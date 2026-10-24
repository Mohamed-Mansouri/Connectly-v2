using System.Globalization;
using Connectly.Api.Data;
using Connectly.Api.Models;

namespace Connectly.Api.Services;

public sealed class MessagingService(TursoDatabase database)
{
    private const string Connected = """
        (EXISTS(SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followed_id = u.id)
         OR EXISTS(SELECT 1 FROM friendships f WHERE f.status = 'accepted'
           AND ((f.user_low_id = ? AND f.user_high_id = u.id) OR (f.user_high_id = ? AND f.user_low_id = u.id))))
        """;

    private const string ConversationSelect = """
        SELECT c.id, c.kind, c.created_at,
          CASE WHEN c.kind = 'group' THEN c.title ELSE
            (SELECT u.name FROM conversation_members m JOIN users u ON u.id = m.user_id
             WHERE m.conversation_id = c.id AND m.user_id <> mine.user_id LIMIT 1) END AS title,
          (SELECT COUNT(*) FROM conversation_members m WHERE m.conversation_id = c.id) AS member_count,
          last.body AS last_body, last.created_at AS last_message_at, sender.name AS last_sender_name,
          (SELECT COUNT(*) FROM messages msg WHERE msg.conversation_id = c.id
            AND msg.sequence > mine.last_read_sequence AND msg.sender_id <> mine.user_id) AS unread_count
        FROM conversations c JOIN conversation_members mine ON mine.conversation_id = c.id AND mine.user_id = ?
        LEFT JOIN messages last ON last.sequence = (SELECT MAX(msg.sequence) FROM messages msg WHERE msg.conversation_id = c.id)
        LEFT JOIN users sender ON sender.id = last.sender_id
        """;

    private static ChatConversation Conversation(Dictionary<string, string?> row) => new(
        row["id"]!, row["kind"]!, row["title"] ?? "Conversation",
        int.Parse(row["member_count"]!, CultureInfo.InvariantCulture), row["created_at"]!, row["last_body"],
        row["last_sender_name"], row["last_message_at"], long.Parse(row["unread_count"]!, CultureInfo.InvariantCulture));

    private static ChatMessage Message(Dictionary<string, string?> row) => new(
        long.Parse(row["sequence"]!, CultureInfo.InvariantCulture), row["client_id"]!,
        new ChatPerson(row["sender_id"]!, row["sender_name"]!), row["body"]!, row["created_at"]!);

    private const string MessageSelect = """
        SELECT msg.sequence, msg.client_id, msg.sender_id, u.name AS sender_name, msg.body, msg.created_at
        FROM messages msg JOIN users u ON u.id = msg.sender_id
        """;

    public async Task<IReadOnlyList<ChatPerson>> ContactsAsync(string userId, string? search, CancellationToken ct)
    {
        if (search?.Length > 80) throw new ApiException(400, "invalid_search", "Search using at most 80 characters.");
        var result = await database.ExecuteAsync("SELECT u.id, u.name FROM users u WHERE u.id <> ? AND " + Connected +
            " AND instr(lower(u.name), lower(?)) > 0 ORDER BY u.name COLLATE NOCASE, u.id LIMIT 50",
            ct, userId, userId, userId, userId, search?.Trim() ?? "");
        return result.Rows.Select(row => new ChatPerson(row["id"]!, row["name"]!)).ToArray();
    }

    public async Task<IReadOnlyList<ChatConversation>> ListAsync(string userId, CancellationToken ct)
    {
        var result = await database.ExecuteAsync(ConversationSelect +
            " ORDER BY COALESCE(last.created_at, c.created_at) DESC, c.id DESC LIMIT 100", ct, userId);
        return result.Rows.Select(Conversation).ToArray();
    }

    private async Task<ChatConversation> FindAsync(string userId, string conversationId, CancellationToken ct)
    {
        var result = await database.ExecuteAsync(ConversationSelect + " WHERE c.id = ?", ct, userId, conversationId);
        if (result.Rows.Count == 0) throw new ApiException(404, "conversation_not_found", "This conversation is not available to your account.");
        return Conversation(result.Rows[0]);
    }

    private async Task EnsureMemberAsync(string userId, string conversationId, CancellationToken ct)
    {
        var result = await database.ExecuteAsync("SELECT user_id FROM conversation_members WHERE conversation_id = ? AND user_id = ?", ct, conversationId, userId);
        if (result.Rows.Count == 0) throw new ApiException(404, "conversation_not_found", "This conversation is not available to your account.");
    }

    public async Task<ChatConversation> CreateAsync(string userId, CreateConversationRequest request, CancellationToken ct)
    {
        if (request.Kind is not ("direct" or "group")) throw new ApiException(400, "invalid_kind", "Choose a direct or group conversation.");
        var ids = request.MemberIds.Select(id => Guid.TryParse(id, out var value) ? value.ToString() : "").ToArray();
        if (ids.Contains("") || ids.Contains(userId) || ids.Distinct().Count() != ids.Length ||
            (request.Kind == "direct" && ids.Length != 1) || (request.Kind == "group" && ids.Length < 2))
            throw new ApiException(400, "invalid_members", "Choose one person for a direct chat, or 2–19 people for a group.");
        var title = request.Title?.Trim() ?? "";
        if (request.Kind == "group" && (title.Length < 2 || title.Length > 80))
            throw new ApiException(400, "invalid_title", "Group names need 2–80 characters.");
        var slots = string.Join(',', ids.Select(_ => "?"));
        var eligible = await database.ExecuteAsync("SELECT u.id FROM users u WHERE u.id IN (" + slots + ") AND " + Connected,
            ct, [.. ids, userId, userId, userId]);
        if (eligible.Rows.Count != ids.Length) throw new ApiException(403, "not_connected", "Start chats with friends or people you follow. Refresh your contacts and try again.");
        var id = Guid.NewGuid().ToString();
        var now = AuthService.Timestamp(DateTimeOffset.UtcNow);
        var statements = new List<SqlStatement>();
        if (request.Kind == "direct")
        {
            var key = string.Join(':', new[] { userId, ids[0] }.Order(StringComparer.Ordinal));
            statements.Add(new SqlStatement("INSERT INTO conversations (id, kind, direct_key, created_by, created_at) VALUES (?, 'direct', ?, ?, ?) ON CONFLICT(direct_key) DO NOTHING", id, key, userId, now));
            foreach (var memberId in ids.Append(userId))
                statements.Add(new SqlStatement("INSERT INTO conversation_members (conversation_id, user_id) SELECT id, ? FROM conversations WHERE direct_key = ? ON CONFLICT DO NOTHING", memberId, key));
            await database.BatchAsync(statements, ct);
            var existing = await database.ExecuteAsync("SELECT id FROM conversations WHERE direct_key = ?", ct, key);
            id = existing.Rows[0]["id"]!;
        }
        else
        {
            statements.Add(new SqlStatement("INSERT INTO conversations (id, kind, title, created_by, created_at) VALUES (?, 'group', ?, ?, ?)", id, title, userId, now));
            foreach (var memberId in ids.Append(userId))
                statements.Add(new SqlStatement("INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?)", id, memberId));
            await database.BatchAsync(statements, ct);
        }
        return await FindAsync(userId, id, ct);
    }

    public async Task<IReadOnlyList<ChatPerson>> MembersAsync(string userId, string id, CancellationToken ct)
    {
        await EnsureMemberAsync(userId, id, ct);
        var result = await database.ExecuteAsync("SELECT u.id, u.name FROM conversation_members m JOIN users u ON u.id = m.user_id WHERE m.conversation_id = ? ORDER BY u.name COLLATE NOCASE, u.id", ct, id);
        return result.Rows.Select(row => new ChatPerson(row["id"]!, row["name"]!)).ToArray();
    }

    public async Task<MessagePage> MessagesAsync(string userId, string id, long? before, long? after, CancellationToken ct)
    {
        await EnsureMemberAsync(userId, id, ct);
        if ((before.HasValue && after.HasValue) || before < 1 || after < 0)
            throw new ApiException(400, "invalid_cursor", "Refresh the conversation and try again.");
        var args = new List<string> { id };
        var query = MessageSelect + " WHERE msg.conversation_id = ?";
        if (before.HasValue) { query += " AND msg.sequence < ?"; args.Add(before.Value.ToString(CultureInfo.InvariantCulture)); }
        if (after.HasValue) { query += " AND msg.sequence > ?"; args.Add(after.Value.ToString(CultureInfo.InvariantCulture)); }
        query += after.HasValue ? " ORDER BY msg.sequence ASC LIMIT 51" : " ORDER BY msg.sequence DESC LIMIT 51";
        var result = await database.ExecuteAsync(query, ct, args.ToArray());
        var messages = result.Rows.Take(50).Select(Message).ToArray();
        if (!after.HasValue) Array.Reverse(messages);
        return new MessagePage(messages, !after.HasValue && result.Rows.Count > 50 ? messages[0].Sequence : null,
            after.HasValue && result.Rows.Count > 50);
    }

    public async Task<ChatMessage> SendAsync(string userId, string id, SendMessageRequest request, CancellationToken ct)
    {
        await EnsureMemberAsync(userId, id, ct);
        if (!Guid.TryParse(request.ClientId, out var parsed)) throw new ApiException(400, "invalid_client_id", "Refresh the conversation and try again.");
        var body = request.Body.Trim();
        if (body.Length == 0 || body.Length > 4000) throw new ApiException(400, "invalid_message", "Messages need 1–4,000 characters.");
        var clientId = parsed.ToString();
        await database.ExecuteAsync("""
            INSERT INTO messages (conversation_id, sender_id, client_id, body, created_at) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(conversation_id, sender_id, client_id) DO NOTHING
            """, ct, id, userId, clientId, body, AuthService.Timestamp(DateTimeOffset.UtcNow));
        var result = await database.ExecuteAsync(MessageSelect + " WHERE msg.conversation_id = ? AND msg.sender_id = ? AND msg.client_id = ?", ct, id, userId, clientId);
        if (result.Rows[0]["body"] != body) throw new ApiException(409, "message_changed", "This retry differs from the original message. Refresh the conversation.");
        return Message(result.Rows[0]);
    }

    public async Task MarkReadAsync(string userId, string id, long through, CancellationToken ct)
    {
        await EnsureMemberAsync(userId, id, ct);
        await database.ExecuteAsync("""
            UPDATE conversation_members SET last_read_sequence = MAX(last_read_sequence,
              COALESCE((SELECT MAX(sequence) FROM messages WHERE conversation_id = ? AND sequence <= CAST(? AS INTEGER)), 0))
            WHERE conversation_id = ? AND user_id = ?
            """, ct, id, through.ToString(CultureInfo.InvariantCulture), id, userId);
    }
}

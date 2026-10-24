using System.Globalization;
using Connectly.Api.Data;
using Connectly.Api.Models;

namespace Connectly.Api.Services;

public sealed class FeedService(TursoDatabase database)
{
    private static readonly string[] ReactionKinds = ["like", "love", "celebrate", "insightful"];

    private const string Friends = """
        EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'accepted'
          AND ((f.user_low_id = ? AND f.user_high_id = p.author_id)
            OR (f.user_high_id = ? AND f.user_low_id = p.author_id)))
        """;
    private const string Following = "EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followed_id = p.author_id)";

    private static (string Clause, string[] Args) Visibility(string userId, string scope) => scope switch
    {
        "connections" => ($"(p.author_id = ? OR {Following} OR {Friends})", [userId, userId, userId, userId]),
        "friends" => ($"(p.author_id = ? OR {Friends})", [userId, userId, userId]),
        "following" => ($"(p.author_id = ? OR {Following})", [userId, userId]),
        _ => throw new ApiException(400, "invalid_scope", "Choose Connections, Friends, or Following.")
    };

    private static string SelectPost => """
        SELECT p.id, p.author_id, u.name AS author_name, p.body, p.created_at,
          (SELECT r.kind FROM post_reactions r WHERE r.post_id = p.id AND r.user_id = ?) AS my_reaction,
          (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id AND r.kind = 'like') AS likes,
          (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id AND r.kind = 'love') AS loves,
          (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id AND r.kind = 'celebrate') AS celebrates,
          (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id AND r.kind = 'insightful') AS insights
        FROM posts p JOIN users u ON u.id = p.author_id
        """;

    private static FeedPost Post(Dictionary<string, string?> row) => new(row["id"]!,
        new PostAuthor(row["author_id"]!, row["author_name"]!), row["body"]!, row["created_at"]!,
        new Dictionary<string, int> {
            ["like"] = int.Parse(row["likes"]!, CultureInfo.InvariantCulture),
            ["love"] = int.Parse(row["loves"]!, CultureInfo.InvariantCulture),
            ["celebrate"] = int.Parse(row["celebrates"]!, CultureInfo.InvariantCulture),
            ["insightful"] = int.Parse(row["insights"]!, CultureInfo.InvariantCulture)
        }, row["my_reaction"]);

    public async Task<FeedPage> ListAsync(string userId, string scope, string? cursor, CancellationToken ct)
    {
        var visibility = Visibility(userId, scope);
        var args = new List<string> { userId };
        args.AddRange(visibility.Args);
        var boundary = "";
        if (!string.IsNullOrEmpty(cursor))
        {
            var parts = cursor.Split('|');
            if (parts.Length != 2 || !DateTimeOffset.TryParseExact(parts[0], "yyyy-MM-dd'T'HH:mm:ss.fff'Z'",
                    CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out _) || !Guid.TryParse(parts[1], out _))
                throw new ApiException(400, "invalid_cursor", "Refresh the feed and try again.");
            boundary = " AND (p.created_at < ? OR (p.created_at = ? AND p.id < ?))";
            args.AddRange([parts[0], parts[0], parts[1]]);
        }
        var result = await database.ExecuteAsync(SelectPost + " WHERE " + visibility.Clause + boundary +
            " ORDER BY p.created_at DESC, p.id DESC LIMIT 21", ct, args.ToArray());
        var posts = result.Rows.Take(20).Select(Post).ToArray();
        var next = result.Rows.Count > 20 ? posts[^1].CreatedAt + "|" + posts[^1].Id : null;
        return new FeedPage(posts, next);
    }

    private async Task<FeedPost> FindAsync(string userId, string postId, CancellationToken ct)
    {
        var visibility = Visibility(userId, "connections");
        var result = await database.ExecuteAsync(SelectPost + " WHERE p.id = ? AND " + visibility.Clause,
            ct, [userId, postId, .. visibility.Args]);
        if (result.Rows.Count == 0)
            throw new ApiException(404, "post_not_found", "This post is no longer available in your feed.");
        return Post(result.Rows[0]);
    }

    public async Task<FeedPost> CreateAsync(string userId, CreatePostRequest request, CancellationToken ct)
    {
        var body = request.Body.Trim();
        if (body.Length == 0 || body.Length > 3000)
            throw new ApiException(400, "invalid_post", "Write a post between 1 and 3,000 characters.");
        var id = Guid.NewGuid().ToString();
        await database.ExecuteAsync("INSERT INTO posts (id, author_id, body, created_at) VALUES (?, ?, ?, ?)",
            ct, id, userId, body, AuthService.Timestamp(DateTimeOffset.UtcNow));
        return await FindAsync(userId, id, ct);
    }

    public async Task DeleteAsync(string userId, string postId, CancellationToken ct)
    {
        // Explicit cleanup also works when a remote connection has foreign_keys disabled.
        await database.BatchAsync([
            new SqlStatement("DELETE FROM post_reactions WHERE post_id IN (SELECT id FROM posts WHERE id = ? AND author_id = ?)", postId, userId),
            new SqlStatement("DELETE FROM posts WHERE id = ? AND author_id = ?", postId, userId)
        ], ct);
    }

    public async Task<FeedPost> ReactAsync(string userId, string postId, string? kind, CancellationToken ct)
    {
        if (kind is not null && !ReactionKinds.Contains(kind, StringComparer.Ordinal))
            throw new ApiException(400, "invalid_reaction", "Choose a supported reaction.");
        await FindAsync(userId, postId, ct);
        if (kind is null)
            await database.ExecuteAsync("DELETE FROM post_reactions WHERE post_id = ? AND user_id = ?", ct, postId, userId);
        else
            await database.ExecuteAsync("""
                INSERT INTO post_reactions (post_id, user_id, kind) VALUES (?, ?, ?)
                ON CONFLICT(post_id, user_id) DO UPDATE SET kind = excluded.kind
                """, ct, postId, userId, kind);
        return await FindAsync(userId, postId, ct);
    }

    public async Task<IReadOnlyList<FeedPerson>> PeopleAsync(string userId, string? search, bool requests, CancellationToken ct)
    {
        if (search?.Length > 80) throw new ApiException(400, "invalid_search", "Search using at most 80 characters.");
        var query = """
            SELECT u.id, u.name,
              EXISTS(SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followed_id = u.id) AS following,
              CASE WHEN f.status = 'accepted' THEN 'friends'
                WHEN f.requested_by = ? THEN 'outgoing'
                WHEN f.status = 'pending' THEN 'incoming' ELSE 'none' END AS friendship
            FROM users u LEFT JOIN friendships f
              ON ((f.user_low_id = ? AND f.user_high_id = u.id) OR (f.user_high_id = ? AND f.user_low_id = u.id))
            WHERE u.id <> ? AND instr(lower(u.name), lower(?)) > 0
            """;
        if (requests) query += " AND f.status = 'pending'";
        query += " ORDER BY CASE WHEN f.status = 'pending' THEN 0 ELSE 1 END, u.name COLLATE NOCASE, u.id LIMIT 50";
        var result = await database.ExecuteAsync(query, ct, userId, userId, userId, userId, userId, search?.Trim() ?? "");
        return result.Rows.Select(row => new FeedPerson(row["id"]!, row["name"]!, row["following"] == "1", row["friendship"]!)).ToArray();
    }

    private async Task EnsurePersonAsync(string userId, string otherId, CancellationToken ct)
    {
        if (userId == otherId) throw new ApiException(400, "self_connection", "Choose another person.");
        var result = await database.ExecuteAsync("SELECT id FROM users WHERE id = ?", ct, otherId);
        if (result.Rows.Count == 0) throw new ApiException(404, "person_not_found", "This person is no longer available.");
    }

    public async Task FollowAsync(string userId, string otherId, bool follow, CancellationToken ct)
    {
        await EnsurePersonAsync(userId, otherId, ct);
        if (follow)
            await database.ExecuteAsync("INSERT INTO follows (follower_id, followed_id, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING",
                ct, userId, otherId, AuthService.Timestamp(DateTimeOffset.UtcNow));
        else
            await database.ExecuteAsync("DELETE FROM follows WHERE follower_id = ? AND followed_id = ?", ct, userId, otherId);
    }

    public async Task FriendshipAsync(string userId, string otherId, string action, CancellationToken ct)
    {
        await EnsurePersonAsync(userId, otherId, ct);
        var low = string.CompareOrdinal(userId, otherId) < 0 ? userId : otherId;
        var high = low == userId ? otherId : userId;
        if (action == "request")
            await database.ExecuteAsync("""
                INSERT INTO friendships (user_low_id, user_high_id, requested_by, status, created_at)
                VALUES (?, ?, ?, 'pending', ?) ON CONFLICT DO NOTHING
                """, ct, low, high, userId, AuthService.Timestamp(DateTimeOffset.UtcNow));
        else if (action == "accept")
        {
            var result = await database.ExecuteAsync("""
                UPDATE friendships SET status = 'accepted'
                WHERE user_low_id = ? AND user_high_id = ? AND requested_by = ? AND status = 'pending'
                """, ct, low, high, otherId);
            if (result.AffectedRows == 0)
                throw new ApiException(409, "request_changed", "This request has changed. Refresh People and try again.");
        }
        else if (action == "remove")
            await database.ExecuteAsync("DELETE FROM friendships WHERE user_low_id = ? AND user_high_id = ?", ct, low, high);
        else throw new ApiException(400, "invalid_action", "Choose a valid friendship action.");
    }
}

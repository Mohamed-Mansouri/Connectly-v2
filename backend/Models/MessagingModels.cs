using System.ComponentModel.DataAnnotations;

namespace Connectly.Api.Models;

public sealed record CreateConversationRequest(
    [Required] string Kind,
    [Required, MinLength(1), MaxLength(19)] string[] MemberIds,
    [StringLength(80)] string? Title);
public sealed record SendMessageRequest(
    [Required] string ClientId,
    [Required, StringLength(4000, MinimumLength = 1)] string Body);
public sealed record ReadConversationRequest([Range(0, long.MaxValue)] long ThroughSequence);
public sealed record ChatPerson(string Id, string Name);
public sealed record ChatConversation(string Id, string Kind, string Title, int MemberCount,
    string CreatedAt, string? LastBody, string? LastSenderName, string? LastMessageAt, long UnreadCount);
public sealed record ChatMessage(long Sequence, string ClientId, ChatPerson Sender, string Body, string CreatedAt);
public sealed record MessagePage(IReadOnlyList<ChatMessage> Messages, long? OlderCursor, bool HasMore);

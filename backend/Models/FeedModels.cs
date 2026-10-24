using System.ComponentModel.DataAnnotations;

namespace Connectly.Api.Models;

public sealed record CreatePostRequest([Required, StringLength(3000, MinimumLength = 1)] string Body);
public sealed record ReactionRequest([Required] string Kind);
public sealed record FriendshipRequest([Required] string Action);
public sealed record PostAuthor(string Id, string Name);
public sealed record FeedPost(string Id, PostAuthor Author, string Body, string CreatedAt,
    Dictionary<string, int> Reactions, string? MyReaction);
public sealed record FeedPage(IReadOnlyList<FeedPost> Posts, string? NextCursor);
public sealed record FeedPerson(string Id, string Name, bool IsFollowing, string Friendship);

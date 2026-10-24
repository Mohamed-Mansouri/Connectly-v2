using Connectly.Api.Models;
using Connectly.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Connectly.Api.Controllers;

[ApiController, Authorize]
public sealed class FeedController(FeedService feed) : ControllerBase
{
    private string UserId => ((AuthUser)HttpContext.Items["authUser"]!).Id;

    [HttpGet("feed")]
    public async Task<IActionResult> List([FromQuery] string scope = "connections", [FromQuery] string? cursor = null, CancellationToken ct = default) =>
        Ok(await feed.ListAsync(UserId, scope, cursor, ct));

    [HttpPost("posts")]
    public async Task<IActionResult> Create(CreatePostRequest request, CancellationToken ct) =>
        StatusCode(201, new { post = await feed.CreateAsync(UserId, request, ct) });

    [HttpDelete("posts/{postId}")]
    public async Task<IActionResult> Delete(string postId, CancellationToken ct)
    {
        await feed.DeleteAsync(UserId, postId, ct);
        return NoContent();
    }

    [HttpPut("posts/{postId}/reaction")]
    public async Task<IActionResult> React(string postId, ReactionRequest request, CancellationToken ct) =>
        Ok(new { post = await feed.ReactAsync(UserId, postId, request.Kind, ct) });

    [HttpDelete("posts/{postId}/reaction")]
    public async Task<IActionResult> RemoveReaction(string postId, CancellationToken ct) =>
        Ok(new { post = await feed.ReactAsync(UserId, postId, null, ct) });

    [HttpGet("people")]
    public async Task<IActionResult> People([FromQuery] string? search = null, [FromQuery] bool requests = false, CancellationToken ct = default) =>
        Ok(new { people = await feed.PeopleAsync(UserId, search, requests, ct) });

    [HttpPut("people/{personId}/follow")]
    public async Task<IActionResult> Follow(string personId, CancellationToken ct)
    {
        await feed.FollowAsync(UserId, personId, true, ct);
        return NoContent();
    }

    [HttpDelete("people/{personId}/follow")]
    public async Task<IActionResult> Unfollow(string personId, CancellationToken ct)
    {
        await feed.FollowAsync(UserId, personId, false, ct);
        return NoContent();
    }

    [HttpPut("people/{personId}/friendship")]
    public async Task<IActionResult> Friendship(string personId, FriendshipRequest request, CancellationToken ct)
    {
        await feed.FriendshipAsync(UserId, personId, request.Action, ct);
        return NoContent();
    }
}

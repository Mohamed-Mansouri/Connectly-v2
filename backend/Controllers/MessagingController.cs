using Connectly.Api.Models;
using Connectly.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Connectly.Api.Controllers;

[ApiController, Authorize, Route("conversations")]
public sealed class MessagingController(MessagingService messaging) : ControllerBase
{
    private string UserId => ((AuthUser)HttpContext.Items["authUser"]!).Id;

    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) => Ok(new { conversations = await messaging.ListAsync(UserId, ct) });

    [HttpGet("contacts")]
    public async Task<IActionResult> Contacts([FromQuery] string? search, CancellationToken ct) => Ok(new { contacts = await messaging.ContactsAsync(UserId, search, ct) });

    [HttpPost]
    public async Task<IActionResult> Create(CreateConversationRequest request, CancellationToken ct) =>
        StatusCode(201, new { conversation = await messaging.CreateAsync(UserId, request, ct) });

    [HttpGet("{id}/members")]
    public async Task<IActionResult> Members(string id, CancellationToken ct) => Ok(new { members = await messaging.MembersAsync(UserId, id, ct) });

    [HttpGet("{id}/messages")]
    public async Task<IActionResult> Messages(string id, [FromQuery] long? before, [FromQuery] long? after, CancellationToken ct) =>
        Ok(await messaging.MessagesAsync(UserId, id, before, after, ct));

    [HttpPost("{id}/messages")]
    public async Task<IActionResult> Send(string id, SendMessageRequest request, CancellationToken ct) =>
        StatusCode(201, new { message = await messaging.SendAsync(UserId, id, request, ct) });

    [HttpPost("{id}/read")]
    public async Task<IActionResult> Read(string id, ReadConversationRequest request, CancellationToken ct)
    {
        await messaging.MarkReadAsync(UserId, id, request.ThroughSequence, ct);
        return NoContent();
    }
}

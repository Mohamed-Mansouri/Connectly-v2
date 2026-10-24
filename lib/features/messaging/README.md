# Messaging module

The Chats tab supports authenticated direct and group text conversations through the .NET 10 API and Turso. The project owner confirmed messaging working on the connected phone on **2026-10-24**.

## Views and functions

| View | Working behavior |
| --- | --- |
| Inbox | Recent conversations, local name search, last-message preview, unread count, pull to refresh, and New conversation. Guests see a sign-in invitation. |
| New conversation | Select one friend/followed person for a direct chat, or name a group and select 2–19 others. Existing direct chats reopen rather than duplicate. Members are fixed at creation in this version. |
| Conversation | Incoming/outgoing bubbles, real sender names in groups, dates/times, earlier history, keyboard-aware composer, send progress, failed-message retry, and saved drafts. Text is trimmed and limited to 4,000 characters. |
| Members | Read-only names of conversation participants; membership is checked by the server. |

The inbox polls every 10 seconds while its tab is visible and the app is active. An open conversation polls every 5 seconds and marks fetched messages read while active. Polling pauses in the background and when another route covers the screen. This is polling, without push delivery, presence, typing indicators, or per-message read receipts. Inbox lists the most recent 100 conversations; contact searches return up to 50 results. History loads 50 messages per page using server sequence cursors.

New chats can include accepted friends or people the creator follows. Existing conversation membership remains valid if a connection is later removed. Only members can list members, fetch/send messages, or update their own unread cursor. The server derives the sender from the session and does not expose email/password fields in chat responses.

## Source map

- `presentation/messages_screen.dart`: inbox, active-tab polling, authenticated repository, local store initialization, and route creation.
- `presentation/new_conversation_screen.dart`: contact search, direct/group selection, validation, creation.
- `presentation/conversation_screen.dart`: bubbles, composer, pending retries, lifecycle handling, and member sheet.
- `application/chat_controller.dart`: draft restoration, history merge/pagination, incremental polling, read markers, send/retry, and serialized local writes.
- `data/messaging_api.dart`: bearer-authenticated HTTP repository; uses the same `API_BASE_URL` as auth/feed.
- `data/chat_local_store.dart`: Hive and memory implementations for drafts and pending messages.
- `backend/Controllers/MessagingController.cs`, `Services/MessagingService.cs`, `Models/MessagingModels.cs`, and `migrations/003_messaging.sql`: routes, access rules, and shared records.

## Storage, retries, and offline behavior

Hive's `Box<String>('messaging_local')` uses `<userId>:<conversationId>` keys. Each JSON record contains the current `draft` and an `outbox` of `{ clientId, body, createdAt }`. Draft edits save after 250 ms; leaving a conversation also queues a save. Empty records are deleted. Records survive logout but are loaded only for their matching account/conversation. Tokens/passwords are not stored in this box. There is no draft TTL or persistent server-history cache.

Sending first saves a pending message with a stable UUID, then calls the server. The server's unique `(conversation_id, sender_id, client_id)` constraint makes retrying that message idempotent. The pending item clears after confirmation or when polling finds its server copy. Sending a reply does not skip intervening incoming messages because polling maintains a separate cursor.

On restart, pending items become **Not confirmed** with an explicit Retry action; they are not automatically resent. A local write failure prevents that send and retains the pending text in memory. If Hive cannot open, an in-memory store keeps the screen usable and a notice explains that drafts will not survive app closure. Offline history is limited to messages already loaded in the running screen; startup account restoration still needs the API. Failed sends retain text/IDs for retry, and polling resumes when the active app can connect again.

Turso holds `conversations`, `conversation_members` (including each member's read cursor), and `messages`. Message bodies/IDs are shared through authenticated endpoints; local drafts stay on the device. See [API setup and routes](../../../backend/README.md#messaging).

## Verification and future work

All **48 Flutter tests** pass, analysis reports no issues, the .NET build succeeds, and the live messaging check passed on 2026-10-24. [Test-Messaging.ps1](../../../backend/tests/Test-Messaging.ps1) checks temporary accounts for connection eligibility, private access, direct-chat deduplication, message retries, groups, unread markers, and both history/polling pagination. It cleans up only its generated records. Default test port: 8789.

Attachments, voice recording/transcription/translation, message search, group membership management, editing/deletion, push notifications, and persistent history caching remain planned. The advanced demonstration will record a voice message, transcribe/translate it, and make its text searchable. The supplied group chat reference remains on `archive/sprint-0` at `design/reference/group_chat.png`.

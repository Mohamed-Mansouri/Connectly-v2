# Messaging module

The Chats tab now uses `SqliteMessagingRepository` and the phone's `connectly_local.db` for direct/group text conversations. It needs no API, internet, or PC connection. Create multiple accounts on this phone and switch between them to demonstrate messages; other phones have independent databases.

## Views and functions

| View | Working behavior |
| --- | --- |
| Chats | Accepted friends are listed directly above recent conversations. Tap a friend to open their existing direct chat or create it on first tap. Search covers friends and chats; previews, unread counts, and pull to refresh remain. Guests see a sign-in invitation. |
| Existing groups | Group conversations remain in Recent chats. The previous New conversation screen is retained in source but is no longer linked from Chats. |
| Conversation | Incoming/outgoing bubbles, real sender names in groups, dates/times, earlier history, keyboard-aware composer, send progress, failed-message retry, and saved drafts. Text is trimmed and limited to 4,000 characters. |
| Members | Read-only names of conversation participants; membership is checked by the SQLite repository. |

The inbox refreshes SQLite every 10 seconds while visible; an active conversation refreshes every 5 seconds and updates its local read cursor. Refresh pauses in the background or behind another route. These are local database reads with no HTTP requests. Inbox lists the most recent 100 conversations; contact searches return up to 50. History loads 50 messages per page using SQLite sequence cursors.

The Chats friend list includes accepted friendships only. The repository still permits direct chats with followed accounts and preserves existing membership after a connection is removed. Only members can read/write the conversation or update their own unread cursor. The repository uses the signed-in account as sender and exposes names/IDs without password fields.

## Source map

- `presentation/messages_screen.dart`: inbox, active-tab polling, authenticated repository, local store initialization, and route creation.
- `presentation/new_conversation_screen.dart`: retained group creation screen, currently not linked from Chats.
- `presentation/conversation_screen.dart`: bubbles, composer, pending retries, lifecycle handling, and member sheet.
- `application/chat_controller.dart`: draft restoration, history merge/pagination, incremental polling, read markers, send/retry, and serialized local writes.
- `data/sqlite_messaging_repository.dart`: local SQLite contacts, conversations, messages, membership, unread counts, and retry deduplication. The old HTTP repository remains reference code.
- `data/chat_local_store.dart`: Hive and memory implementations for drafts and pending messages.
- `lib/shared/data/local_schema.dart`: conversations, memberships, messages, foreign keys, indexes, and uniqueness constraints.

## Storage, retries, and offline behavior

Hive's `Box<String>('messaging_local')` uses `<userId>:<conversationId>` keys. Each JSON record contains the current `draft` and an `outbox` of `{ clientId, body, createdAt }`. Draft edits save after 250 ms; leaving queues a save. Empty records are deleted. Records survive logout but load only for their matching account/conversation. Tokens/passwords are not stored in this box. Full message history persists separately in SQLite.

Sending first saves a pending message with a stable UUID, then inserts it into SQLite. The unique `(conversation_id, sender_id, client_id)` constraint deduplicates retries. Pending items clear after insertion or when a refresh finds the stored copy. History refresh uses a separate cursor so sending does not skip intervening messages.

On restart, pending items become **Not confirmed** with Retry; they are not automatically resent. Local write failure retains pending text in memory and stops that send. If Hive cannot open, temporary memory keeps the screen usable with a notice. Account restoration and full SQLite history work offline after restart.

SQLite holds `conversations`, `conversation_members` (including read cursors), and `messages`. See [local architecture and presentation steps](../../../README.md).

## Verification and future work

Run `flutter test` and `flutter analyze`. The real SQLite tests cover direct/group membership, retry deduplication, unread markers, both cursors, and database reopening. The app-level test renders Feed/Chats with HTTP clients blocked. Earlier backend integration scripts remain reference code and are not used for this local presentation.

Attachments, voice recording/transcription/translation, message search, group membership management, editing/deletion, push notifications, and persistent history caching remain planned. The advanced demonstration will record a voice message, transcribe/translate it, and make its text searchable. The supplied group chat reference remains on `archive/sprint-0` at `design/reference/group_chat.png`.

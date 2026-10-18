# Messaging module

This branch owns the Chats tab. `module_entry.dart` connects the navigation shell to `presentation/messages_screen.dart`. The screen is an empty starting view; conversations, group chat, voice recording, and API calls are still to be built.

Planned endpoints: `GET/POST /conversations` and `GET/POST /conversations/{id}/messages`. The advanced demonstration records a voice message, transcribes and translates it, then makes its text searchable. The supplied group chat mockup remains on `archive/sprint-0` at `design/reference/group_chat.png`.

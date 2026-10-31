import 'dart:typed_data';
import 'package:connectly/features/messaging/domain/messaging_models.dart';

final testConversation = Conversation(
    id: 'chat-1',
    kind: 'direct',
    title: 'Another Member',
    memberCount: 2,
    createdAt: DateTime.utc(2026, 10, 24),
    peerId: 'other');
ChatMessage testMessage(int sequence,
        {String? clientId,
        String senderId = 'other',
        String? body,
        int? voiceDurationMs}) =>
    ChatMessage(
        sequence: sequence,
        clientId: clientId ?? 'message-$sequence',
        sender: ChatPerson(
            senderId, senderId == 'user-1' ? 'Test Member' : 'Another Member'),
        body: body ?? 'Message $sequence',
        createdAt: DateTime.utc(2026, 10, 24, 12, 0, sequence),
        voiceDurationMs: voiceDurationMs);

class FakeMessagingRepository implements MessagingRepository {
  List<ChatMessage> history = [];
  List<Conversation> inbox = [testConversation];
  List<ChatPerson> people = [
    const ChatPerson('other', 'Another Member'),
    const ChatPerson('third', 'Third Member')
  ];
  List<ChatPerson> friendsList = [const ChatPerson('other', 'Another Member')];
  Future<MessagePage> Function(int?, int?)? onMessages;
  Future<ChatMessage> Function(String, String)? onSend;
  int inboxCalls = 0;
  int messageCalls = 0;
  final sentIds = <String>[];
  final readMarkers = <int>[];
  final voiceClips = <int, Uint8List>{};
  String? createdKind;
  List<String>? createdMembers;
  String? createdTitle;
  @override
  Future<List<Conversation>> conversations() async {
    inboxCalls++;
    return inbox;
  }

  @override
  Future<List<ChatPerson>> contacts(String search) async => people;
  @override
  Future<List<ChatPerson>> friends() async => friendsList;
  @override
  Future<Conversation> create(
      {required String kind,
      required List<String> memberIds,
      String? title}) async {
    createdKind = kind;
    createdMembers = memberIds;
    createdTitle = title;
    return testConversation;
  }

  @override
  Future<List<ChatPerson>> members(String conversationId) async =>
      [const ChatPerson('user-1', 'Test Member'), ...people];
  @override
  Future<MessagePage> messages(String conversationId,
      {int? before, int? after}) async {
    messageCalls++;
    if (onMessages != null) return await onMessages!(before, after);
    return MessagePage(history
        .where((m) =>
            (before == null || m.sequence < before) &&
            (after == null || m.sequence > after))
        .toList());
  }

  @override
  Future<ChatMessage> send(
      String conversationId, String clientId, String body) async {
    sentIds.add(clientId);
    if (onSend != null) return await onSend!(clientId, body);
    final existing =
        history.where((m) => m.clientId == clientId && m.sender.id == 'user-1');
    if (existing.isNotEmpty) return existing.first;
    final message = testMessage(history.isEmpty ? 1 : history.last.sequence + 1,
        clientId: clientId, senderId: 'user-1', body: body);
    history.add(message);
    return message;
  }

  @override
  Future<ChatMessage> sendVoice(String conversationId, String clientId,
      Uint8List bytes, int durationMs) async {
    sentIds.add(clientId);
    final existing = history.where((message) => message.clientId == clientId);
    if (existing.isNotEmpty) return existing.single;
    final message = testMessage(history.isEmpty ? 1 : history.last.sequence + 1,
        clientId: clientId,
        senderId: 'user-1',
        body: 'Voice message',
        voiceDurationMs: durationMs);
    history.add(message);
    voiceClips[message.sequence] = bytes;
    return message;
  }

  @override
  Future<Uint8List> voiceBytes(String conversationId, int sequence) async =>
      voiceClips[sequence]!;

  @override
  Future<void> markRead(String conversationId, int throughSequence) async {
    readMarkers.add(throughSequence);
  }
}

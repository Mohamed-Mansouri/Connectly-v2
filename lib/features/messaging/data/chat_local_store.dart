import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

class QueuedMessage {
  QueuedMessage(
      {required this.clientId,
      required this.body,
      required this.createdAt,
      this.sending = false,
      this.error});
  final String clientId;
  final String body;
  final DateTime createdAt;
  bool sending;
  String? error;
  Map<String, Object> toJson() => {
        'clientId': clientId,
        'body': body,
        'createdAt': createdAt.toIso8601String()
      };
  factory QueuedMessage.fromJson(Map<String, dynamic> json) => QueuedMessage(
      clientId: json['clientId'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      error: 'Not confirmed. Tap Retry to check or send it.');
}

class ChatLocalData {
  const ChatLocalData({this.draft = '', this.outbox = const []});
  final String draft;
  final List<QueuedMessage> outbox;
  String encode() => jsonEncode(
      {'draft': draft, 'outbox': outbox.map((m) => m.toJson()).toList()});
  factory ChatLocalData.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    return ChatLocalData(
        draft: json['draft'] as String,
        outbox: (json['outbox'] as List)
            .map((m) => QueuedMessage.fromJson(m as Map<String, dynamic>))
            .toList());
  }
}

abstract class ChatLocalStore {
  Future<ChatLocalData> read(String userId, String conversationId);
  Future<void> write(String userId, String conversationId, String encoded);
}

class HiveChatLocalStore implements ChatLocalStore {
  HiveChatLocalStore(this.box);
  final Box<String> box;
  static Future<HiveChatLocalStore> open() async {
    await Hive.initFlutter();
    return HiveChatLocalStore(await Hive.openBox<String>('messaging_local'));
  }

  String _key(String userId, String conversationId) =>
      '$userId:$conversationId';
  @override
  Future<ChatLocalData> read(String userId, String conversationId) async {
    final value = box.get(_key(userId, conversationId));
    return value == null ? const ChatLocalData() : ChatLocalData.decode(value);
  }

  @override
  Future<void> write(
      String userId, String conversationId, String encoded) async {
    final data = ChatLocalData.decode(encoded);
    if (data.draft.isEmpty && data.outbox.isEmpty) {
      await box.delete(_key(userId, conversationId));
    } else {
      await box.put(_key(userId, conversationId), encoded);
    }
  }
}

class MemoryChatLocalStore implements ChatLocalStore {
  final _values = <String, String>{};
  @override
  Future<ChatLocalData> read(String userId, String conversationId) async {
    final value = _values['$userId:$conversationId'];
    return value == null ? const ChatLocalData() : ChatLocalData.decode(value);
  }

  @override
  Future<void> write(
      String userId, String conversationId, String encoded) async {
    _values['$userId:$conversationId'] = encoded;
  }
}

class ChatPerson {
  const ChatPerson(this.id, this.name);
  final String id;
  final String name;
  factory ChatPerson.fromJson(Map<String, dynamic> json) =>
      ChatPerson(json['id'] as String, json['name'] as String);
}

class Conversation {
  const Conversation(
      {required this.id,
      required this.kind,
      required this.title,
      required this.memberCount,
      required this.createdAt,
      this.lastBody,
      this.lastSenderName,
      this.lastMessageAt,
      this.unreadCount = 0});
  final String id;
  final String kind;
  final String title;
  final int memberCount;
  final DateTime createdAt;
  final String? lastBody;
  final String? lastSenderName;
  final DateTime? lastMessageAt;
  final int unreadCount;
  bool get isGroup => kind == 'group';
  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
      id: json['id'] as String,
      kind: json['kind'] as String,
      title: json['title'] as String,
      memberCount: json['memberCount'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastBody: json['lastBody'] as String?,
      lastSenderName: json['lastSenderName'] as String?,
      lastMessageAt: json['lastMessageAt'] == null
          ? null
          : DateTime.parse(json['lastMessageAt'] as String),
      unreadCount: json['unreadCount'] as int);
}

class ChatMessage {
  const ChatMessage(
      {required this.sequence,
      required this.clientId,
      required this.sender,
      required this.body,
      required this.createdAt});
  final int sequence;
  final String clientId;
  final ChatPerson sender;
  final String body;
  final DateTime createdAt;
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
      sequence: json['sequence'] as int,
      clientId: json['clientId'] as String,
      sender: ChatPerson.fromJson(json['sender'] as Map<String, dynamic>),
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String));
}

class MessagePage {
  const MessagePage(this.messages, {this.olderCursor, this.hasMore = false});
  final List<ChatMessage> messages;
  final int? olderCursor;
  final bool hasMore;
}

class MessagingException implements Exception {
  const MessagingException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
}

abstract class MessagingRepository {
  Future<List<Conversation>> conversations();
  Future<List<ChatPerson>> contacts(String search);
  Future<Conversation> create(
      {required String kind, required List<String> memberIds, String? title});
  Future<List<ChatPerson>> members(String conversationId);
  Future<MessagePage> messages(String conversationId,
      {int? before, int? after});
  Future<ChatMessage> send(String conversationId, String clientId, String body);
  Future<void> markRead(String conversationId, int throughSequence);
}

import 'package:sqflite/sqflite.dart';
import '../../../shared/data/local_database.dart';
import '../domain/messaging_models.dart';

class SqliteMessagingRepository implements MessagingRepository {
  SqliteMessagingRepository(this.database, this.userId);
  final LocalDatabase database;
  final String userId;
  static const _connected =
      '''(EXISTS(SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followed_id = u.id)
    OR EXISTS(SELECT 1 FROM friendships f WHERE f.status = 'accepted'
      AND ((f.user_low_id = ? AND f.user_high_id = u.id) OR (f.user_high_id = ? AND f.user_low_id = u.id))))''';
  static const _conversationSelect = '''SELECT c.id, c.kind, c.created_at,
    CASE WHEN c.kind = 'group' THEN c.title ELSE
      (SELECT u.name FROM conversation_members m JOIN users u ON u.id = m.user_id
       WHERE m.conversation_id = c.id AND m.user_id <> mine.user_id LIMIT 1) END AS title,
    CASE WHEN c.kind = 'direct' THEN
      (SELECT m.user_id FROM conversation_members m
       WHERE m.conversation_id = c.id AND m.user_id <> mine.user_id LIMIT 1)
      ELSE NULL END AS peer_id,
    (SELECT COUNT(*) FROM conversation_members m WHERE m.conversation_id = c.id) AS member_count,
    last.body AS last_body, last.created_at AS last_message_at, sender.name AS last_sender_name,
    (SELECT COUNT(*) FROM messages msg WHERE msg.conversation_id = c.id
      AND msg.sequence > mine.last_read_sequence AND msg.sender_id <> mine.user_id) AS unread_count
    FROM conversations c JOIN conversation_members mine ON mine.conversation_id = c.id AND mine.user_id = ?
    LEFT JOIN messages last ON last.sequence = (SELECT MAX(msg.sequence) FROM messages msg WHERE msg.conversation_id = c.id)
    LEFT JOIN users sender ON sender.id = last.sender_id''';
  static const _messageSelect =
      '''SELECT msg.sequence, msg.client_id, msg.sender_id, u.name AS sender_name, msg.body, msg.created_at
    FROM messages msg JOIN users u ON u.id = msg.sender_id''';
  Conversation _conversation(Map<String, Object?> r) => Conversation(
      id: r['id'] as String,
      kind: r['kind'] as String,
      title: r['title'] as String? ?? 'Conversation',
      memberCount: r['member_count'] as int,
      createdAt: DateTime.parse(r['created_at'] as String),
      peerId: r['peer_id'] as String?,
      lastBody: r['last_body'] as String?,
      lastSenderName: r['last_sender_name'] as String?,
      lastMessageAt: r['last_message_at'] == null
          ? null
          : DateTime.parse(r['last_message_at'] as String),
      unreadCount: r['unread_count'] as int);
  ChatMessage _message(Map<String, Object?> r) => ChatMessage(
      sequence: r['sequence'] as int,
      clientId: r['client_id'] as String,
      sender: ChatPerson(r['sender_id'] as String, r['sender_name'] as String),
      body: r['body'] as String,
      createdAt: DateTime.parse(r['created_at'] as String));
  @override
  Future<List<Conversation>> conversations() async {
    final rows = await database.db.rawQuery(
        '$_conversationSelect ORDER BY COALESCE(last.created_at, c.created_at) DESC, c.id DESC LIMIT 100',
        [userId]);
    return rows.map(_conversation).toList();
  }

  @override
  Future<List<ChatPerson>> friends() async {
    final rows = await database.db.rawQuery('''
      SELECT u.id, u.name FROM friendships f
      JOIN users u ON u.id = CASE
        WHEN f.user_low_id = ? THEN f.user_high_id ELSE f.user_low_id END
      WHERE f.status = 'accepted'
        AND (f.user_low_id = ? OR f.user_high_id = ?)
      ORDER BY u.name COLLATE NOCASE, u.id
    ''', [userId, userId, userId]);
    return rows
        .map((r) => ChatPerson(r['id'] as String, r['name'] as String))
        .toList();
  }

  @override
  Future<List<ChatPerson>> contacts(String search) async {
    if (search.length > 80) {
      throw const MessagingException('Search using at most 80 characters.');
    }
    final rows = await database.db.rawQuery(
        'SELECT u.id, u.name FROM users u WHERE u.id <> ? AND $_connected AND instr(lower(u.name), lower(?)) > 0 ORDER BY u.name COLLATE NOCASE, u.id LIMIT 50',
        [userId, userId, userId, userId, search.trim()]);
    return rows
        .map((r) => ChatPerson(r['id'] as String, r['name'] as String))
        .toList();
  }

  Future<void> _ensureMember(DatabaseExecutor db, String id) async {
    final rows = await db.query('conversation_members',
        columns: ['user_id'],
        where: 'conversation_id = ? AND user_id = ?',
        whereArgs: [id, userId]);
    if (rows.isEmpty) {
      throw const MessagingException(
          'This conversation is not available to your account.');
    }
  }

  @override
  Future<Conversation> create(
      {required String kind,
      required List<String> memberIds,
      String? title}) async {
    if (kind != 'direct' && kind != 'group') {
      throw const MessagingException('Choose a direct or group conversation.');
    }
    if (memberIds.contains(userId) ||
        memberIds.toSet().length != memberIds.length ||
        memberIds.any((id) => id.isEmpty) ||
        memberIds.length > 19 ||
        (kind == 'direct' && memberIds.length != 1) ||
        (kind == 'group' && memberIds.length < 2)) {
      throw const MessagingException(
          'Choose one person for a direct chat, or 2–19 people for a group.');
    }
    final name = title?.trim() ?? '';
    if (kind == 'group' && (name.length < 2 || name.length > 80)) {
      throw const MessagingException('Group names need 2–80 characters.');
    }
    return database.db.transaction((txn) async {
      final slots = List.filled(memberIds.length, '?').join(',');
      final eligible = await txn.rawQuery(
          'SELECT u.id FROM users u WHERE u.id IN ($slots) AND $_connected',
          [...memberIds, userId, userId, userId]);
      if (eligible.length != memberIds.length) {
        throw const MessagingException(
            'Start chats with friends or people you follow on this phone.');
      }
      var id = localId();
      if (kind == 'direct') {
        final pair = [userId, memberIds.single]..sort();
        final key = pair.join(':');
        await txn.rawInsert(
            "INSERT INTO conversations (id, kind, direct_key, created_by, created_at) VALUES (?, 'direct', ?, ?, ?) ON CONFLICT(direct_key) DO NOTHING",
            [id, key, userId, localTimestamp()]);
        id = (await txn.query('conversations',
                columns: ['id'], where: 'direct_key = ?', whereArgs: [key]))
            .single['id'] as String;
      } else {
        await txn.insert('conversations', {
          'id': id,
          'kind': kind,
          'title': name,
          'created_by': userId,
          'created_at': localTimestamp()
        });
      }
      for (final member in [userId, ...memberIds]) {
        await txn.rawInsert(
            'INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?) ON CONFLICT DO NOTHING',
            [id, member]);
      }
      return _conversation((await txn
              .rawQuery('$_conversationSelect WHERE c.id = ?', [userId, id]))
          .single);
    });
  }

  @override
  Future<List<ChatPerson>> members(String conversationId) async {
    await _ensureMember(database.db, conversationId);
    final rows = await database.db.rawQuery(
        'SELECT u.id, u.name FROM conversation_members m JOIN users u ON u.id = m.user_id WHERE m.conversation_id = ? ORDER BY u.name COLLATE NOCASE, u.id',
        [conversationId]);
    return rows
        .map((r) => ChatPerson(r['id'] as String, r['name'] as String))
        .toList();
  }

  @override
  Future<MessagePage> messages(String conversationId,
      {int? before, int? after}) async {
    await _ensureMember(database.db, conversationId);
    if ((before != null && after != null) ||
        (before != null && before < 1) ||
        (after != null && after < 0)) {
      throw const MessagingException('Refresh the conversation and try again.');
    }
    var query = '$_messageSelect WHERE msg.conversation_id = ?';
    final args = <Object?>[conversationId];
    if (before != null) {
      query += ' AND msg.sequence < ?';
      args.add(before);
    }
    if (after != null) {
      query += ' AND msg.sequence > ?';
      args.add(after);
    }
    query += after != null
        ? ' ORDER BY msg.sequence ASC LIMIT 51'
        : ' ORDER BY msg.sequence DESC LIMIT 51';
    final rows = await database.db.rawQuery(query, args);
    var messages = rows.take(50).map(_message).toList();
    if (after == null) messages = messages.reversed.toList();
    return MessagePage(messages,
        olderCursor:
            after == null && rows.length > 50 ? messages.first.sequence : null,
        hasMore: after != null && rows.length > 50);
  }

  @override
  Future<ChatMessage> send(
      String conversationId, String clientId, String body) async {
    if (clientId.isEmpty || clientId.length > 80) {
      throw const MessagingException('Please retry this message.');
    }
    final text = body.trim();
    if (text.isEmpty || text.length > 4000) {
      throw const MessagingException('Messages need 1–4,000 characters.');
    }
    return database.db.transaction((txn) async {
      await _ensureMember(txn, conversationId);
      await txn.rawInsert(
          '''INSERT INTO messages (conversation_id, sender_id, client_id, body, created_at) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(conversation_id, sender_id, client_id) DO NOTHING''',
          [conversationId, userId, clientId, text, localTimestamp()]);
      final row = (await txn.rawQuery(
              '$_messageSelect WHERE msg.conversation_id = ? AND msg.sender_id = ? AND msg.client_id = ?',
              [conversationId, userId, clientId]))
          .single;
      if (row['body'] != text) {
        throw const MessagingException(
            'This retry differs from the original message. Refresh the conversation.');
      }
      return _message(row);
    });
  }

  @override
  Future<void> markRead(String conversationId, int throughSequence) async {
    if (throughSequence < 0) {
      throw const MessagingException('Refresh the conversation and try again.');
    }
    await _ensureMember(database.db, conversationId);
    await database.db.rawUpdate(
        '''UPDATE conversation_members SET last_read_sequence = MAX(last_read_sequence,
      COALESCE((SELECT MAX(sequence) FROM messages WHERE conversation_id = ? AND sequence <= ?), 0))
      WHERE conversation_id = ? AND user_id = ?''',
        [conversationId, throughSequence, conversationId, userId]);
  }
}

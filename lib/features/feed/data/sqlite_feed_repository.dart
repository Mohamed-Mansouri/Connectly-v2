import 'package:sqflite/sqflite.dart';
import '../../../shared/data/local_database.dart';
import '../domain/feed_models.dart';

class SqliteFeedRepository implements FeedRepository {
  SqliteFeedRepository(this.database, this.userId);
  final LocalDatabase database;
  final String userId;
  static const _friends =
      '''EXISTS (SELECT 1 FROM friendships f WHERE f.status = 'accepted'
    AND ((f.user_low_id = ? AND f.user_high_id = p.author_id)
      OR (f.user_high_id = ? AND f.user_low_id = p.author_id)))''';
  static const _following =
      'EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followed_id = p.author_id)';
  (String, List<Object?>) _visibility(String scope) => switch (scope) {
        'connections' => (
            '(p.author_id = ? OR $_following OR $_friends)',
            [userId, userId, userId, userId]
          ),
        'friends' => (
            '(p.author_id = ? OR $_friends)',
            [userId, userId, userId]
          ),
        'following' => ('(p.author_id = ? OR $_following)', [userId, userId]),
        _ => throw const FeedException(
            'Choose Connections, Friends, or Following.'),
      };
  static const _select =
      '''SELECT p.id, p.author_id, u.name AS author_name, p.body, p.created_at,
    (SELECT kind FROM post_reactions r WHERE r.post_id = p.id AND r.user_id = ?) AS my_reaction,
    (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id AND r.kind = 'like') AS likes,
    (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id AND r.kind = 'love') AS loves,
    (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id AND r.kind = 'celebrate') AS celebrates,
    (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id AND r.kind = 'insightful') AS insights
    FROM posts p JOIN users u ON u.id = p.author_id''';
  FeedPost _post(Map<String, Object?> row) => FeedPost(
      id: row['id'] as String,
      authorId: row['author_id'] as String,
      authorName: row['author_name'] as String,
      body: row['body'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      reactions: {
        'like': row['likes'] as int,
        'love': row['loves'] as int,
        'celebrate': row['celebrates'] as int,
        'insightful': row['insights'] as int
      },
      myReaction: row['my_reaction'] as String?);

  @override
  Future<FeedPage> load({required String scope, String? cursor}) async {
    final (clause, visibilityArgs) = _visibility(scope);
    final args = <Object?>[userId, ...visibilityArgs];
    var boundary = '';
    if (cursor != null) {
      final parts = cursor.split('|');
      if (parts.length != 2 ||
          DateTime.tryParse(parts[0]) == null ||
          parts[1].isEmpty) {
        throw const FeedException('Refresh the feed and try again.');
      }
      boundary = ' AND (p.created_at < ? OR (p.created_at = ? AND p.id < ?))';
      args.addAll([parts[0], parts[0], parts[1]]);
    }
    final rows = await database.db.rawQuery(
        '$_select WHERE $clause$boundary ORDER BY p.created_at DESC, p.id DESC LIMIT 21',
        args);
    final posts = rows.take(20).map(_post).toList();
    return FeedPage(
        posts,
        rows.length > 20
            ? '${localTimestamp(posts.last.createdAt)}|${posts.last.id}'
            : null);
  }

  Future<FeedPost> _find(DatabaseExecutor db, String id) async {
    final (clause, args) = _visibility('connections');
    final rows = await db
        .rawQuery('$_select WHERE p.id = ? AND $clause', [userId, id, ...args]);
    if (rows.isEmpty) {
      throw const FeedException(
          'This post is no longer available in your feed.');
    }
    return _post(rows.first);
  }

  @override
  Future<FeedPost> create(String body) async {
    final text = body.trim();
    if (text.isEmpty || text.length > 3000) {
      throw const FeedException('Write a post between 1 and 3,000 characters.');
    }
    return database.db.transaction((txn) async {
      final id = localId();
      await txn.insert('posts', {
        'id': id,
        'author_id': userId,
        'body': text,
        'created_at': localTimestamp()
      });
      return _find(txn, id);
    });
  }

  @override
  Future<void> delete(String postId) async {
    // Foreign keys cascade the reactions; another account cannot delete this row.
    await database.db.delete('posts',
        where: 'id = ? AND author_id = ?', whereArgs: [postId, userId]);
  }

  @override
  Future<FeedPost> react(String postId, String? kind) async {
    if (kind != null &&
        !const ['like', 'love', 'celebrate', 'insightful'].contains(kind)) {
      throw const FeedException('Choose a supported reaction.');
    }
    return database.db.transaction((txn) async {
      await _find(txn, postId);
      if (kind == null) {
        await txn.delete('post_reactions',
            where: 'post_id = ? AND user_id = ?', whereArgs: [postId, userId]);
      } else {
        await txn.rawInsert(
            '''INSERT INTO post_reactions (post_id, user_id, kind) VALUES (?, ?, ?)
          ON CONFLICT(post_id, user_id) DO UPDATE SET kind = excluded.kind''',
            [postId, userId, kind]);
      }
      return _find(txn, postId);
    });
  }

  @override
  Future<List<FeedPerson>> people(
      {String search = '', bool requests = false}) async {
    if (search.length > 80) {
      throw const FeedException('Search using at most 80 characters.');
    }
    final rows = await database.db.rawQuery('''SELECT u.id, u.name,
      EXISTS(SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followed_id = u.id) AS following,
      CASE WHEN f.status = 'accepted' THEN 'friends' WHEN f.requested_by = ? THEN 'outgoing'
        WHEN f.status = 'pending' THEN 'incoming' ELSE 'none' END AS friendship
      FROM users u LEFT JOIN friendships f ON ((f.user_low_id = ? AND f.user_high_id = u.id)
        OR (f.user_high_id = ? AND f.user_low_id = u.id))
      WHERE u.id <> ? AND instr(lower(u.name), lower(?)) > 0
      ${requests ? "AND f.status = 'pending'" : ''}
      ORDER BY CASE WHEN f.status = 'pending' THEN 0 ELSE 1 END, u.name COLLATE NOCASE, u.id LIMIT 50''',
        [userId, userId, userId, userId, userId, search.trim()]);
    return rows
        .map((r) => FeedPerson(
            id: r['id'] as String,
            name: r['name'] as String,
            isFollowing: r['following'] == 1,
            friendship: r['friendship'] as String))
        .toList();
  }

  Future<void> _ensurePerson(String otherId) async {
    if (otherId == userId) throw const FeedException('Choose another person.');
    final rows = await database.db
        .query('users', columns: ['id'], where: 'id = ?', whereArgs: [otherId]);
    if (rows.isEmpty) {
      throw const FeedException('This person is not available on this phone.');
    }
  }

  @override
  Future<void> follow(String personId, bool following) async {
    await _ensurePerson(personId);
    if (following) {
      await database.db.rawInsert(
          'INSERT INTO follows (follower_id, followed_id, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING',
          [userId, personId, localTimestamp()]);
    } else {
      await database.db.delete('follows',
          where: 'follower_id = ? AND followed_id = ?',
          whereArgs: [userId, personId]);
    }
  }

  @override
  Future<void> friendship(String personId, String action) async {
    await _ensurePerson(personId);
    final ids = [userId, personId]..sort();
    switch (action) {
      case 'request':
        await database.db.rawInsert(
            '''INSERT INTO friendships (user_low_id, user_high_id, requested_by, status, created_at)
          VALUES (?, ?, ?, 'pending', ?) ON CONFLICT DO NOTHING''',
            [...ids, userId, localTimestamp()]);
      case 'accept':
        final changed = await database.db.rawUpdate(
            "UPDATE friendships SET status = 'accepted' WHERE user_low_id = ? AND user_high_id = ? AND requested_by = ? AND status = 'pending'",
            [...ids, personId]);
        if (changed == 0) {
          throw const FeedException(
              'This request has changed. Refresh People and try again.');
        }
      case 'remove':
        await database.db.delete('friendships',
            where: 'user_low_id = ? AND user_high_id = ?', whereArgs: ids);
      default:
        throw const FeedException('Choose a valid friendship action.');
    }
  }
}

import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import '../../../shared/data/local_database.dart';
import '../domain/feed_models.dart';
import '../domain/post_text.dart';
import 'post_index.dart';

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
    (SELECT COUNT(*) FROM post_reactions r WHERE r.post_id = p.id AND r.kind = 'insightful') AS insights,
    (SELECT COUNT(*) FROM post_comments c WHERE c.post_id = p.id) AS comments,
    i.width AS image_width, i.height AS image_height
    FROM posts p JOIN users u ON u.id = p.author_id
    LEFT JOIN post_images i ON i.post_id = p.id''';
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
      myReaction: row['my_reaction'] as String?,
      commentCount: row['comments'] as int,
      imageWidth: row['image_width'] as int?,
      imageHeight: row['image_height'] as int?);

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
  Future<FeedPost> create(String body, {FeedImageUpload? image}) async {
    final text = body.trim();
    if (text.isEmpty || text.length > 3000) {
      throw const FeedException('Write a post between 1 and 3,000 characters.');
    }
    if (image != null &&
        (image.bytes.isEmpty ||
            image.bytes.length > 2000000 ||
            image.width < 1 ||
            image.height < 1 ||
            image.width > 4096 ||
            image.height > 4096)) {
      throw const FeedException('Choose a photo smaller than 2 MB.');
    }
    return database.db.transaction((txn) async {
      final id = localId();
      await txn.insert('posts', {
        'id': id,
        'author_id': userId,
        'body': text,
        'created_at': localTimestamp()
      });
      if (image != null) {
        await txn.insert('post_images', {
          'post_id': id,
          'data': image.bytes,
          'width': image.width,
          'height': image.height
        });
        _remember(id, image.bytes);
      }
      await indexPostLinks(txn, id, text);
      return _find(txn, id);
    });
  }

  // Recently shown photos, so scrolling back does not re-read the database.
  final _images = <String, Uint8List>{}; // Keeps insertion order.
  void _remember(String postId, Uint8List bytes) {
    _images.remove(postId);
    _images[postId] = bytes;
    while (_images.length > 30) {
      _images.remove(_images.keys.first);
    }
  }

  @override
  Future<Uint8List> postImage(String postId) async {
    final cached = _images[postId];
    if (cached != null) return cached;
    await _find(database.db, postId); // Visibility check.
    final rows = await database.db.query('post_images',
        columns: ['data'], where: 'post_id = ?', whereArgs: [postId]);
    if (rows.isEmpty) throw const FeedException('This photo was removed.');
    final bytes = rows.single['data'] as Uint8List;
    _remember(postId, bytes);
    return bytes;
  }

  @override
  Future<void> delete(String postId) async {
    _images.remove(postId);
    // Foreign keys cascade reactions and comments; another account cannot delete this row.
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
  Future<List<FeedReactor>> reactors(String postId) async {
    await _find(database.db, postId);
    final rows = await database.db.rawQuery(
        '''SELECT r.user_id, u.name, r.kind FROM post_reactions r
      JOIN users u ON u.id = r.user_id WHERE r.post_id = ?
      ORDER BY CASE WHEN r.user_id = ? THEN 0 ELSE 1 END, u.name COLLATE NOCASE, u.id''',
        [postId, userId]);
    return rows
        .map((r) => FeedReactor(
            userId: r['user_id'] as String,
            name: r['name'] as String,
            kind: r['kind'] as String))
        .toList();
  }

  static const _commentSelect =
      '''SELECT c.id, c.post_id, c.author_id, u.name AS author_name, c.body, c.created_at
    FROM post_comments c JOIN users u ON u.id = c.author_id''';
  FeedComment _comment(Map<String, Object?> row) => FeedComment(
      id: row['id'] as String,
      postId: row['post_id'] as String,
      authorId: row['author_id'] as String,
      authorName: row['author_name'] as String,
      body: row['body'] as String,
      createdAt: DateTime.parse(row['created_at'] as String));

  @override
  Future<List<FeedComment>> comments(String postId) async {
    await _find(database.db, postId);
    final rows = await database.db.rawQuery(
        '$_commentSelect WHERE c.post_id = ? ORDER BY c.created_at, c.id LIMIT 500',
        [postId]);
    return rows.map(_comment).toList();
  }

  @override
  Future<FeedComment> addComment(String postId, String body) async {
    final text = body.trim();
    if (text.isEmpty || text.length > 1000) {
      throw const FeedException(
          'Write a comment between 1 and 1,000 characters.');
    }
    return database.db.transaction((txn) async {
      await _find(txn, postId);
      final id = localId();
      await txn.insert('post_comments', {
        'id': id,
        'post_id': postId,
        'author_id': userId,
        'body': text,
        'created_at': localTimestamp()
      });
      final rows = await txn.rawQuery('$_commentSelect WHERE c.id = ?', [id]);
      return _comment(rows.single);
    });
  }

  @override
  Future<void> deleteComment(String commentId) async {
    // Comment authors and the post's author may remove a comment.
    await database.db.rawDelete(
        '''DELETE FROM post_comments WHERE id = ? AND (author_id = ?
      OR post_id IN (SELECT id FROM posts WHERE author_id = ?))''',
        [commentId, userId, userId]);
  }

  Future<bool>? _fullText;
  Future<bool> _hasFullText() async {
    final rows = await database.db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'posts_fts'");
    return rows.isNotEmpty;
  }

  @override
  Future<List<FeedPost>> search(String input) async {
    if (input.length > 200) {
      throw const FeedException('Search using at most 200 characters.');
    }
    final query = PostQuery.parse(input);
    if (query.isEmpty) return const [];
    final (clause, visibilityArgs) = _visibility('connections');
    final where = <String>[clause];
    final args = <Object?>[userId, ...visibilityArgs];
    for (final tag in query.tags) {
      where.add('p.id IN (SELECT post_id FROM post_tags WHERE tag = ?)');
      args.add(tag);
    }
    for (final handle in query.mentions) {
      // Posts written by that person or mentioning them.
      where.add(
          '''(p.author_id IN (SELECT u.id FROM users u WHERE $handleSql = ?)
        OR p.id IN (SELECT m.post_id FROM post_mentions m JOIN users u ON u.id = m.user_id
          WHERE $handleSql = ?))''');
      args.addAll([handle, handle]);
    }
    if (query.words.isNotEmpty) {
      if (await (_fullText ??= _hasFullText())) {
        // Every word must match the start of a word: "trav" finds "travel".
        where.add(
            'p.id IN (SELECT post_id FROM posts_fts WHERE posts_fts MATCH ?)');
        args.add(query.words.map((w) => '$w*').join(' '));
      } else {
        for (final word in query.words) {
          where.add('instr(lower(p.body), ?) > 0');
          args.add(word);
        }
      }
    }
    final rows = await database.db.rawQuery(
        '$_select WHERE ${where.join(' AND ')} '
        'ORDER BY p.created_at DESC, p.id DESC LIMIT 100',
        args);
    // Rank by how well the words match; on a tie keep newest first.
    final ranked = [
      for (final (index, row) in rows.indexed) (post: _post(row), index: index)
    ]
        .map((e) =>
            (post: e.post, index: e.index, score: query.score(e.post.body)))
        .toList()
      ..sort((a, b) => a.score != b.score
          ? b.score.compareTo(a.score)
          : a.index.compareTo(b.index));
    return ranked.take(50).map((e) => e.post).toList();
  }

  @override
  Future<List<FeedTrend>> trendingTags() async {
    final (clause, args) = _visibility('connections');
    final since =
        localTimestamp(DateTime.now().subtract(const Duration(days: 30)));
    final rows = await database.db.rawQuery(
        '''SELECT t.tag, COUNT(*) AS uses FROM post_tags t
      JOIN posts p ON p.id = t.post_id
      WHERE p.created_at >= ? AND $clause
      GROUP BY t.tag ORDER BY uses DESC, MAX(p.created_at) DESC, t.tag LIMIT 10''',
        [since, ...args]);
    return rows
        .map((r) => FeedTrend(r['tag'] as String, r['uses'] as int))
        .toList();
  }

  @override
  Future<List<FeedSuggestion>> suggestions(String token) async {
    if (token.length > 41) return const [];
    if (token.startsWith('#')) {
      final prefix = token.substring(1).toLowerCase();
      final rows = await database.db
          .rawQuery('''SELECT tag, COUNT(*) AS uses FROM post_tags
        WHERE substr(tag, 1, length(?)) = ? GROUP BY tag
        ORDER BY uses DESC, tag LIMIT 6''', [prefix, prefix]);
      return rows.map((r) {
        final uses = r['uses'] as int;
        return FeedSuggestion(
            '#${r['tag']}', '$uses post${uses == 1 ? '' : 's'}');
      }).toList();
    }
    if (token.startsWith('@')) {
      final prefix = token.substring(1).toLowerCase();
      // Only accepted friends are suggested.
      final rows = await database.db.rawQuery(
          '''SELECT $handleSql AS handle, u.name FROM users u
        JOIN friendships f ON f.status = 'accepted'
          AND ((f.user_low_id = ? AND f.user_high_id = u.id)
            OR (f.user_high_id = ? AND f.user_low_id = u.id))
        WHERE substr($handleSql, 1, length(?)) = ?
          OR instr(lower(u.name), ?) > 0
        ORDER BY u.name COLLATE NOCASE LIMIT 6''',
          [userId, userId, prefix, prefix, prefix]);
      return rows
          .where((r) => (r['handle'] as String).isNotEmpty)
          .map((r) => FeedSuggestion('@${r['handle']}', r['name'] as String))
          .toList();
    }
    return const [];
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

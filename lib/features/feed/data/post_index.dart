import 'package:sqflite/sqflite.dart';
import '../../../shared/data/local_schema.dart';
import '../domain/post_text.dart';

/// SQL expression giving a user's mention handle (email before the `@`).
const handleSql = "lower(substr(u.email, 1, instr(u.email, '@') - 1))";

/// Saves the hashtags and resolved @mentions of one post.
Future<void> indexPostLinks(
    DatabaseExecutor db, String postId, String body) async {
  await db.delete('post_tags', where: 'post_id = ?', whereArgs: [postId]);
  await db.delete('post_mentions', where: 'post_id = ?', whereArgs: [postId]);
  for (final tag in extractTags(body)) {
    await db.insert('post_tags', {'post_id': postId, 'tag': tag},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }
  for (final handle in extractMentions(body)) {
    await db.rawInsert(
        'INSERT OR IGNORE INTO post_mentions (post_id, user_id) '
        'SELECT ?, u.id FROM users u WHERE $handleSql = ?',
        [postId, handle]);
  }
}

/// Creates the version 7 tables and indexes every existing post.
Future<void> createPostIndexes(DatabaseExecutor db) async {
  for (final sql in postLinkSchema) {
    await db.execute(sql);
  }
  if (await _createFullText(db)) {
    await db.execute(
        'INSERT INTO posts_fts(post_id, body) SELECT id, body FROM posts');
  }
  final posts = await db.query('posts', columns: ['id', 'body']);
  for (final post in posts) {
    await indexPostLinks(db, post['id'] as String, post['body'] as String);
  }
}

/// Version 9: rebuilds `posts` with `shared_post_id` and a relaxed body
/// CHECK, keeping every row. Must run with foreign keys off. Dropping the old
/// table also drops its full-text triggers, so they are created again.
Future<void> rebuildPostsForSharing(DatabaseExecutor db) async {
  for (final sql in postsV9Schema) {
    await db.execute(sql);
  }
  final fullText = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'posts_fts'");
  if (fullText.isNotEmpty) {
    for (final trigger in postSearchTriggers) {
      await db.execute(trigger);
    }
  }
  final broken = await db.rawQuery('PRAGMA foreign_key_check');
  if (broken.isNotEmpty) {
    throw StateError('Post upgrade left ${broken.length} broken references.');
  }
}

/// Creates the first full-text engine this SQLite supports (see
/// [postSearchTable]); returns false when none is available.
Future<bool> _createFullText(DatabaseExecutor db) async {
  for (final sql in postSearchTable) {
    try {
      await db.execute(sql);
    } on DatabaseException {
      continue; // Module missing: try the next one.
    }
    for (final trigger in postSearchTriggers) {
      await db.execute(trigger);
    }
    return true;
  }
  return false;
}

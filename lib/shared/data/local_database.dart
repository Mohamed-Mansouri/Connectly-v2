import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import '../../features/feed/data/post_index.dart';
import 'local_schema.dart';

class LocalDatabase {
  LocalDatabase(this.db);
  final Database db;

  static Future<LocalDatabase> open(
      {DatabaseFactory? factory, String? databasePath}) async {
    final engine = factory ?? databaseFactory;
    final filename = databasePath ??
        path.join(await engine.getDatabasesPath(), 'connectly_local.db');
    final db = await engine.openDatabase(filename,
        options: OpenDatabaseOptions(
          version: 9,
          // Foreign keys stay off while tables are created or rebuilt
          // (dropping the old `posts` must not cascade) and are switched on
          // in onOpen, after the upgrade transaction has committed.
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = OFF'),
          onOpen: (db) async => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            final batch = db.batch();
            for (final sql in localSchema) {
              batch.execute(sql);
            }
            batch.execute(peopleLocationSchema);
            batch.execute(userProfileSchema);
            batch.execute(messageAudioSchema);
            for (final sql in postCommentSchema) {
              batch.execute(sql);
            }
            batch.execute(passwordResetSchema);
            await batch.commit(noResult: true);
            await createPostIndexes(db);
            await db.execute(postImageSchema);
            await rebuildPostsForSharing(db);
            await db.execute(messagePostSchema);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) await db.execute(peopleLocationSchema);
            if (oldVersion < 3) await db.execute(userProfileSchema);
            if (oldVersion < 4) await db.execute(messageAudioSchema);
            if (oldVersion < 5) {
              for (final sql in postCommentSchema) {
                await db.execute(sql);
              }
            }
            if (oldVersion < 6) await db.execute(passwordResetSchema);
            if (oldVersion < 7) await createPostIndexes(db);
            if (oldVersion < 8) await db.execute(postImageSchema);
            if (oldVersion < 9) {
              await rebuildPostsForSharing(db);
              await db.execute(messagePostSchema);
            }
          },
        ));
    return LocalDatabase(db);
  }

  Future<void> close() => db.close();
}

String localTimestamp([DateTime? time]) => DateTime.fromMillisecondsSinceEpoch(
        (time ?? DateTime.now()).millisecondsSinceEpoch,
        isUtc: true)
    .toIso8601String();
String localId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

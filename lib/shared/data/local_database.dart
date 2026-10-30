import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
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
          version: 2,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            final batch = db.batch();
            for (final sql in localSchema) {
              batch.execute(sql);
            }
            batch.execute(peopleLocationSchema);
            await batch.commit(noResult: true);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) await db.execute(peopleLocationSchema);
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

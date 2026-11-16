import 'dart:io';
import 'dart:typed_data';
import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/shared/presentation/photo_crop_screen.dart';
import 'package:connectly/features/feed/data/sqlite_feed_repository.dart';
import 'package:connectly/features/feed/domain/post_text.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:connectly/shared/data/local_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('post text rules', () {
    test('extracts tags and mentions but not emails', () {
      const body = 'Lunch with @Amal and @sami. at #Ariana #ariana #food_2026 '
          'mail me at x@g.m #';
      expect(extractTags(body), ['ariana', 'food_2026']);
      expect(extractMentions(body), ['amal', 'sami']);
      expect(extractTags('price#5 a#b'), isEmpty);
    });

    test('splits a body into plain text, tags and mentions', () {
      final parts = splitPostText('Hi @amal. See #trip!');
      expect(parts.map((p) => p.text).join(), 'Hi @amal. See #trip!');
      expect(parts.where((p) => p.mention != null).single.text, '@amal');
      expect(parts.where((p) => p.tag != null).single.tag, 'trip');
    });

    test('parses a query and scores word matches', () {
      final query = PostQuery.parse('  #Trip @AMAL Beach sun ');
      expect(query.tags, ['trip']);
      expect(query.mentions, ['amal']);
      expect(query.words, ['beach', 'sun']);
      expect(PostQuery.parse('   ').isEmpty, isTrue);
      // Exact word = 3, prefix = 1.
      expect(query.score('Beach day, sunny beach'), 3 + 1 + 3);
      expect(query.score('Nothing here'), 0);
    });
  });

  group('SQLite search', () {
    late LocalDatabase database;
    late SqliteAuthRepository auth;
    setUp(() async {
      database = await LocalDatabase.open(
          factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
      auth = SqliteAuthRepository(database,
          passwords: LocalPasswords(iterations: 1000));
    });
    tearDown(() => database.close());

    test('finds visible posts by tag, mention and word, ranked', () async {
      final amal = (await auth.signUp('Amal', 'amal@g.m', 'password1')).user;
      final sami = (await auth.signUp('Sami', 'sami@g.m', 'password1')).user;
      final eve = (await auth.signUp('Eve', 'eve@g.m', 'password1')).user;
      final asAmal = SqliteFeedRepository(database, amal.id);
      final asSami = SqliteFeedRepository(database, sami.id);
      final asEve = SqliteFeedRepository(database, eve.id);
      await asAmal.friendship(sami.id, 'request');
      await asSami.friendship(amal.id, 'accept');

      final trip = await asSami.create('Beach trip with @amal #Summer #trip');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final beach =
          await asAmal.create('Beach beach beach! Best beach day #summer');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Eve is not connected to Amal, so this stays hidden from her.
      await asEve.create('Secret beach #summer');

      expect(
          (await database.db.query('post_tags',
                  where: 'post_id = ?', whereArgs: [trip.id]))
              .map((r) => r['tag']),
          unorderedEquals(['summer', 'trip']));
      expect((await database.db.query('post_mentions')).single['user_id'],
          amal.id);

      // Tags are case-insensitive and respect visibility.
      expect((await asAmal.search('#SUMMER')).map((p) => p.id),
          unorderedEquals([trip.id, beach.id]));
      expect((await asAmal.search('#summer #trip')).single.id, trip.id);
      // @amal finds Amal's own posts and posts mentioning her.
      expect((await asSami.search('@amal')).map((p) => p.id),
          unorderedEquals([trip.id, beach.id]));
      // Word prefix through the full-text index, best match first.
      final words = await asAmal.search('bea');
      expect(words.map((p) => p.id), [beach.id, trip.id]);
      expect(await asAmal.search('nothing-like-this'), isEmpty);
      expect(await asAmal.search('   '), isEmpty);
      // Hostile input is treated as text, not FTS syntax or SQL.
      expect(await asAmal.search('" OR 1=1 -- NEAR('), isEmpty);

      final trends = await asAmal.trendingTags();
      expect(trends.first.tag, 'summer');
      expect(trends.first.count, 2);
      expect((await asAmal.suggestions('#su')).single.value, '#summer');
      expect((await asSami.suggestions('@am')).single.value, '@amal');
      expect((await asSami.suggestions('@am')).single.label, 'Amal');
      // Only friends are suggested: Eve is not Amal's friend.
      expect(await asAmal.suggestions('@ev'), isEmpty);
      expect(await asEve.suggestions('@am'), isEmpty);
      expect((await asAmal.suggestions('@')).map((s) => s.value), ['@sami']);

      // Deleting a post removes it from every index.
      await asAmal.delete(beach.id);
      expect((await asAmal.search('beach')).single.id, trip.id);
      expect(
          await database.db
              .query('post_tags', where: 'post_id = ?', whereArgs: [beach.id]),
          isEmpty);
      expect(
          (await database.db.rawQuery(
                  "SELECT COUNT(*) AS n FROM posts_fts WHERE posts_fts MATCH 'best'"))
              .single['n'],
          0);
    });

    test('upgrading an old database indexes existing posts', () async {
      final dir = await Directory.systemTemp.createTemp('connectly_v7_');
      final filename = '${dir.path}/v6.db';
      try {
        final old = await databaseFactoryFfi.openDatabase(filename,
            options: OpenDatabaseOptions(
                version: 1,
                onCreate: (db, _) async {
                  for (final sql in localSchema) {
                    await db.execute(sql);
                  }
                  await db.insert('users', {
                    'id': 'u1',
                    'email': 'amal@g.m',
                    'name': 'Amal',
                    'password_hash': 'x',
                    'created_at': localTimestamp()
                  });
                  await db.insert('posts', {
                    'id': 'p1',
                    'author_id': 'u1',
                    'body': 'Old post about #Tunis with @amal',
                    'created_at': localTimestamp()
                  });
                }));
        await old.close();
        final upgraded = await LocalDatabase.open(
            factory: databaseFactoryFfi, databasePath: filename);
        try {
          expect(await upgraded.db.getVersion(), 9);
          final repo = SqliteFeedRepository(upgraded, 'u1');
          expect((await repo.search('#tunis')).single.id, 'p1');
          expect((await repo.search('old')).single.id, 'p1');
          expect((await repo.search('@amal')).single.id, 'p1');
        } finally {
          await upgraded.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  test('profile photos are resized to a 512 px square JPEG', () {
    final source = img.Image(width: 1200, height: 900);
    img.fill(source, color: img.ColorRgb8(200, 30, 30));
    final out = resizeProfilePhoto(Uint8List.fromList(img.encodePng(source)));
    final decoded = img.decodeJpg(out)!;
    expect(decoded.width, profilePhotoSize);
    expect(decoded.height, profilePhotoSize);
    final rotated =
        img.decodeJpg(rotatePhoto(Uint8List.fromList(img.encodePng(source))))!;
    expect((rotated.width, rotated.height), (900, 1200));
    // Small crops are not enlarged.
    final small = img.decodeJpg(resizeProfilePhoto(Uint8List.fromList(
        img.encodePng(img.Image(width: 200, height: 200)))))!;
    expect(small.width, 200);
  });
}

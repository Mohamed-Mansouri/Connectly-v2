import 'dart:io';
import 'package:connectly/features/discovery/data/people_repository.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:connectly/shared/data/local_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late LocalDatabase database;
  late SqlitePeopleRepository alice;
  late SqlitePeopleRepository bob;
  Future<void> user(String id) => database.db.insert('users', {
        'id': id,
        'name': id,
        'email': '$id@example.test',
        'password_hash': 'test',
        'created_at': localTimestamp(),
      }).then((_) {});
  setUp(() async {
    database = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    for (final name in ['Alice', 'Bob', 'Charlie', 'Distant']) {
      await user(name);
    }
    alice = SqlitePeopleRepository(database, 'Alice');
    bob = SqlitePeopleRepository(database, 'Bob');
  });
  tearDown(() => database.close());

  test('search and connection filters work without shared pins', () async {
    expect((await alice.load()).ownLocation, isNull);
    expect((await alice.load()).people, hasLength(3));
    expect(
        (await alice.load(search: '  bOB  ')).people.single.person.id, 'Bob');
    expect((await alice.load(search: "' OR 1=1 --")).people, isEmpty);
    await alice.connections.friendship('Bob', 'request');
    expect(
        (await alice.load(filter: 'requests')).people.single.person.friendship,
        'outgoing');
    expect((await bob.load(filter: 'requests')).people.single.person.friendship,
        'incoming');
    await bob.connections.friendship('Alice', 'accept');
    expect((await alice.load(filter: 'requests')).people, isEmpty);
    expect(
        (await alice.load(filter: 'friends')).people.single.person.id, 'Bob');
    expect((await alice.load(filter: 'following')).people, isEmpty);
    await alice.connections.follow('Charlie', true);
    expect((await alice.load(filter: 'following')).people.single.person.id,
        'Charlie');
  });

  test(
      'proximity is measured from own pin, with hidden and missing pins excluded',
      () async {
    const center = PeopleLocation(36.8065, 10.1815);
    const near = PeopleLocation(36.81, 10.1815);
    await alice.saveLocation(center);
    await bob.saveLocation(near);
    await SqlitePeopleRepository(database, 'Distant')
        .saveLocation(const PeopleLocation(36.90, 10.28));
    final result = await alice.load(radiusKm: 1);
    expect(result.people.single.person.id, 'Bob');
    expect(result.people.single.distanceKm, closeTo(.389, .002));
    expect((await alice.load(radiusKm: 25)).people, hasLength(2));
    expect((await alice.load(radiusKm: center.distanceKm(near))).people,
        hasLength(1));
    expect(
        (await alice.load(radiusKm: center.distanceKm(near) - .00001)).people,
        isEmpty);
    await bob
        .saveLocation(const PeopleLocation(36.81, 10.1815, visible: false));
    expect((await bob.load()).ownLocation!.visible, isFalse);
    expect((await alice.load(radiusKm: 1)).people, isEmpty);
    expect((await alice.load(search: 'Bob')).people.single.location, isNull);
    await alice.removeLocation();
    expect((await alice.load()).ownLocation, isNull);
    expect((await alice.load(radiusKm: 25)).people, isEmpty);
    expect((await bob.load()).ownLocation, isNotNull);
  });

  test(
      'validates coordinates and distance, and pins cascade on account deletion',
      () async {
    await expectLater(alice.saveLocation(PeopleLocation(double.nan, 10)),
        throwsA(isA<FeedException>()));
    await expectLater(alice.saveLocation(const PeopleLocation(91, 10)),
        throwsA(isA<FeedException>()));
    await expectLater(alice.load(radiusKm: -1), throwsA(isA<FeedException>()));
    await alice.saveLocation(const PeopleLocation(36.8, 10.18));
    await database.db.delete('users', where: 'id = ?', whereArgs: ['Alice']);
    expect(await database.db.query('user_locations'), isEmpty);
    expect(
        const PeopleLocation(0, 179.9)
            .distanceKm(const PeopleLocation(0, -179.9)),
        closeTo(22.239, .01));
  });

  test('version 1 upgrade preserves accounts, sessions, posts and messages',
      () async {
    final dir = await Directory.systemTemp.createTemp('connectly_upgrade_');
    final filename = '${dir.path}/upgrade.db';
    final old = await databaseFactoryFfi.openDatabase(filename,
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              for (final sql in localSchema) {
                await db.execute(sql);
              }
            }));
    try {
      await old.insert('users', {
        'id': 'old',
        'name': 'Existing member',
        'email': 'old@test.example',
        'password_hash': 'hash',
        'created_at': localTimestamp()
      });
      await old.insert('auth_sessions', {
        'token_hash': 'session',
        'user_id': 'old',
        'expires_at': '2099-01-01',
        'created_at': localTimestamp()
      });
      await old.insert('posts', {
        'id': 'post',
        'author_id': 'old',
        'body': 'Keep my post',
        'created_at': localTimestamp()
      });
      await old.insert('conversations', {
        'id': 'chat',
        'kind': 'group',
        'title': 'Keep chat',
        'created_by': 'old',
        'created_at': localTimestamp()
      });
      await old.insert('conversation_members',
          {'conversation_id': 'chat', 'user_id': 'old'});
      await old.insert('messages', {
        'conversation_id': 'chat',
        'sender_id': 'old',
        'client_id': 'client',
        'body': 'Keep message',
        'created_at': localTimestamp()
      });
    } finally {
      await old.close();
    }
    final upgraded = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: filename);
    try {
      expect(await upgraded.db.getVersion(), 2);
      expect(
          (await upgraded.db.query('users')).single['name'], 'Existing member');
      expect((await upgraded.db.query('auth_sessions')).single['token_hash'],
          'session');
      expect((await upgraded.db.query('posts')).single['body'], 'Keep my post');
      expect(
          (await upgraded.db.query('messages')).single['body'], 'Keep message');
      expect(await upgraded.db.query('user_locations'), isEmpty);
      await SqlitePeopleRepository(upgraded, 'old')
          .saveLocation(const PeopleLocation(36.8, 10.18));
      expect(await upgraded.db.query('user_locations'), hasLength(1));
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });
}

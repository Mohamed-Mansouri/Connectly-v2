import 'dart:io';
import 'dart:typed_data';
import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/profile_repository.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/features/auth/domain/auth_models.dart';
import 'package:connectly/features/discovery/data/people_repository.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:connectly/shared/data/local_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('profile details, photo, and location persist without changing others',
      () async {
    final database = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    try {
      final auth = SqliteAuthRepository(database,
          passwords: LocalPasswords(iterations: 1000));
      final alice =
          await auth.signUp('Alice', 'alice@example.test', 'password123');
      final bob = await auth.signUp('Bob', 'bob@example.test', 'password123');
      final profile = SqliteProfileRepository(database, alice.user.id);
      expect((await profile.load()).bio, isEmpty);
      expect((await profile.load()).photo, isNull);
      expect((await profile.load()).location, isNull);

      await profile.saveDetails(
          name: ' Alice Updated ',
          email: ' ALICE.NEW@example.test ',
          bio: ' Looking for friends ');
      final photo = Uint8List.fromList([1, 2, 3, 4]);
      await profile.savePhoto(photo);
      await profile
          .saveLocation(const PeopleLocation(36.8533, 10.2072, visible: false));
      final saved = await profile.load();
      expect(saved.name, 'Alice Updated');
      expect(saved.email, 'alice.new@example.test');
      expect(saved.bio, 'Looking for friends');
      expect(saved.photo, photo);
      expect(saved.location!.visible, isFalse);
      expect((await auth.currentUser(alice.token)).name, 'Alice Updated');
      expect((await SqliteProfileRepository(database, bob.user.id).load()).name,
          'Bob');

      await expectLater(
          profile.saveDetails(
              name: 'Changed', email: 'bob@example.test', bio: 'Lost'),
          throwsA(isA<AuthException>()));
      expect((await profile.load()).name, 'Alice Updated');
      expect((await profile.load()).bio, 'Looking for friends');
      await expectLater(
          profile.savePhoto(Uint8List(2000001)), throwsA(isA<AuthException>()));

      await profile.savePhoto(null);
      await profile.removeLocation();
      expect((await profile.load()).photo, isNull);
      expect((await profile.load()).location, isNull);
      expect((await profile.load()).bio, 'Looking for friends');
    } finally {
      await database.close();
    }
  });

  test('version 2 database gains profiles without replacing accounts or pins',
      () async {
    final dir = await Directory.systemTemp.createTemp('connectly_profile_');
    final filename = '${dir.path}/upgrade.db';
    final old = await databaseFactoryFfi.openDatabase(filename,
        options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, _) async {
              for (final sql in localSchema) {
                await db.execute(sql);
              }
              await db.execute(peopleLocationSchema);
            }));
    try {
      await old.insert('users', {
        'id': 'existing',
        'name': 'Existing member',
        'email': 'existing@example.test',
        'password_hash': 'hash',
        'created_at': localTimestamp(),
      });
      await old.insert('user_locations', {
        'user_id': 'existing',
        'latitude': 36.8625,
        'longitude': 10.19556,
        'visible': 1,
        'updated_at': localTimestamp(),
      });
    } finally {
      await old.close();
    }
    final upgraded = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: filename);
    try {
      expect(await upgraded.db.getVersion(), 4);
      final profile = SqliteProfileRepository(upgraded, 'existing');
      expect((await profile.load()).name, 'Existing member');
      expect((await profile.load()).location!.latitude, 36.8625);
      await profile.saveDetails(
          name: 'Updated member',
          email: 'updated@example.test',
          bio: 'Still here');
      expect((await profile.load()).bio, 'Still here');
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });
}

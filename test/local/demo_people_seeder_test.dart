import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/features/auth/domain/auth_models.dart';
import 'package:connectly/features/discovery/data/demo_people_seeder.dart';
import 'package:connectly/features/discovery/data/people_repository.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('demo seeding preserves data and supports nearby friend requests',
      () async {
    final database = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    try {
      final passwords = LocalPasswords(iterations: 1000);
      final auth = SqliteAuthRepository(database, passwords: passwords);
      final presenter = await auth.signUp(
          'Presenter', 'presenter@example.test', 'presenter-password');
      final people = SqlitePeopleRepository(database, presenter.user.id);
      await people.saveLocation(const PeopleLocation(36.8625, 10.19556));

      await seedDemoPeople(database, passwords: passwords);
      expect(await database.db.query('users'), hasLength(7));
      final ariana = await people.load(radiusKm: 1);
      expect(ariana.people.map((p) => p.person.id).toSet(),
          {'demo-amal', 'demo-sami', 'demo-ines'});
      expect(
          ariana.people.map((p) => p.distanceKm!).toList(),
          orderedEquals(
              ariana.people.map((p) => p.distanceKm!).toList()..sort()));

      await people.saveLocation(const PeopleLocation(36.8533, 10.2072));
      final campus = await people.load(radiusKm: 1);
      expect(campus.people.map((p) => p.person.id).toSet(),
          {'demo-nour', 'demo-youssef', 'demo-meriem'});

      final nour = SqlitePeopleRepository(database, 'demo-nour');
      await nour
          .saveLocation(const PeopleLocation(36.8570, 10.2060, visible: false));
      await people.connections.friendship('demo-nour', 'request');
      final hashBefore = (await database.db.query('users',
              columns: ['password_hash'],
              where: 'id = ?',
              whereArgs: ['demo-nour']))
          .single['password_hash'];
      await seedDemoPeople(database, passwords: passwords);
      expect(await database.db.query('users'), hasLength(7));
      expect(
          (await database.db.query('users',
                  columns: ['password_hash'],
                  where: 'id = ?',
                  whereArgs: ['demo-nour']))
              .single['password_hash'],
          hashBefore);
      expect((await nour.load()).ownLocation!.visible, isFalse);
      expect((await people.load(radiusKm: 1)).people.map((p) => p.person.id),
          isNot(contains('demo-nour')));
      expect((await people.load(search: 'Demo Nour')).people.single.location,
          isNull);
      expect((await people.load()).ownLocation!.latitude, 36.8533);

      final demoSession =
          await auth.signIn('demo.nour@connectly.invalid', demoPeoplePassword);
      expect(demoSession.user.id, 'demo-nour');
      expect((await nour.load(filter: 'requests')).people.single.person.id,
          presenter.user.id);
      await nour.connections.friendship(presenter.user.id, 'accept');
      expect((await people.load(filter: 'friends')).people.single.person.id,
          'demo-nour');
    } finally {
      await database.close();
    }
  });

  test('old demo passwords rotate once without changing pins or requests',
      () async {
    final database = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    try {
      final passwords = LocalPasswords(iterations: 1000);
      final auth = SqliteAuthRepository(database, passwords: passwords);
      final presenter = await auth.signUp(
          'Presenter', 'presenter@example.test', 'presenter-password');
      await database.db.insert('users', {
        'id': 'demo-amal',
        'name': 'Demo Amal · Ariana',
        'email': 'demo.amal@connectly.invalid',
        'password_hash': await passwords.hash('ConnectlyDemo!2026'),
        'created_at': localTimestamp(),
      });
      await database.db.insert('user_locations', {
        'user_id': 'demo-amal',
        'latitude': 36.8680,
        'longitude': 10.1945,
        'visible': 0,
        'updated_at': localTimestamp(),
      });
      final people = SqlitePeopleRepository(database, presenter.user.id);
      await people.connections.friendship('demo-amal', 'request');

      await seedDemoPeople(database, passwords: passwords);
      expect(await database.db.query('users'), hasLength(7));
      expect(
          (await SqlitePeopleRepository(database, 'demo-amal').load())
              .ownLocation!
              .visible,
          isFalse);
      expect((await people.load(filter: 'requests')).people.single.person.id,
          'demo-amal');
      await expectLater(
          auth.signIn('demo.amal@connectly.invalid', 'ConnectlyDemo!2026'),
          throwsA(isA<AuthException>()));
      expect(
          (await auth.signIn('demo.amal@connectly.invalid', demoPeoplePassword))
              .user
              .id,
          'demo-amal');

      final updatedHash = (await database.db.query('users',
              columns: ['password_hash'],
              where: 'id = ?',
              whereArgs: ['demo-amal']))
          .single['password_hash'];
      await seedDemoPeople(database, passwords: passwords);
      expect(
          (await database.db.query('users',
                  columns: ['password_hash'],
                  where: 'id = ?',
                  whereArgs: ['demo-amal']))
              .single['password_hash'],
          updatedHash);
    } finally {
      await database.close();
    }
  });
}

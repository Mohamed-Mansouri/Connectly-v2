import 'dart:convert';
import 'package:connectly/app/connectly_theme.dart';
import 'package:connectly/app/local_data_scope.dart';
import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/profile_repository.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/features/auth/presentation/auth_scope.dart';
import 'package:connectly/features/auth/presentation/profile_screen.dart';
import 'package:connectly/features/discovery/data/people_repository.dart';
import 'package:connectly/features/discovery/presentation/ariana_map.dart';
import 'package:connectly/features/discovery/presentation/location_sheet.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'auth_controller_test.dart' show MemorySessionStore;

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(finder, findsWidgets);
}

void main() {
  sqfliteFfiInit();

  testWidgets('Profile edits details, chooses a photo, and saves location',
      (tester) async {
    late LocalDatabase database;
    late AuthController auth;
    await tester.runAsync(() async {
      database = await LocalDatabase.open(
          factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
      auth = AuthController(
          repository: SqliteAuthRepository(database,
              passwords: LocalPasswords(iterations: 1000)),
          store: MemorySessionStore());
      await auth.restore();
      await auth.signUp('Alice', 'alice@example.test', 'password123');
    });
    final userId = auth.user!.id;
    final photo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO8B9x8AAAAASUVORK5CYII=');
    try {
      await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        builder: (context, child) => LocalDataScope(
            database: database,
            child: AuthScope(controller: auth, child: child!)),
        home: ProfileScreen(pickPhoto: () async => photo),
      ));
      await waitFor(tester, find.text('Edit profile'));
      await tester.tap(find.text('Edit profile'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Updated Alice');
      await tester.enterText(
          find.byType(TextField).at(1), 'updated@example.test');
      await tester.enterText(find.byType(TextField).at(2), 'A short bio');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Save profile'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Save profile'));
      await waitFor(tester, find.text('Edit profile'));
      expect(find.text('Updated Alice'), findsOneWidget);
      expect(auth.user!.name, 'Updated Alice');
      expect(auth.user!.email, 'updated@example.test');
      await tester.runAsync(() async {
        expect((await SqliteProfileRepository(database, userId).load()).bio,
            'A short bio');
      });

      await tester.ensureVisible(find.text('Choose photo'));
      await tester.tap(find.text('Choose photo'));
      await waitFor(tester, find.text('Remove photo'));
      await tester.runAsync(() async {
        expect((await SqliteProfileRepository(database, userId).load()).photo,
            photo);
      });

      await tester.scrollUntilVisible(find.text('Set location'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Set location'));
      await waitFor(tester, find.byType(ArianaMap));
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<ArianaMap>(find.byType(ArianaMap))
          .onPlacePin!(const PeopleLocation(36.8533, 10.2072));
      await tester.pump();
      final sheetScroll = tester.state<ScrollableState>(find
          .descendant(
              of: find.byType(LocationSheet), matching: find.byType(Scrollable))
          .first);
      sheetScroll.position.jumpTo(sheetScroll.position.maxScrollExtent);
      await tester.pump();
      await tester.tap(find.text('Save pin'));
      await waitFor(tester, find.text('Edit location'));
      await tester.runAsync(() async {
        expect(
            (await SqliteProfileRepository(database, userId).load())
                .location!
                .latitude,
            36.8533);
      });
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      await tester.runAsync(database.close);
    }
  });
}

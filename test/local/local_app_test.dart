import 'dart:io';
import 'package:connectly/app/connectly_app.dart';
import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/features/feed/data/sqlite_feed_repository.dart';
import 'package:connectly/features/messaging/data/sqlite_messaging_repository.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../features/auth/auth_controller_test.dart' show MemorySessionStore;
import '../features/auth/login_screen_test.dart' show MemoryLoginPreferences;

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('The local app must not create an HTTP client.');
}

Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

void main() {
  sqfliteFfiInit();
  testWidgets('default Feed and Chats use SQLite with all HTTP clients blocked',
      (tester) async {
    await HttpOverrides.runWithHttpOverrides(() async {
      LocalDatabase? database;
      AuthController? auth;
      try {
        await tester.runAsync(() async {
          database = await LocalDatabase.open(
              factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
          final repository = SqliteAuthRepository(database!,
              passwords: LocalPasswords(iterations: 1000));
          auth = AuthController(
              repository: repository, store: MemorySessionStore());
          await auth!.restore();
          await auth!
              .signUp('Local Member', 'member@example.test', 'password123');
          final other = await repository.signUp(
              'Other Member', 'other@example.test', 'password123');
          final feed = SqliteFeedRepository(database!, auth!.user!.id);
          await feed.create('SQLite post without HTTP');
          await feed.follow(other.user.id, true);
          final chat =
              await SqliteMessagingRepository(database!, auth!.user!.id)
                  .create(kind: 'direct', memberIds: [other.user.id]);
          await SqliteMessagingRepository(database!, other.user.id)
              .send(chat.id, localId(), 'SQLite message without HTTP');
        });
        await tester.pumpWidget(ConnectlyApp(
            database: database,
            authController: auth,
            loginPreferences: MemoryLoginPreferences()));
        await pumpUntil(tester, find.text('SQLite post without HTTP'));
        expect(find.text('SQLite post without HTTP'), findsOneWidget);
        await tester.tap(find.text('People'));
        await pumpUntil(tester, find.text('Other Member'));
        expect(find.text('Other Member'), findsOneWidget);
        expect(find.text('Nearby'), findsNothing);
        await tester.tap(find.text('Chats'));
        await pumpUntil(tester, find.text('Other Member'));
        expect(find.text('SQLite message without HTTP'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        auth?.dispose();
        await tester.runAsync(() async => database?.close());
      }
    }, _NoNetwork());
  });
}

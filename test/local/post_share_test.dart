import 'dart:io';
import 'dart:typed_data';
import 'package:connectly/app/connectly_theme.dart';
import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/features/auth/domain/auth_models.dart';
import 'package:connectly/features/auth/presentation/auth_scope.dart';
import 'package:connectly/features/feed/data/sqlite_feed_repository.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';
import 'package:connectly/features/feed/presentation/feed_screen.dart';
import 'package:connectly/features/messaging/data/sqlite_messaging_repository.dart';
import 'package:connectly/features/messaging/domain/messaging_models.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:connectly/shared/data/local_schema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../features/auth/auth_controller_test.dart' show MemorySessionStore;

FeedImageUpload photo() => FeedImageUpload(
    bytes: Uint8List.fromList(List.filled(64, 7)), width: 40, height: 30);

void main() {
  sqfliteFfiInit();
  late LocalDatabase database;
  late SqliteAuthRepository auth;
  late AuthUser amal, sami, eve;
  late SqliteFeedRepository asAmal, asSami, asEve;

  setUp(() async {
    database = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    auth = SqliteAuthRepository(database,
        passwords: LocalPasswords(iterations: 1000));
    amal = (await auth.signUp('Amal', 'amal@g.m', 'password1')).user;
    sami = (await auth.signUp('Sami', 'sami@g.m', 'password1')).user;
    eve = (await auth.signUp('Eve', 'eve@g.m', 'password1')).user;
    asAmal = SqliteFeedRepository(database, amal.id);
    asSami = SqliteFeedRepository(database, sami.id);
    asEve = SqliteFeedRepository(database, eve.id);
    // Amal and Sami are friends; Eve only follows Sami.
    await asAmal.friendship(sami.id, 'request');
    await asSami.friendship(amal.id, 'accept');
    await asEve.follow(sami.id, true);
  });
  tearDown(() => database.close());

  test('scopes: default hides your own posts, Me shows only yours', () async {
    final mine = await asAmal.create('Mine');
    final friend = await asSami.create('From a friend');
    Future<List<String>> ids(String scope) async =>
        (await asAmal.load(scope: scope)).posts.map((p) => p.id).toList();
    expect(await ids('all'), [friend.id]);
    expect(await ids('me'), [mine.id]);
    expect(await ids('friends'), [friend.id]);
    expect(await ids('following'), isEmpty);
    expect(await ids('connections'), unorderedEquals([mine.id, friend.id]));
    await expectLater(
        asAmal.load(scope: 'everyone'), throwsA(isA<FeedException>()));
  });

  test('photo-only posts are allowed, empty posts are not', () async {
    final post = await asAmal.create('   ', image: photo());
    expect(post.body, '');
    expect(post.hasImage, isTrue);
    await expectLater(asAmal.create('  '), throwsA(isA<FeedException>()));
  });

  test('reposts embed the original, count shares and survive deletion',
      () async {
    final original = await asAmal.create('Sunset at #sidibou', image: photo());

    // Eve cannot see Amal's post directly...
    expect((await asEve.load(scope: 'all')).posts, isEmpty);
    await expectLater(
        asEve.repost(original.id, ''), throwsA(isA<FeedException>()));
    await expectLater(
        asEve.postImage(original.id), throwsA(isA<FeedException>()));

    final repost = await asSami.repost(original.id, ' Look at this! ');
    expect(repost.isRepost, isTrue);
    expect(repost.body, 'Look at this!');
    expect(repost.shared!.authorName, 'Amal');
    expect(repost.shared!.hasImage, isTrue);

    // ...but sees it through Sami's repost, photo included.
    final evesFeed = (await asEve.load(scope: 'all')).posts;
    expect(evesFeed.single.id, repost.id);
    expect(evesFeed.single.shared!.body, 'Sunset at #sidibou');
    expect(await asEve.postImage(original.id), photo().bytes);

    // Reposting a repost shares the original; empty comment is fine.
    final again = await asEve.repost(repost.id, '');
    expect(again.sharedPostId, original.id);
    expect(again.body, '');
    final counted = (await asAmal.load(scope: 'me')).posts.single;
    expect(counted.shareCount, 2);

    // Deleting the original keeps the reposts, marked unavailable.
    await asAmal.delete(original.id);
    final orphan = (await asSami.load(scope: 'me')).posts.single;
    expect(orphan.isRepost, isTrue);
    expect(orphan.shared, isNull);
    await expectLater(
        asSami.repost(orphan.id, ''), throwsA(isA<FeedException>()));
  });

  test('a post sent to a friend appears in the chat with its photo', () async {
    final original = await asSami.create('Concert tonight', image: photo());
    final evesPost = await asEve.create('Eve only');
    final amalChat = SqliteMessagingRepository(database, amal.id);
    final chat = await amalChat.create(kind: 'direct', memberIds: [sami.id]);

    final sent = await amalChat.sendPost(chat.id, original.id);
    expect(sent.body, 'Shared a post by Sami');
    expect(sent.sharedPost!.authorName, 'Sami');

    final samiChat = SqliteMessagingRepository(database, sami.id);
    final received = (await samiChat.messages(chat.id)).messages.single;
    expect(received.sharedPost!.body, 'Concert tonight');
    expect(received.sharedPost!.hasImage, isTrue);
    expect(await samiChat.sharedPostImage(chat.id, received.sequence),
        photo().bytes);
    expect((await samiChat.conversations()).single.lastBody,
        'Shared a post by Sami');

    // Amal cannot see Eve's post, and Eve is not in the chat.
    await expectLater(amalChat.sendPost(chat.id, evesPost.id),
        throwsA(isA<MessagingException>()));
    await expectLater(
        SqliteMessagingRepository(database, eve.id)
            .sharedPostImage(chat.id, received.sequence),
        throwsA(isA<MessagingException>()));

    // A deleted post stays in the chat as unavailable.
    await asSami.delete(original.id);
    final after = (await samiChat.messages(chat.id)).messages.single;
    expect(after.sharedPost!.available, isFalse);
  });

  test('version 9 upgrade keeps posts, reactions and search', () async {
    final dir = await Directory.systemTemp.createTemp('connectly_v9_');
    final filename = '${dir.path}/old.db';
    try {
      final old = await databaseFactoryFfi.openDatabase(filename,
          options: OpenDatabaseOptions(
              version: 1,
              onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
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
                  'body': 'Old post #tunis',
                  'created_at': localTimestamp()
                });
                await db.insert('post_reactions',
                    {'post_id': 'p1', 'user_id': 'u1', 'kind': 'love'});
              }));
      await old.close();

      final upgraded = await LocalDatabase.open(
          factory: databaseFactoryFfi, databasePath: filename);
      try {
        expect(await upgraded.db.getVersion(), 9);
        expect(
            (await upgraded.db.rawQuery('PRAGMA foreign_keys')).single.values,
            [1]);
        // Rebuilding `posts` did not cascade into its reactions.
        expect(
            (await upgraded.db.query('post_reactions')).single['kind'], 'love');
        final repo = SqliteFeedRepository(upgraded, 'u1');
        final page = await repo.load(scope: 'me');
        expect(page.posts.single.reactions['love'], 1);
        expect((await repo.search('#tunis')).single.id, 'p1');
        // Full-text triggers were recreated on the new table.
        final created = await repo.create('Fresh words after upgrade');
        expect((await repo.search('fresh')).single.id, created.id);
        await repo.delete('p1');
        expect(await upgraded.db.query('post_reactions'), isEmpty);
        expect(await repo.search('old'), isEmpty);
      } finally {
        await upgraded.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });

  testWidgets('feed filters and both share options', (tester) async {
    late AuthController controller;
    late FeedPost original;
    await tester.runAsync(() async {
      controller =
          AuthController(repository: auth, store: MemorySessionStore());
      await controller.restore();
      await controller.signIn('amal@g.m', 'password1');
      original = await asSami.create('Sami at the beach');
      await asAmal.create('Amal own post');
    });
    addTearDown(controller.dispose);

    Future<void> settle() async {
      // Real SQLite work needs runAsync; spinners never "settle" meanwhile.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(AuthScope(
        controller: controller,
        child: MaterialApp(
            theme: ConnectlyTheme.dark,
            home: FeedScreen(
                repository: SqliteFeedRepository(database, amal.id),
                messaging: SqliteMessagingRepository(database, amal.id)))));
    await settle();
    // Default view: everyone but me.
    expect(find.text('Sami at the beach'), findsOneWidget);
    expect(find.text('Amal own post'), findsNothing);
    await tester.tap(find.byKey(const Key('filter_me')));
    await settle();
    expect(find.text('Amal own post'), findsOneWidget);
    expect(find.text('Sami at the beach'), findsNothing);
    // Tapping the selected chip again returns to the default view.
    await tester.tap(find.byKey(const Key('filter_me')));
    await settle();
    expect(find.text('Sami at the beach'), findsOneWidget);

    // Repost with a comment.
    await tester.ensureVisible(find.byKey(Key('share_${original.id}')));
    await tester.tap(find.byKey(Key('share_${original.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share_repost')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('repost_comment')), 'Great day!');
    await tester.tap(find.byKey(const Key('repost_submit')));
    await settle();
    expect(find.text('Reposted. You can find it under Me.'), findsOneWidget);
    expect(find.byKey(Key('shares_${original.id}')), findsOneWidget);
    await tester.tap(find.text('View'));
    await settle();
    expect(find.text('Great day!'), findsOneWidget);
    expect(find.text('reposted'), findsOneWidget);

    // Send to a friend.
    await tester.tap(find.byKey(const Key('filter_me')));
    await settle();
    await tester.ensureVisible(find.byKey(Key('share_${original.id}')));
    await tester.tap(find.byKey(Key('share_${original.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share_send')));
    await settle();
    await tester.tap(find.byKey(Key('send_to_${sami.id}')));
    await settle();
    expect(find.text('Sent to Sami in Chats.'), findsOneWidget);
    await tester.runAsync(() async {
      expect((await database.db.query('message_posts')).single['post_id'],
          original.id);
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

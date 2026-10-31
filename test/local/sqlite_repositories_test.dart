import 'dart:io';
import 'dart:typed_data';
import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/features/auth/domain/auth_models.dart';
import 'package:connectly/features/feed/data/sqlite_feed_repository.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';
import 'package:connectly/features/messaging/data/sqlite_messaging_repository.dart';
import 'package:connectly/features/messaging/domain/messaging_models.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late LocalDatabase database;
  late SqliteAuthRepository auth;
  Future<AuthSession> account(String name) => auth.signUp(
      name, '${name.toLowerCase()}@example.test', ' correct password ');
  setUp(() async {
    database = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    // Only tests reduce the work factor. The app uses 120,000 rounds.
    auth = SqliteAuthRepository(database,
        passwords: LocalPasswords(iterations: 1000));
  });
  tearDown(() => database.close());

  test('new SQLite database is empty and has foreign keys enabled', () async {
    expect(await database.db.query('users'), isEmpty);
    expect(await database.db.query('posts'), isEmpty);
    expect(await database.db.query('conversations'), isEmpty);
    expect(
        (await database.db.rawQuery('PRAGMA foreign_keys'))
            .single
            .values
            .single,
        1);
    expect(await database.db.getVersion(), 4);
    await expectLater(
        database.db.insert('posts', {
          'id': 'invalid',
          'author_id': 'missing',
          'body': 'Invalid',
          'created_at': localTimestamp()
        }),
        throwsA(isA<DatabaseException>()));
  });

  test(
      'local authentication normalizes emails, hashes passwords, restores and revokes sessions',
      () async {
    final first = await auth.signUp(
        '  Local Member  ', ' MEMBER@EXAMPLE.TEST ', ' password with spaces ');
    expect(first.user.name, 'Local Member');
    expect(first.user.email, 'member@example.test');
    final row = (await database.db.query('users')).single;
    expect(row['password_hash'], startsWith(r'pbkdf2_sha256$'));
    expect(row['password_hash'], isNot(contains('password with spaces')));
    await expectLater(
        auth.signUp('Duplicate', 'member@example.test', 'another password'),
        throwsA(isA<AuthException>()));
    await expectLater(
        auth.signIn('member@example.test', 'password with spaces'),
        throwsA(isA<AuthException>()));
    final login =
        await auth.signIn('MEMBER@example.test', ' password with spaces ');
    expect((await auth.currentUser(login.token)).id, first.user.id);
    final biometricToken = await auth.createBiometricToken(login.token);
    await auth.signOut(login.token);
    await expectLater(
        auth.currentUser(login.token),
        throwsA(isA<AuthException>()
            .having((e) => e.statusCode, 'expired session', 401)));
    expect((await auth.currentUser(first.token)).id, first.user.id);
    final biometricLogin = await auth.signInWithBiometricToken(biometricToken);
    expect(biometricLogin.user.id, first.user.id);
    await auth.revokeBiometricToken(biometricToken);
    await expectLater(auth.signInWithBiometricToken(biometricToken),
        throwsA(isA<AuthException>()));
    await database.db
        .update('auth_sessions', {'expires_at': '2000-01-01T00:00:00.000Z'});
    await expectLater(
        auth.currentUser(first.token), throwsA(isA<AuthException>()));
    final passwords = LocalPasswords(iterations: 1000);
    expect(await passwords.hash('same password'),
        isNot(await passwords.hash('same password')));
  });

  test('friends/following visibility and reactions work between local accounts',
      () async {
    final a = await account('Alpha');
    final b = await account('Beta');
    final c = await account('Gamma');
    final feedA = SqliteFeedRepository(database, a.user.id);
    final feedB = SqliteFeedRepository(database, b.user.id);
    final feedC = SqliteFeedRepository(database, c.user.id);
    final post = await feedA.create('  A local post  ');
    expect(post.body, 'A local post');
    expect((await feedB.load(scope: 'connections')).posts, isEmpty);
    await expectLater(
        feedB.react(post.id, 'like'), throwsA(isA<FeedException>()));
    await feedB.follow(a.user.id, true);
    expect((await feedB.load(scope: 'following')).posts.single.id, post.id);
    expect((await feedB.load(scope: 'friends')).posts, isEmpty);
    await feedC.friendship(a.user.id, 'request');
    expect((await feedC.load(scope: 'friends')).posts, isEmpty);
    await expectLater(
        feedC.friendship(a.user.id, 'accept'), throwsA(isA<FeedException>()));
    expect((await feedA.people(requests: true)).single.friendship, 'incoming');
    await feedA.friendship(c.user.id, 'accept');
    expect((await feedC.load(scope: 'friends')).posts.single.id, post.id);
    await feedB.react(post.id, 'like');
    final changed = await feedB.react(post.id, 'love');
    expect(changed.reactions['like'], 0);
    expect(changed.reactions['love'], 1);
    expect((await feedB.react(post.id, 'love')).reactionCount, 1);
    await feedC.react(post.id, 'celebrate');
    expect((await feedB.react(post.id, null)).reactionCount, 1);
    await feedB.delete(post.id);
    expect((await feedA.load(scope: 'connections')).posts.single.id, post.id);
    await feedA.delete(post.id);
    expect(await database.db.query('post_reactions'), isEmpty);
    await feedA.create('Another post');
    await feedB.follow(a.user.id, false);
    await feedC.friendship(a.user.id, 'remove');
    expect((await feedB.load(scope: 'connections')).posts, isEmpty);
    expect((await feedC.load(scope: 'connections')).posts, isEmpty);
  });

  test(
      'feed cursor pagination preserves tied timestamps and SQLite parameter binding',
      () async {
    final a = await account('Alpha');
    final feed = SqliteFeedRepository(database, a.user.id);
    await database.db.transaction((txn) async {
      for (var i = 0; i < 23; i++) {
        await txn.insert('posts', {
          'id': localId(),
          'author_id': a.user.id,
          'body': "Quoted post '$i",
          'created_at': '2026-10-26T12:00:00.000Z'
        });
      }
    });
    final first = await feed.load(scope: 'connections');
    final second =
        await feed.load(scope: 'connections', cursor: first.nextCursor);
    expect(first.posts.length, 20);
    expect(second.posts.length, 3);
    expect(
        {...first.posts.map((p) => p.id), ...second.posts.map((p) => p.id)}
            .length,
        23);
    expect((await feed.create("It's a post; DROP TABLE users;")).body,
        "It's a post; DROP TABLE users;");
    expect((await database.db.query('users')).length, 1);
  });

  test(
      'direct chats deduplicate and enforce account membership with safe message retries',
      () async {
    final a = await account('Alpha');
    final b = await account('Beta');
    final c = await account('Gamma');
    final chatsA = SqliteMessagingRepository(database, a.user.id);
    final chatsB = SqliteMessagingRepository(database, b.user.id);
    final chatsC = SqliteMessagingRepository(database, c.user.id);
    await expectLater(chatsA.create(kind: 'direct', memberIds: [b.user.id]),
        throwsA(isA<MessagingException>()));
    await SqliteFeedRepository(database, a.user.id).follow(b.user.id, true);
    await SqliteFeedRepository(database, b.user.id).follow(a.user.id, true);
    final conversation =
        await chatsA.create(kind: 'direct', memberIds: [b.user.id]);
    expect((await chatsB.create(kind: 'direct', memberIds: [a.user.id])).id,
        conversation.id);
    expect((await chatsA.members(conversation.id)).length, 2);
    expect(await chatsC.conversations(), isEmpty);
    await expectLater(
        chatsC.messages(conversation.id), throwsA(isA<MessagingException>()));
    await expectLater(
        chatsC.members(conversation.id), throwsA(isA<MessagingException>()));
    await expectLater(chatsC.send(conversation.id, localId(), 'No access'),
        throwsA(isA<MessagingException>()));
    await expectLater(chatsC.markRead(conversation.id, 99999),
        throwsA(isA<MessagingException>()));
    final id = localId();
    final message = await chatsA.send(conversation.id, id, '  Hello offline  ');
    expect((await chatsA.send(conversation.id, id, 'Hello offline')).sequence,
        message.sequence);
    await expectLater(chatsA.send(conversation.id, id, 'Changed retry'),
        throwsA(isA<MessagingException>()));
    expect((await chatsB.messages(conversation.id)).messages.single.sender.id,
        a.user.id);
    expect((await chatsB.conversations()).single.unreadCount, 1);
    await chatsB.markRead(conversation.id, 9999999);
    expect((await chatsB.conversations()).single.unreadCount, 0);
    final reply =
        await chatsB.send(conversation.id, localId(), 'Reply from Beta');
    expect(
        (await chatsA.messages(conversation.id, after: message.sequence))
            .messages
            .single
            .sequence,
        reply.sequence);
    await chatsA.send(conversation.id, localId(), 'New unread');
    expect((await chatsB.conversations()).single.unreadCount, 1);
  });

  test('voice messages persist, deduplicate, and respect membership', () async {
    final a = await account('Alpha');
    final b = await account('Beta');
    final c = await account('Gamma');
    await SqliteFeedRepository(database, a.user.id).follow(b.user.id, true);
    final sender = SqliteMessagingRepository(database, a.user.id);
    final recipient = SqliteMessagingRepository(database, b.user.id);
    final outsider = SqliteMessagingRepository(database, c.user.id);
    final chat = await sender.create(kind: 'direct', memberIds: [b.user.id]);
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final id = localId();
    final voice = await sender.sendVoice(chat.id, id, bytes, 1200);
    expect(voice.isVoice, isTrue);
    expect(voice.voiceDurationMs, 1200);
    expect((await recipient.messages(chat.id)).messages.single.isVoice, isTrue);
    expect(await recipient.voiceBytes(chat.id, voice.sequence), bytes);
    expect((await sender.sendVoice(chat.id, id, bytes, 1200)).sequence,
        voice.sequence);
    await expectLater(
        sender.sendVoice(chat.id, id, Uint8List.fromList([9]), 1200),
        throwsA(isA<MessagingException>()));
    await expectLater(outsider.voiceBytes(chat.id, voice.sequence),
        throwsA(isA<MessagingException>()));
    expect((await recipient.conversations()).single.lastBody, 'Voice message');
  });

  test(
      'group membership and both message cursors work with a real local database',
      () async {
    final a = await account('Alpha');
    final b = await account('Beta');
    final c = await account('Gamma');
    final feed = SqliteFeedRepository(database, a.user.id);
    await feed.follow(b.user.id, true);
    await feed.friendship(c.user.id, 'request');
    await SqliteFeedRepository(database, c.user.id)
        .friendship(a.user.id, 'accept');
    final chatsA = SqliteMessagingRepository(database, a.user.id);
    final chatsC = SqliteMessagingRepository(database, c.user.id);
    expect((await chatsA.contacts('')).length, 2);
    expect((await chatsA.friends()).map((friend) => friend.id), [c.user.id]);
    expect((await chatsC.friends()).map((friend) => friend.id), [a.user.id]);
    final group = await chatsA.create(
        kind: 'group',
        title: ' Study group ',
        memberIds: [b.user.id, c.user.id]);
    expect(group.title, 'Study group');
    expect(group.memberCount, 3);
    await expectLater(
        chatsA.create(
            kind: 'group', title: 'Invalid', memberIds: [b.user.id, b.user.id]),
        throwsA(isA<MessagingException>()));
    await database.db.transaction((txn) async {
      for (var i = 0; i < 57; i++) {
        await txn.insert('messages', {
          'conversation_id': group.id,
          'sender_id': a.user.id,
          'client_id': localId(),
          'body': 'Message $i',
          'created_at': '2026-10-26T12:00:00.000Z'
        });
      }
    });
    final latest = await chatsC.messages(group.id);
    final older = await chatsC.messages(group.id, before: latest.olderCursor);
    expect(latest.messages.length, 50);
    expect(older.messages.length, 7);
    expect(
        {
          ...latest.messages.map((m) => m.sequence),
          ...older.messages.map((m) => m.sequence)
        }.length,
        57);
    final increments = await chatsC.messages(group.id, after: 0);
    expect(increments.hasMore, isTrue);
    expect(
        (await chatsC.messages(group.id,
                after: increments.messages.last.sequence))
            .messages
            .length,
        7);
    await expectLater(chatsC.messages(group.id, before: 10, after: 1),
        throwsA(isA<MessagingException>()));
  });

  test(
      'accounts, session and messages survive closing and reopening the database file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('connectly_sqlite_');
    final filename =
        '${directory.path}${Platform.pathSeparator}presentation.db';
    LocalDatabase? fileDb;
    try {
      fileDb = await LocalDatabase.open(
          factory: databaseFactoryFfi, databasePath: filename);
      final fileAuth = SqliteAuthRepository(fileDb,
          passwords: LocalPasswords(iterations: 1000));
      final a =
          await fileAuth.signUp('Alpha', 'alpha@example.test', 'password123');
      final b =
          await fileAuth.signUp('Beta', 'beta@example.test', 'password123');
      await SqliteFeedRepository(fileDb, a.user.id).follow(b.user.id, true);
      final chats = SqliteMessagingRepository(fileDb, a.user.id);
      final conversation =
          await chats.create(kind: 'direct', memberIds: [b.user.id]);
      await chats.send(conversation.id, localId(), 'Saved on this phone');
      final voice = await chats.sendVoice(
          conversation.id, localId(), Uint8List.fromList([7, 8, 9]), 1800);
      await fileDb.close();
      fileDb = await LocalDatabase.open(
          factory: databaseFactoryFfi, databasePath: filename);
      expect((await SqliteAuthRepository(fileDb).currentUser(a.token)).id,
          a.user.id);
      final reopened = SqliteMessagingRepository(fileDb, b.user.id);
      final messages = (await reopened.messages(conversation.id)).messages;
      expect(messages.first.body, 'Saved on this phone');
      expect(messages.last.isVoice, isTrue);
      expect(await reopened.voiceBytes(conversation.id, voice.sequence),
          [7, 8, 9]);
      expect((await fileDb.db.query('users')).length, 2);
    } finally {
      await fileDb?.close();
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final resolved = await directory.resolveSymbolicLinks();
      if (!resolved
          .startsWith('$tempRoot${Platform.pathSeparator}connectly_sqlite_')) {
        throw StateError('Unexpected test directory.');
      }
      await directory.delete(recursive: true);
    }
  });
}

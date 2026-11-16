import 'dart:typed_data';
import 'package:connectly/app/connectly_theme.dart';
import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/data/local_passwords.dart';
import 'package:connectly/features/auth/data/sqlite_auth_repository.dart';
import 'package:connectly/features/auth/presentation/auth_scope.dart';
import 'package:connectly/features/feed/data/sqlite_feed_repository.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';
import 'package:connectly/features/feed/presentation/feed_screen.dart';
import 'package:connectly/shared/data/local_database.dart';
import 'package:connectly/shared/presentation/photo_crop_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../features/auth/auth_controller_test.dart'
    show FakeAuthRepository, MemorySessionStore;
import '../features/feed/feed_fakes.dart';

Uint8List png(int width, int height) => Uint8List.fromList(img.encodePng(
    img.fill(img.Image(width: width, height: height),
        color: img.ColorRgb8(40, 120, 200))));

void main() {
  sqfliteFfiInit();

  test('post photos are shrunk to 1280 px on the longest side', () {
    final wide = resizePostPhoto(png(3000, 1500));
    expect((wide.width, wide.height), (1280, 640));
    expect(img.decodeJpg(wide.bytes)!.width, 1280);
    final tall = resizePostPhoto(png(1000, 2000));
    expect((tall.width, tall.height), (640, 1280));
    final small = resizePostPhoto(png(300, 200));
    expect((small.width, small.height), (300, 200));
    expect(() => resizePostPhoto(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });

  test('photos are stored with the post, visible only to connections',
      () async {
    final database = await LocalDatabase.open(
        factory: databaseFactoryFfi, databasePath: inMemoryDatabasePath);
    addTearDown(database.close);
    final auth = SqliteAuthRepository(database,
        passwords: LocalPasswords(iterations: 1000));
    final amal = (await auth.signUp('Amal', 'amal@g.m', 'password1')).user;
    final eve = (await auth.signUp('Eve', 'eve@g.m', 'password1')).user;
    final asAmal = SqliteFeedRepository(database, amal.id);
    final photo = resizePostPhoto(png(800, 600));

    final post = await asAmal.create('Sunset #ariana',
        image: FeedImageUpload(
            bytes: photo.bytes, width: photo.width, height: photo.height));
    expect(post.hasImage, isTrue);
    expect((post.imageWidth, post.imageHeight), (800, 600));
    final text = await asAmal.create('No photo here');
    expect(text.hasImage, isFalse);

    // A fresh repository (no cache) reads the bytes from SQLite.
    final reader = SqliteFeedRepository(database, amal.id);
    expect(await reader.postImage(post.id), photo.bytes);
    final page = await reader.load(scope: 'connections');
    expect(page.posts.firstWhere((p) => p.id == post.id).imageHeight, 600);
    expect((await reader.search('#ariana')).single.hasImage, isTrue);
    await expectLater(reader.postImage(text.id), throwsA(isA<FeedException>()));

    // Eve is not connected to Amal and cannot load the photo.
    await expectLater(SqliteFeedRepository(database, eve.id).postImage(post.id),
        throwsA(isA<FeedException>()));

    await expectLater(
        asAmal.create('Too big',
            image: FeedImageUpload(
                bytes: Uint8List(2000001), width: 10, height: 10)),
        throwsA(isA<FeedException>()));

    // Deleting the post deletes its photo.
    await asAmal.delete(post.id);
    expect(await database.db.query('post_images'), isEmpty);
  });

  testWidgets('composer attaches a photo, can remove it, and publishes it',
      (tester) async {
    final repository = FakeFeedRepository()..posts = [];
    final auth = AuthController(
        repository: FakeAuthRepository(), store: MemorySessionStore());
    addTearDown(auth.dispose);
    await auth.signIn('member@example.com', 'password');
    final picked = png(1600, 900);
    await tester.pumpWidget(AuthScope(
        controller: auth,
        child: MaterialApp(
            theme: ConnectlyTheme.dark,
            home: FeedScreen(
                repository: repository, pickPostImage: (_) async => picked))));
    await tester.pumpAndSettle();

    Future<void> addPhoto() async {
      await tester.tap(find.byKey(const Key('post_add_photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo_source_gallery')));
      // Resizing runs in a background isolate.
      for (var i = 0;
          i < 50 &&
              find.byKey(const Key('post_photo_preview')).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    await tester.tap(find.byKey(const Key('create_post')));
    await tester.pumpAndSettle();
    await addPhoto();
    expect(find.byKey(const Key('post_photo_preview')), findsOneWidget);
    expect(find.text('Write a caption…'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('post_remove_photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('post_remove_photo')));
    await tester.pump();
    expect(find.byKey(const Key('post_photo_preview')), findsNothing);

    await addPhoto();
    await tester.enterText(find.byKey(const Key('post_body')), 'Beach day');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('publish_post')));
    await tester.tap(find.byKey(const Key('publish_post')));
    await tester.pumpAndSettle();
    expect(repository.lastImage, isNotNull);
    expect((repository.lastImage!.width, repository.lastImage!.height),
        (1280, 720));

    // The new card reserves space for the photo while it loads.
    expect(find.byKey(const Key('post_image_new-post')), findsNothing);
    expect(find.text('Beach day'), findsOneWidget);
    expect(find.byType(AspectRatio), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

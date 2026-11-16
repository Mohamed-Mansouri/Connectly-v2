import 'dart:async';
import 'package:connectly/app/connectly_theme.dart';
import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/presentation/auth_scope.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';
import 'package:connectly/features/feed/presentation/feed_screen.dart';
import 'package:connectly/features/discovery/presentation/people_screen.dart';
import '../discovery/people_fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../auth/auth_controller_test.dart'
    show FakeAuthRepository, MemorySessionStore;
import 'feed_fakes.dart';

Future<AuthController> pumpFeed(
    WidgetTester tester, FakeFeedRepository repository) async {
  final auth = AuthController(
      repository: FakeAuthRepository(), store: MemorySessionStore());
  await auth.signIn('member@example.com', 'password');
  await tester.pumpWidget(AuthScope(
      controller: auth,
      child: MaterialApp(
          theme: ConnectlyTheme.dark,
          home: FeedScreen(repository: repository))));
  await tester.pumpAndSettle();
  addTearDown(auth.dispose);
  return auth;
}

void main() {
  testWidgets('signed-in feed renders posts, filters, and a comment action',
      (tester) async {
    await pumpFeed(tester, FakeFeedRepository());
    expect(find.text('A little update post-1'), findsOneWidget);
    expect(find.text('Connections'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Comment'), findsOneWidget);
    expect(find.byKey(const Key('feed_people')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comments can be written and update the post count',
      (tester) async {
    final repository = FakeFeedRepository();
    await pumpFeed(tester, repository);
    await tester.tap(find.byKey(const Key('comment_post-1')));
    await tester.pumpAndSettle();
    expect(
        find.text('No comments yet. Start the conversation.'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('comment_input')), 'Great update!');
    await tester.pump();
    await tester.tap(find.byKey(const Key('comment_send')));
    await tester.pumpAndSettle();
    expect(find.text('Great update!'), findsOneWidget);
    expect(find.text('Comments · 1'), findsOneWidget);
    expect(repository.commentList.single.postId, 'post-1');
    Navigator.of(tester.element(find.text('Great update!'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('1 comment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping reaction counts lists who reacted', (tester) async {
    final repository = FakeFeedRepository()
      ..posts = [testPost('post-1', reaction: 'like')]
      ..reactorList = const [
        FeedReactor(userId: 'user-1', name: 'Test Member', kind: 'like'),
        FeedReactor(userId: 'user-2', name: 'Sara Ben Ali', kind: 'love'),
      ];
    await pumpFeed(tester, repository);
    await tester.tap(find.byKey(const Key('reactors_post-1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Test Member · You'), findsOneWidget);
    expect(find.text('Sara Ben Ali'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reactors_filter_love')));
    await tester.pumpAndSettle();
    expect(find.text('Sara Ben Ali'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Test Member · You'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'composer validates empty text, prevents duplicate publish, and inserts the new post',
      (tester) async {
    final repository = FakeFeedRepository()
      ..pendingCreate = Completer<FeedPost>();
    await pumpFeed(tester, repository);
    await tester.tap(find.byKey(const Key('create_post')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('publish_post')))
            .onPressed,
        isNull);
    await tester.enterText(
        find.byKey(const Key('post_body')), 'My first real post');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('publish_post')));
    await tester.tap(find.byKey(const Key('publish_post')));
    await tester.pump();
    expect(repository.createCalls, 1);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('publish_post')))
            .onPressed,
        isNull);
    repository.pendingCreate!.complete(FeedPost(
        id: 'new',
        authorId: 'user-1',
        authorName: 'Test Member',
        body: 'My first real post',
        createdAt: DateTime.now(),
        reactions: {}));
    await tester.pumpAndSettle();
    expect(find.text('My first real post'), findsOneWidget);
    expect(find.text('Create a post'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed publication retains the text for retry', (tester) async {
    final repository = FakeFeedRepository()
      ..createError = const FeedException('Offline');
    await pumpFeed(tester, repository);
    await tester.tap(find.byKey(const Key('create_post')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('post_body')), 'Keep my words');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('publish_post')));
    await tester.tap(find.byKey(const Key('publish_post')));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Keep my words'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('people accepts an incoming request and follows independently',
      (tester) async {
    final repository = FakeFeedRepository()
      ..members = [
        const FeedPerson(
            id: 'other',
            name: 'Another Member',
            isFollowing: false,
            friendship: 'incoming')
      ];
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        home: PeopleScreen(repository: FakePeopleRepository(repository))));
    await tester.pump();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Accept request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept request'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Follow'));
    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(repository.actions, ['friend:other:accept', 'follow:other:true']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small feed and people layouts tolerate enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpFeed(tester, FakeFeedRepository());
    expect(tester.takeException(), isNull);
    final repository = FakeFeedRepository()
      ..members = [
        const FeedPerson(
            id: 'other',
            name: 'A member with a longer display name',
            isFollowing: false,
            friendship: 'incoming')
      ];
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: PeopleScreen(repository: FakePeopleRepository(repository))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tags open search; trends, typing and suggestions work',
      (tester) async {
    final repository = FakeFeedRepository()
      ..posts = [
        FeedPost(
            id: 'tagged',
            authorId: 'user-2',
            authorName: 'Amal',
            body: 'Sunny day at the beach #trip with @member',
            createdAt: DateTime.utc(2026, 10, 24),
            reactions: const {})
      ]
      ..suggestionList = const [FeedSuggestion('@amal', 'Demo Amal')];
    await pumpFeed(tester, repository);

    // Tapping a hashtag in a post searches for it.
    await tester.scrollUntilVisible(find.textContaining('Sunny day'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tapOnText(find.textRange.ofSubstring('#trip'));
    await tester.pumpAndSettle();
    expect(repository.searches, ['#trip']);
    expect(find.byKey(const Key('search_count')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Empty search shows trends and the mentions shortcut.
    await tester.tap(find.byKey(const Key('feed_search')));
    await tester.pumpAndSettle();
    expect(find.text('#travel · 3'), findsOneWidget);
    expect(find.text('@member'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trend_travel')));
    await tester.pumpAndSettle();
    expect(repository.searches.last, '#travel');
    expect(find.text('No posts found'), findsOneWidget);

    // Typing searches after a short pause and highlights words.
    await tester.enterText(find.byKey(const Key('search_input')), 'beach');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repository.searches.last, 'beach');
    expect(find.text('1 post'), findsOneWidget);

    // @ in the search box suggests people and completes the word.
    await tester.enterText(find.byKey(const Key('search_input')), '@am');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('suggest_@amal')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('search_input')))
            .controller!
            .text,
        '@amal ');
    expect(tester.takeException(), isNull);
  });
}

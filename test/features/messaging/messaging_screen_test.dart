import 'package:connectly/app/connectly_theme.dart';
import 'package:connectly/features/auth/application/auth_controller.dart';
import 'package:connectly/features/auth/presentation/auth_scope.dart';
import 'package:connectly/features/messaging/data/chat_local_store.dart';
import 'package:connectly/features/messaging/domain/messaging_models.dart';
import 'package:connectly/features/messaging/presentation/conversation_screen.dart';
import 'package:connectly/features/messaging/presentation/messages_screen.dart';
import 'package:connectly/features/messaging/presentation/new_conversation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../auth/auth_controller_test.dart'
    show FakeAuthRepository, MemorySessionStore;
import 'messaging_fakes.dart';

void main() {
  testWidgets('conversation sends text and displays the confirmed message',
      (tester) async {
    final repository = FakeMessagingRepository()..history = [testMessage(1)];
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        home: ConversationScreen(
            conversation: testConversation,
            repository: repository,
            store: MemoryChatLocalStore(),
            userId: 'user-1')));
    await tester.pumpAndSettle();
    expect(find.text('Message 1'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byKey(const Key('send_message')))
            .onPressed,
        isNull);
    await tester.enterText(
        find.byKey(const Key('message_input')), 'A shared reply');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message')));
    await tester.pumpAndSettle();
    expect(repository.sentIds.length, 1);
    expect(find.text('A shared reply'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('message_input')))
            .controller!
            .text,
        isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed message exposes retry and preserves its original ID',
      (tester) async {
    final repository = FakeMessagingRepository()
      ..onSend = (_, __) async => throw const MessagingException('Offline');
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        home: ConversationScreen(
            conversation: testConversation,
            repository: repository,
            store: MemoryChatLocalStore(),
            userId: 'user-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('message_input')), 'Keep this message');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_message')));
    await tester.pumpAndSettle();
    expect(find.text('Keep this message'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    final id = repository.sentIds.single;
    repository.onSend = null;
    await tester.tap(find.byKey(Key('retry_$id')));
    await tester.pumpAndSettle();
    expect(repository.sentIds, [id, id]);
    expect(find.text('Offline'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('group creation validates and passes the selected people',
      (tester) async {
    final repository = FakeMessagingRepository();
    Conversation? created;
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        home: Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () async {
                      created = await Navigator.push<Conversation>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => NewConversationScreen(
                                  repository: repository)));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group chat'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('start_conversation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start_conversation')));
    await tester.pumpAndSettle();
    expect(
        find.text('Select at least two people for a group.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('group_title')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group_title')), 'Study group');
    await tester.ensureVisible(find.byKey(const Key('contact_other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact_other')));
    await tester.ensureVisible(find.byKey(const Key('contact_third')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact_third')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('start_conversation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start_conversation')));
    await tester.pumpAndSettle();
    expect(repository.createdKind, 'group');
    expect(repository.createdMembers, ['other', 'third']);
    expect(repository.createdTitle, 'Study group');
    expect(created?.id, 'chat-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden inbox does not poll until the Chats tab is active',
      (tester) async {
    final repository = FakeMessagingRepository();
    final auth = AuthController(
        repository: FakeAuthRepository(), store: MemorySessionStore());
    await auth.signIn('member@example.com', 'password');
    Widget app(bool visible) => AuthScope(
        controller: auth,
        child: MaterialApp(
            theme: ConnectlyTheme.dark,
            home: TickerMode(
                enabled: visible,
                child: MessagesScreen(
                    repository: repository,
                    localStore: MemoryChatLocalStore()))));
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(repository.inboxCalls, 0);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(repository.inboxCalls, 1);
    expect(find.text('Another Member'), findsOneWidget);
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(seconds: 12));
    expect(repository.inboxCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  testWidgets(
      'small chat layout remains usable with keyboard and enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                viewInsets: const EdgeInsets.only(bottom: 240),
                textScaler: const TextScaler.linear(1.4)),
            child: child!),
        home: ConversationScreen(
            conversation: testConversation,
            repository: FakeMessagingRepository()..history = [testMessage(1)],
            store: MemoryChatLocalStore(),
            userId: 'user-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message_input')), findsOneWidget);
    expect(tester.getBottomLeft(find.byKey(const Key('send_message'))).dy,
        lessThan(400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

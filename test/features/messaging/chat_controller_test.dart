import 'dart:async';
import 'package:connectly/features/messaging/application/chat_controller.dart';
import 'package:connectly/features/messaging/data/chat_local_store.dart';
import 'package:connectly/features/messaging/domain/messaging_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'messaging_fakes.dart';

ChatController controllerFor(FakeMessagingRepository repository,
        {ChatLocalStore? store}) =>
    ChatController(
        repository: repository,
        store: store ?? MemoryChatLocalStore(),
        userId: 'user-1',
        conversationId: 'chat-1');

class FailingStore extends MemoryChatLocalStore {
  @override
  Future<void> write(
      String userId, String conversationId, String encoded) async {
    throw StateError('Storage unavailable');
  }
}

void main() {
  test('retry keeps the same client ID after a lost response', () async {
    final repository = FakeMessagingRepository();
    var loseResponse = true;
    repository.onSend = (clientId, body) async {
      if (repository.history.isEmpty) {
        repository.history.add(
            testMessage(1, clientId: clientId, senderId: 'user-1', body: body));
      }
      if (loseResponse) {
        loseResponse = false;
        throw const MessagingException('Connection lost');
      }
      return repository.history.single;
    };
    final controller = controllerFor(repository);
    await controller.initialize();
    controller.updateDraft('Hello there');
    await controller.sendDraft();
    expect(controller.outbox.single.error, 'Connection lost');
    await controller.retry(controller.outbox.single);
    expect(repository.sentIds.length, 2);
    expect(repository.sentIds[0], repository.sentIds[1]);
    expect(repository.history.length, 1);
    expect(controller.messages.single.body, 'Hello there');
    expect(controller.outbox, isEmpty);
    controller.dispose();
  });

  test('send responses do not skip an intervening incoming message', () async {
    final repository = FakeMessagingRepository()..history = [testMessage(1)];
    final controller = controllerFor(repository);
    await controller.initialize();
    repository.onSend = (clientId, body) async {
      repository.history.addAll([
        testMessage(2),
        testMessage(3, clientId: clientId, senderId: 'user-1', body: body)
      ]);
      return repository.history.last;
    };
    controller.updateDraft('My reply');
    await controller.sendDraft();
    expect(controller.messages.map((m) => m.sequence), [1, 3]);
    await controller.sync();
    expect(controller.messages.map((m) => m.sequence), [1, 2, 3]);
    expect(controller.outbox, isEmpty);
    controller.dispose();
  });

  test('recovered pending messages reconcile against server history', () async {
    final store = MemoryChatLocalStore();
    final pending = QueuedMessage(
        clientId: 'pending-id',
        body: 'Already sent',
        createdAt: DateTime.now());
    await store.write('user-1', 'chat-1',
        ChatLocalData(draft: 'Keep my draft', outbox: [pending]).encode());
    final repository = FakeMessagingRepository()
      ..history = [
        testMessage(5,
            clientId: 'pending-id', senderId: 'user-1', body: 'Already sent')
      ];
    final controller = controllerFor(repository, store: store);
    await controller.initialize();
    expect(controller.draft, 'Keep my draft');
    expect(controller.outbox, isEmpty);
    expect(repository.sentIds, isEmpty);
    expect((await store.read('user-1', 'chat-1')).outbox, isEmpty);
    controller.dispose();
  });

  test('storage failure keeps pending text and prevents an untracked send',
      () async {
    final repository = FakeMessagingRepository();
    final controller = controllerFor(repository, store: FailingStore());
    await controller.initialize();
    controller.updateDraft('Do not lose this');
    await controller.sendDraft();
    expect(repository.sentIds, isEmpty);
    expect(controller.outbox.single.body, 'Do not lose this');
    expect(controller.outbox.single.error, isNotNull);
    controller.dispose();
  });

  test('duplicate taps are blocked while sending', () async {
    final pending = Completer<ChatMessage>();
    final repository = FakeMessagingRepository()
      ..onSend = (_, __) => pending.future;
    final controller = controllerFor(repository);
    await controller.initialize();
    controller.updateDraft('Once');
    final sending = controller.sendDraft();
    await Future<void>.delayed(Duration.zero);
    await controller.sendDraft();
    expect(repository.sentIds.length, 1);
    pending.complete(testMessage(1,
        clientId: repository.sentIds.single, senderId: 'user-1', body: 'Once'));
    await sending;
    expect(controller.outbox, isEmpty);
    controller.dispose();
  });

  test('history pagination merges by server sequence without duplicates',
      () async {
    final repository = FakeMessagingRepository()
      ..onMessages = (before, after) async => before == null
          ? MessagePage([testMessage(3), testMessage(4)], olderCursor: 3)
          : MessagePage([testMessage(1), testMessage(2), testMessage(3)]);
    final controller = controllerFor(repository);
    await controller.initialize();
    await controller.loadOlder();
    expect(controller.messages.map((m) => m.sequence), [1, 2, 3, 4]);
    expect(controller.olderCursor, isNull);
    controller.dispose();
  });

  test('read markers are not sent while the conversation is inactive',
      () async {
    final repository = FakeMessagingRepository()..history = [testMessage(1)];
    final controller = controllerFor(repository);
    await controller.initialize();
    expect(repository.readMarkers, isEmpty);
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(repository.readMarkers, [1]);
    controller.setActive(false);
    repository.history.add(testMessage(2));
    await controller.sync();
    expect(repository.readMarkers, [1]);
    controller.dispose();
  });
}

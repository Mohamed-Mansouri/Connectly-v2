import 'dart:io';
import 'package:connectly/features/messaging/data/chat_local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('Hive restores scoped drafts/outbox and clears empty records', () async {
    final directory =
        await Directory.systemTemp.createTemp('connectly_messages_');
    Hive.init(directory.path);
    try {
      var box = await Hive.openBox<String>('messaging_local_test');
      var store = HiveChatLocalStore(box);
      await store.write(
          'user-a',
          'chat-a',
          ChatLocalData(draft: 'Saved words', outbox: [
            QueuedMessage(
                clientId: 'stable-id',
                body: 'Retry me',
                createdAt: DateTime.utc(2026))
          ]).encode());
      await box.close();
      box = await Hive.openBox<String>('messaging_local_test');
      store = HiveChatLocalStore(box);
      final recovered = await store.read('user-a', 'chat-a');
      expect(recovered.draft, 'Saved words');
      expect(recovered.outbox.single.clientId, 'stable-id');
      expect(recovered.outbox.single.sending, isFalse);
      expect(recovered.outbox.single.error, isNotNull);
      expect((await store.read('user-b', 'chat-a')).draft, isEmpty);
      expect((await store.read('user-a', 'chat-b')).outbox, isEmpty);
      await store.write('user-a', 'chat-a', const ChatLocalData().encode());
      expect(box.keys, isEmpty);
      await box.close();
    } finally {
      await Hive.close();
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final testPath = await directory.resolveSymbolicLinks();
      if (!testPath.startsWith(
          '$tempRoot${Platform.pathSeparator}connectly_messages_')) {
        throw StateError('Unexpected test path.');
      }
      await directory.delete(recursive: true);
    }
  });
}

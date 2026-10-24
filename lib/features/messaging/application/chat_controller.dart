import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/chat_local_store.dart';
import '../domain/messaging_models.dart';

String newMessageId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String chatError(Object error) => error is MessagingException
    ? error.message
    : 'Something went wrong. Please try again.';

class ChatController extends ChangeNotifier {
  ChatController(
      {required this.repository,
      required this.store,
      required this.userId,
      required this.conversationId});
  final MessagingRepository repository;
  final ChatLocalStore store;
  final String userId;
  final String conversationId;
  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  final List<QueuedMessage> outbox = [];
  String draft = '';
  String? error;
  String? storageError;
  bool initializing = true;
  bool loadingOlder = false;
  bool sending = false;
  int? olderCursor;
  int _syncedThrough = 0;
  int _readThrough = 0;
  bool _loaded = false;
  bool get loading => !_loaded && _syncing;
  bool _syncing = false;
  bool _active = false;
  bool _disposed = false;
  Timer? _poll;
  Timer? _draftTimer;
  Future<void> _writes = Future.value();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final local = await store.read(userId, conversationId);
      if (_disposed) return;
      draft = local.draft;
      outbox.addAll(local.outbox);
    } catch (_) {
      storageError = 'Could not restore saved drafts on this device.';
    }
    if (_disposed) return;
    initializing = false;
    _notify();
    await sync();
  }

  Future<bool> _persist() async {
    final encoded = ChatLocalData(draft: draft, outbox: outbox).encode();
    var saved = true;
    _writes = _writes.then((_) async {
      try {
        await store.write(userId, conversationId, encoded);
        storageError = null;
      } catch (_) {
        saved = false;
        storageError =
            'Could not save your draft or pending message on this device.';
      }
    });
    await _writes;
    _notify();
    return saved;
  }

  void updateDraft(String value) {
    draft = value;
    _draftTimer?.cancel();
    _draftTimer =
        Timer(const Duration(milliseconds: 250), () => unawaited(_persist()));
  }

  void setActive(bool active) {
    _active = active;
    _poll?.cancel();
    _poll = null;
    if (active && !_disposed) {
      if (!initializing) unawaited(sync());
      _poll = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!initializing) unawaited(sync());
      });
    }
  }

  void _merge(List<ChatMessage> incoming) {
    final merged = {for (final m in _messages) m.sequence: m};
    for (final m in incoming) {
      merged[m.sequence] = m;
    }
    _messages = merged.values.toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    final confirmed = incoming
        .where((m) => m.sender.id == userId)
        .map((m) => m.clientId)
        .toSet();
    outbox.removeWhere((m) => confirmed.contains(m.clientId));
  }

  Future<void> sync() async {
    if (_disposed || _syncing || initializing) return;
    _syncing = true;
    _notify();
    try {
      var more = true;
      do {
        final page = await repository.messages(conversationId,
            after: _loaded ? _syncedThrough : null);
        if (_disposed) return;
        if (!_loaded) olderCursor = page.olderCursor;
        _merge(page.messages);
        if (page.messages.isNotEmpty) {
          _syncedThrough = max(_syncedThrough, page.messages.last.sequence);
        }
        _loaded = true;
        more = page.hasMore && page.messages.isNotEmpty;
        error = null;
        _notify();
      } while (more && _active);
      await _persist();
      if (_active && _syncedThrough > _readThrough) {
        await repository.markRead(conversationId, _syncedThrough);
        _readThrough = _syncedThrough;
      }
    } catch (failure) {
      if (!_disposed) {
        error = chatError(failure);
        _notify();
      }
    } finally {
      _syncing = false;
      _notify();
    }
  }

  Future<void> loadOlder() async {
    final cursor = olderCursor;
    if (_disposed || loadingOlder || cursor == null) return;
    loadingOlder = true;
    _notify();
    try {
      final page = await repository.messages(conversationId, before: cursor);
      if (_disposed) return;
      _merge(page.messages);
      olderCursor = page.olderCursor;
      error = null;
    } catch (failure) {
      error = chatError(failure);
    } finally {
      loadingOlder = false;
      _notify();
    }
  }

  Future<void> sendDraft() async {
    final body = draft.trim();
    if (initializing || sending || body.isEmpty || body.length > 4000) return;
    _draftTimer?.cancel();
    final item = QueuedMessage(
        clientId: newMessageId(), body: body, createdAt: DateTime.now());
    outbox.add(item);
    draft = '';
    await retry(item);
  }

  Future<void> retry(QueuedMessage item) async {
    if (sending || _disposed || !outbox.contains(item)) return;
    sending = true;
    item.sending = true;
    item.error = null;
    _notify();
    try {
      if (!await _persist()) {
        throw const MessagingException(
            'Pending message could not be saved. Retry when device storage is available.');
      }
      if (_disposed) return;
      final message =
          await repository.send(conversationId, item.clientId, item.body);
      if (_disposed) return;
      _merge([message]);
      // Do not advance the polling cursor here: other people may have sent messages in between.
      await _persist();
      error = null;
    } catch (failure) {
      item.error = chatError(failure);
    } finally {
      item.sending = false;
      sending = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _draftTimer?.cancel();
    unawaited(_persist());
    _disposed = true;
    super.dispose();
  }
}

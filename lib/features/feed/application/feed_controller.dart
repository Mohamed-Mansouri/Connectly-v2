import 'package:flutter/foundation.dart';
import '../domain/feed_models.dart';

class FeedController extends ChangeNotifier {
  FeedController(this.repository);
  final FeedRepository repository;
  List<FeedPost> _posts = [];
  List<FeedPost> get posts => List.unmodifiable(_posts);
  String scope = 'connections';
  String? nextCursor;
  String? error;
  bool loading = false;
  bool loadingMore = false;
  final Set<String> busyPosts = {};
  final Set<String> _deletedIds = {};
  int _revision = 0;
  bool _disposed = false;

  static String message(Object error) => error is FeedException
      ? error.message
      : 'Something went wrong. Please try again.';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh({String? filter}) async {
    final revision = ++_revision;
    if (filter != null && filter != scope) {
      scope = filter;
      _posts = [];
      nextCursor = null;
    }
    loading = true;
    loadingMore = false;
    error = null;
    _notify();
    try {
      final page = await repository.load(scope: scope);
      if (_disposed || revision != _revision) return;
      _posts = page.posts.where((p) => !_deletedIds.contains(p.id)).toList();
      nextCursor = page.nextCursor;
    } catch (failure) {
      if (_disposed || revision != _revision) return;
      error = message(failure);
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = nextCursor;
    if (loading || loadingMore || cursor == null) return;
    final revision = _revision;
    loadingMore = true;
    error = null;
    _notify();
    try {
      final page = await repository.load(scope: scope, cursor: cursor);
      if (_disposed || revision != _revision) return;
      final ids = _posts.map((p) => p.id).toSet();
      _posts = [
        ..._posts,
        ...page.posts
            .where((p) => !ids.contains(p.id) && !_deletedIds.contains(p.id))
      ];
      nextCursor = page.nextCursor;
    } catch (failure) {
      if (!_disposed && revision == _revision) error = message(failure);
    } finally {
      if (!_disposed && revision == _revision) {
        loadingMore = false;
        _notify();
      }
    }
  }

  void created(FeedPost post) {
    // Cancel an older refresh so it cannot erase a just-created post.
    _revision++;
    loading = false;
    loadingMore = false;
    _posts = [post, ..._posts.where((p) => p.id != post.id)];
    error = null;
    _notify();
  }

  Future<String?> react(FeedPost post, String? kind) async {
    if (!busyPosts.add(post.id)) return null;
    _notify();
    try {
      final updated = await repository.react(post.id, kind);
      if (_disposed) return null;
      _posts = _posts.map((p) => p.id == updated.id ? updated : p).toList();
      return null;
    } catch (failure) {
      return message(failure);
    } finally {
      busyPosts.remove(post.id);
      _notify();
    }
  }

  Future<String?> delete(FeedPost post) async {
    if (!busyPosts.add(post.id)) return null;
    _notify();
    try {
      await repository.delete(post.id);
      if (!_disposed) {
        _deletedIds.add(post.id);
        _posts = _posts.where((p) => p.id != post.id).toList();
      }
      return null;
    } catch (failure) {
      return message(failure);
    } finally {
      busyPosts.remove(post.id);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}

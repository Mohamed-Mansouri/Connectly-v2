import 'dart:async';
import 'package:connectly/features/feed/application/feed_controller.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'feed_fakes.dart';

void main() {
  test('a slow old filter cannot replace the latest feed', () async {
    final old = Completer<FeedPage>();
    final repository = FakeFeedRepository()
      ..onLoad = (scope, _) async => scope == 'connections'
          ? await old.future
          : FeedPage([testPost('friend')], null);
    final controller = FeedController(repository);
    final initial = controller.refresh();
    await controller.refresh(filter: 'friends');
    old.complete(FeedPage([testPost('old')], null));
    await initial;
    expect(controller.posts.single.id, 'friend');
    expect(controller.scope, 'friends');
    controller.dispose();
  });

  test('pagination deduplicates posts and preserves them on a failed refresh',
      () async {
    final repository = FakeFeedRepository()
      ..onLoad = (_, cursor) async => cursor == null
          ? FeedPage([testPost('one')], 'next')
          : FeedPage([testPost('one'), testPost('two')], null);
    final controller = FeedController(repository);
    await controller.refresh();
    await controller.loadMore();
    expect(controller.posts.map((p) => p.id), ['one', 'two']);
    repository.onLoad = (_, __) async => throw const FeedException('Offline');
    await controller.refresh();
    expect(controller.posts.length, 2);
    expect(controller.error, 'Offline');
    controller.dispose();
  });

  test('publishing survives an older refresh response', () async {
    final old = Completer<FeedPage>();
    final repository = FakeFeedRepository()..onLoad = (_, __) => old.future;
    final controller = FeedController(repository);
    final pending = controller.refresh();
    controller.created(testPost('new'));
    old.complete(const FeedPage([], null));
    await pending;
    expect(controller.posts.single.id, 'new');
    expect(controller.loading, isFalse);
    controller.dispose();
  });

  test('reactions prevent duplicates and update authoritative server counts',
      () async {
    final repository = FakeFeedRepository()
      ..pendingReaction = Completer<FeedPost>();
    final controller = FeedController(repository);
    await controller.refresh();
    final pending = controller.react(controller.posts.single, 'love');
    await controller.react(controller.posts.single, 'love');
    expect(repository.reactionCalls, 1);
    repository.pendingReaction!.complete(testPost('post-1', reaction: 'love'));
    await pending;
    expect(controller.posts.single.myReaction, 'love');
    expect(controller.posts.single.reactionCount, 1);
    expect(controller.busyPosts, isEmpty);
    controller.dispose();
  });

  test('an in-flight refresh cannot resurrect a deleted post', () async {
    final repository = FakeFeedRepository();
    final controller = FeedController(repository);
    await controller.refresh();
    final old = Completer<FeedPage>();
    repository.onLoad = (_, __) => old.future;
    final pending = controller.refresh();
    await controller.delete(controller.posts.single);
    old.complete(FeedPage([testPost('post-1')], null));
    await pending;
    expect(controller.posts, isEmpty);
    controller.dispose();
  });
}

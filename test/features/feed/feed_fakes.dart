import 'dart:async';
import 'package:connectly/features/feed/domain/feed_models.dart';

FeedPost testPost(String id, {String? reaction}) => FeedPost(
    id: id,
    authorId: 'user-1',
    authorName: 'Test Member',
    body: 'A little update $id',
    createdAt: DateTime.utc(2026, 10, 24),
    reactions: {
      'like': reaction == 'like' ? 1 : 0,
      'love': reaction == 'love' ? 1 : 0
    },
    myReaction: reaction);

class FakeFeedRepository implements FeedRepository {
  List<FeedPost> posts = [testPost('post-1')];
  Future<FeedPage> Function(String, String?)? onLoad;
  Completer<FeedPost>? pendingCreate;
  Completer<FeedPost>? pendingReaction;
  FeedException? createError;
  int createCalls = 0;
  int reactionCalls = 0;
  final actions = <String>[];
  List<FeedPerson> members = [];
  @override
  Future<FeedPage> load({required String scope, String? cursor}) async =>
      onLoad == null ? FeedPage(posts, null) : await onLoad!(scope, cursor);
  @override
  Future<FeedPost> create(String body) async {
    createCalls++;
    if (createError != null) throw createError!;
    return pendingCreate?.future ??
        Future.value(FeedPost(
            id: 'new-post',
            authorId: 'user-1',
            authorName: 'Test Member',
            body: body,
            createdAt: DateTime.now(),
            reactions: {}));
  }

  @override
  Future<void> delete(String postId) async {
    actions.add('delete:$postId');
  }

  @override
  Future<FeedPost> react(String postId, String? kind) async {
    reactionCalls++;
    return pendingReaction?.future ??
        Future.value(testPost(postId, reaction: kind));
  }

  @override
  Future<List<FeedPerson>> people(
          {String search = '', bool requests = false}) async =>
      members;
  @override
  Future<void> follow(String personId, bool following) async {
    actions.add('follow:$personId:$following');
  }

  @override
  Future<void> friendship(String personId, String action) async {
    actions.add('friend:$personId:$action');
  }
}

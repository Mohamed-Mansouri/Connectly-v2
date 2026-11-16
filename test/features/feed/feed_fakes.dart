import 'dart:async';
import 'dart:typed_data';
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
  FeedImageUpload? lastImage;
  final images = <String, Uint8List>{};
  @override
  Future<Uint8List> postImage(String postId) async =>
      images[postId] ?? (throw const FeedException('This photo was removed.'));

  final reposts = <String>[];
  @override
  Future<FeedPost> repost(String postId, String comment) async {
    reposts.add('$postId:$comment');
    final original = posts.firstWhere((p) => p.id == postId);
    return FeedPost(
        id: 'repost-${reposts.length}',
        authorId: 'user-1',
        authorName: 'Test Member',
        body: comment.trim(),
        createdAt: DateTime.now(),
        reactions: const {},
        sharedPostId: original.id,
        shared: FeedSharedPost(
            id: original.id,
            authorId: original.authorId,
            authorName: original.authorName,
            body: original.body,
            createdAt: original.createdAt));
  }

  @override
  Future<FeedPost> create(String body, {FeedImageUpload? image}) async {
    createCalls++;
    lastImage = image;
    if (createError != null) throw createError!;
    return pendingCreate?.future ??
        Future.value(FeedPost(
            id: 'new-post',
            authorId: 'user-1',
            authorName: 'Test Member',
            body: body,
            createdAt: DateTime.now(),
            reactions: {},
            imageWidth: image?.width,
            imageHeight: image?.height));
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

  List<FeedReactor> reactorList = [];
  final commentList = <FeedComment>[];
  @override
  Future<List<FeedReactor>> reactors(String postId) async => reactorList;
  @override
  Future<List<FeedComment>> comments(String postId) async =>
      commentList.where((c) => c.postId == postId).toList();
  @override
  Future<FeedComment> addComment(String postId, String body,
      {String? replyTo}) async {
    final target =
        replyTo == null ? null : commentList.firstWhere((c) => c.id == replyTo);
    final comment = FeedComment(
        parentId: target == null ? null : (target.parentId ?? target.id),
        id: 'comment-${commentList.length + 1}',
        postId: postId,
        authorId: 'user-1',
        authorName: 'Test Member',
        body: body.trim(),
        createdAt: DateTime.now());
    commentList.add(comment);
    return comment;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    commentList
        .removeWhere((c) => c.id == commentId || c.parentId == commentId);
  }

  final searches = <String>[];
  List<FeedTrend> trends = const [FeedTrend('travel', 3)];
  List<FeedSuggestion> suggestionList = const [];
  @override
  Future<List<FeedPost>> search(String query) async {
    searches.add(query);
    return posts
        .where((p) => p.body.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Future<List<FeedTrend>> trendingTags() async => trends;
  @override
  Future<List<FeedSuggestion>> suggestions(String token) async =>
      suggestionList.where((s) => s.value.startsWith(token)).toList();

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

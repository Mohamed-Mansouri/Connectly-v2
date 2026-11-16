import 'dart:typed_data';

class FeedPost {
  const FeedPost(
      {required this.id,
      required this.authorId,
      required this.authorName,
      required this.body,
      required this.createdAt,
      required this.reactions,
      this.myReaction,
      this.commentCount = 0,
      this.imageWidth,
      this.imageHeight,
      this.sharedPostId,
      this.shared,
      this.shareCount = 0});

  final String id;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final Map<String, int> reactions;
  final String? myReaction;
  final int commentCount;

  /// Size of the attached photo, or null when the post has none.
  final int? imageWidth;
  final int? imageHeight;
  bool get hasImage => imageWidth != null && imageHeight != null;

  /// Set when this post is a repost; [shared] is null if the original was
  /// deleted since.
  final String? sharedPostId;
  final FeedSharedPost? shared;
  bool get isRepost => sharedPostId != null;

  /// Number of reposts of this post.
  final int shareCount;
  int get reactionCount =>
      reactions.values.fold(0, (sum, count) => sum + count);

  FeedPost copyWith({int? commentCount}) => FeedPost(
      id: id,
      authorId: authorId,
      authorName: authorName,
      body: body,
      createdAt: createdAt,
      reactions: reactions,
      myReaction: myReaction,
      commentCount: commentCount ?? this.commentCount,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      sharedPostId: sharedPostId,
      shared: shared,
      shareCount: shareCount);

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>;
    return FeedPost(
        id: json['id'] as String,
        authorId: author['id'] as String,
        authorName: author['name'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        reactions: Map<String, int>.from(json['reactions'] as Map),
        myReaction: json['myReaction'] as String?,
        commentCount: json['commentCount'] as int? ?? 0);
  }
}

/// The original post shown inside a repost.
class FeedSharedPost {
  const FeedSharedPost(
      {required this.id,
      required this.authorId,
      required this.authorName,
      required this.body,
      required this.createdAt,
      this.imageWidth,
      this.imageHeight});
  final String id;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final int? imageWidth;
  final int? imageHeight;
  bool get hasImage => imageWidth != null && imageHeight != null;
}

/// A photo chosen in the composer, already resized to JPEG.
class FeedImageUpload {
  const FeedImageUpload(
      {required this.bytes, required this.width, required this.height});
  final Uint8List bytes;
  final int width;
  final int height;
}

class FeedComment {
  const FeedComment(
      {required this.id,
      required this.postId,
      required this.authorId,
      required this.authorName,
      required this.body,
      required this.createdAt,
      this.parentId});
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  /// The top-level comment this replies to; null for a top-level comment.
  final String? parentId;
  bool get isReply => parentId != null;
}

class FeedReactor {
  const FeedReactor(
      {required this.userId, required this.name, required this.kind});
  final String userId;
  final String name;
  final String kind;
}

/// A trending hashtag and how many visible posts use it.
class FeedTrend {
  const FeedTrend(this.tag, this.count);
  final String tag;
  final int count;
}

/// Autocomplete entry for the composer and search box.
/// [value] is inserted as typed (`#travel`, `@amal`); [label] explains it.
class FeedSuggestion {
  const FeedSuggestion(this.value, this.label);
  final String value;
  final String label;
}

class FeedPage {
  const FeedPage(this.posts, this.nextCursor);
  final List<FeedPost> posts;
  final String? nextCursor;
}

class FeedPerson {
  const FeedPerson(
      {required this.id,
      required this.name,
      required this.isFollowing,
      required this.friendship});
  final String id;
  final String name;
  final bool isFollowing;
  // none, incoming, outgoing, friends
  final String friendship;

  factory FeedPerson.fromJson(Map<String, dynamic> json) => FeedPerson(
      id: json['id'] as String,
      name: json['name'] as String,
      isFollowing: json['isFollowing'] as bool,
      friendship: json['friendship'] as String);
}

class FeedException implements Exception {
  const FeedException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
}

abstract class FeedRepository {
  /// [scope] is `all` (friends and followed people, not you), `me`,
  /// `friends` or `following`.
  Future<FeedPage> load({required String scope, String? cursor});
  Future<FeedPost> create(String body, {FeedImageUpload? image});

  /// Shares [postId] (or, for a repost, its original) to your followers and
  /// friends with an optional [comment].
  Future<FeedPost> repost(String postId, String comment);

  /// JPEG bytes of a visible post's photo.
  Future<Uint8List> postImage(String postId);
  Future<void> delete(String postId);
  Future<FeedPost> react(String postId, String? kind);
  Future<List<FeedReactor>> reactors(String postId);
  Future<List<FeedComment>> comments(String postId);

  /// Adds a comment, or a reply when [replyTo] is set. Replying to a reply
  /// attaches to the same top-level comment (one level of nesting).
  Future<FeedComment> addComment(String postId, String body, {String? replyTo});

  /// Deletes a comment and, for a top-level comment, its replies.
  Future<void> deleteComment(String commentId);

  /// Posts visible to the viewer that match `#tags`, `@handles` and words.
  Future<List<FeedPost>> search(String query);

  /// Most used hashtags in visible posts from the last 30 days.
  Future<List<FeedTrend>> trendingTags();

  /// Completions for a token that starts with `#` or `@`.
  Future<List<FeedSuggestion>> suggestions(String token);
  Future<List<FeedPerson>> people({String search = '', bool requests = false});
  Future<void> follow(String personId, bool following);
  Future<void> friendship(String personId, String action);
}

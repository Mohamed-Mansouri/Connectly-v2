class FeedPost {
  const FeedPost(
      {required this.id,
      required this.authorId,
      required this.authorName,
      required this.body,
      required this.createdAt,
      required this.reactions,
      this.myReaction,
      this.commentCount = 0});

  final String id;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final Map<String, int> reactions;
  final String? myReaction;
  final int commentCount;
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
      commentCount: commentCount ?? this.commentCount);

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

class FeedComment {
  const FeedComment(
      {required this.id,
      required this.postId,
      required this.authorId,
      required this.authorName,
      required this.body,
      required this.createdAt});
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
}

class FeedReactor {
  const FeedReactor(
      {required this.userId, required this.name, required this.kind});
  final String userId;
  final String name;
  final String kind;
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
  Future<FeedPage> load({required String scope, String? cursor});
  Future<FeedPost> create(String body);
  Future<void> delete(String postId);
  Future<FeedPost> react(String postId, String? kind);
  Future<List<FeedReactor>> reactors(String postId);
  Future<List<FeedComment>> comments(String postId);
  Future<FeedComment> addComment(String postId, String body);
  Future<void> deleteComment(String commentId);
  Future<List<FeedPerson>> people({String search = '', bool requests = false});
  Future<void> follow(String personId, bool following);
  Future<void> friendship(String personId, String action);
}

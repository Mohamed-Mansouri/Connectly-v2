class FeedPost {
  const FeedPost(
      {required this.id,
      required this.authorId,
      required this.authorName,
      required this.body,
      required this.createdAt,
      required this.reactions,
      this.myReaction});

  final String id;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final Map<String, int> reactions;
  final String? myReaction;
  int get reactionCount =>
      reactions.values.fold(0, (sum, count) => sum + count);

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>;
    return FeedPost(
        id: json['id'] as String,
        authorId: author['id'] as String,
        authorName: author['name'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        reactions: Map<String, int>.from(json['reactions'] as Map),
        myReaction: json['myReaction'] as String?);
  }
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
  Future<List<FeedPerson>> people({String search = '', bool requests = false});
  Future<void> follow(String personId, bool following);
  Future<void> friendship(String personId, String action);
}

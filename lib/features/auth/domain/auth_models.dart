class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final DateTime createdAt;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;
}

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;
}

abstract class AuthRepository {
  Future<AuthSession> signIn(String email, String password);
  Future<AuthSession> signUp(String name, String email, String password);
  Future<AuthUser> currentUser(String token);
  Future<void> signOut(String token);
}

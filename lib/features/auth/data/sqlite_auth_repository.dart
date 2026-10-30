import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';
import '../../../shared/data/local_database.dart';
import '../domain/auth_models.dart';
import 'local_passwords.dart';

class SqliteAuthRepository implements AuthRepository {
  SqliteAuthRepository(this.database, {LocalPasswords? passwords})
      : _passwords = passwords ?? LocalPasswords();
  final LocalDatabase database;
  final LocalPasswords _passwords;

  String _email(String value) {
    final email = value.trim().toLowerCase();
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const AuthException('Enter a valid email address.');
    }
    return email;
  }

  AuthUser _user(Map<String, Object?> row) => AuthUser(
      id: row['id'] as String,
      name: row['name'] as String,
      email: row['email'] as String,
      createdAt: DateTime.parse(row['created_at'] as String));

  Future<String> _hashToken(String token) async =>
      base64Encode((await Sha256().hash(utf8.encode(token))).bytes);
  Future<AuthSession> _newSession(DatabaseExecutor db, AuthUser user) async {
    final random = Random.secure();
    final token = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final now = DateTime.now().toUtc();
    await db.insert('auth_sessions', {
      'token_hash': await _hashToken(token),
      'user_id': user.id,
      'created_at': localTimestamp(now),
      'expires_at': localTimestamp(now.add(const Duration(days: 7)))
    });
    return AuthSession(token: token, user: user);
  }

  @override
  Future<AuthSession> signUp(String name, String email, String password) async {
    final normalized = _email(email);
    final displayName = name.trim();
    if (displayName.length < 2 || displayName.length > 80) {
      throw const AuthException('Name must contain 2–80 characters.');
    }
    if (password.length < 8 || password.length > 128) {
      throw const AuthException('Password must contain 8–128 characters.');
    }
    final id = localId();
    final created = DateTime.now().toUtc();
    final hash = await _passwords.hash(password);
    try {
      return await database.db.transaction((txn) async {
        await txn.insert('users', {
          'id': id,
          'name': displayName,
          'email': normalized,
          'password_hash': hash,
          'created_at': localTimestamp(created)
        });
        return _newSession(
            txn,
            AuthUser(
                id: id,
                name: displayName,
                email: normalized,
                createdAt: created));
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const AuthException(
            'An account on this phone already uses this email address.');
      }
      rethrow;
    }
  }

  @override
  Future<AuthSession> signIn(String email, String password) async {
    final normalized = _email(email);
    final rows = await database.db
        .query('users', where: 'email = ?', whereArgs: [normalized], limit: 1);
    if (password.isEmpty ||
        password.length > 128 ||
        rows.isEmpty ||
        !await _passwords.verify(
            password, rows.first['password_hash'] as String)) {
      throw const AuthException('Email or password is incorrect.');
    }
    return _newSession(database.db, _user(rows.first));
  }

  @override
  Future<AuthUser> currentUser(String token) async {
    final rows = await database.db.rawQuery(
        '''SELECT u.id, u.name, u.email, u.created_at FROM users u
      JOIN auth_sessions s ON s.user_id = u.id WHERE s.token_hash = ? AND s.expires_at > ?''',
        [await _hashToken(token), localTimestamp()]);
    if (rows.isEmpty) {
      throw const AuthException('Please sign in again.', statusCode: 401);
    }
    return _user(rows.first);
  }

  @override
  Future<void> signOut(String token) async {
    await database.db.delete('auth_sessions',
        where: 'token_hash = ?', whereArgs: [await _hashToken(token)]);
  }
}

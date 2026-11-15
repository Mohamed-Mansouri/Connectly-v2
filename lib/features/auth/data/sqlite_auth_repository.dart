import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';
import '../../../shared/data/local_database.dart';
import '../domain/auth_models.dart';
import 'biometric_access.dart';
import 'local_passwords.dart';

class SqliteAuthRepository
    implements
        AuthRepository,
        BiometricSessionRepository,
        PasswordResetRepository {
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
  Future<AuthSession> _newSession(DatabaseExecutor db, AuthUser user,
      {Duration lifetime = const Duration(days: 7)}) async {
    final random = Random.secure();
    final token = base64UrlEncode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final now = DateTime.now().toUtc();
    await db.insert('auth_sessions', {
      'token_hash': await _hashToken(token),
      'user_id': user.id,
      'created_at': localTimestamp(now),
      'expires_at': localTimestamp(now.add(lifetime))
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
  Future<String> createBiometricToken(String sessionToken) async {
    final user = await currentUser(sessionToken);
    return (await _newSession(database.db, user,
            lifetime: const Duration(days: 90)))
        .token;
  }

  @override
  Future<AuthSession> signInWithBiometricToken(String biometricToken) async {
    final user = await currentUser(biometricToken);
    return _newSession(database.db, user);
  }

  @override
  Future<void> revokeBiometricToken(String biometricToken) =>
      signOut(biometricToken);

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

  static const resetLifetime = Duration(minutes: 15);
  static const resetCooldown = Duration(seconds: 60);
  static const resetMaxAttempts = 5;

  Future<Map<String, Object?>?> _userByEmail(
      DatabaseExecutor db, String email) async {
    final rows = await db.query('users',
        where: 'email = ?', whereArgs: [_email(email)], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<({String code, String email})> createPasswordResetCode(
      String email) async {
    final user = await _userByEmail(database.db, email);
    if (user == null) {
      throw const AuthException('No account on this phone uses this email.');
    }
    final userId = user['id'] as String;
    final now = DateTime.now().toUtc();
    final previous = await database.db.query('password_resets',
        columns: ['created_at'], where: 'user_id = ?', whereArgs: [userId]);
    if (previous.isNotEmpty &&
        now.difference(
                DateTime.parse(previous.single['created_at'] as String)) <
            resetCooldown) {
      throw const AuthException(
          'A code was just sent. Wait a minute before requesting another.');
    }
    final code =
        (Random.secure().nextInt(900000) + 100000).toString(); // 6 digits
    await database.db.insert(
        'password_resets',
        {
          'user_id': userId,
          'code_hash': await _hashToken('$userId:$code'),
          'attempts': 0,
          'created_at': localTimestamp(now),
          'expires_at': localTimestamp(now.add(resetLifetime)),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    return (code: code, email: user['email'] as String);
  }

  @override
  Future<void> cancelPasswordReset(String email) async {
    final user = await _userByEmail(database.db, email);
    if (user == null) return;
    await database.db.delete('password_resets',
        where: 'user_id = ?', whereArgs: [user['id']]);
  }

  @override
  Future<void> resetPassword(
      String email, String code, String newPassword) async {
    if (newPassword.length < 8 || newPassword.length > 128) {
      throw const AuthException('Password must contain 8–128 characters.');
    }
    const invalid = AuthException('That code is incorrect or has expired.');
    final user = await _userByEmail(database.db, email);
    if (user == null) throw invalid;
    final userId = user['id'] as String;
    final rows = await database.db
        .query('password_resets', where: 'user_id = ?', whereArgs: [userId]);
    if (rows.isEmpty) throw invalid;
    final reset = rows.single;
    final expired = DateTime.parse(reset['expires_at'] as String)
        .isBefore(DateTime.now().toUtc());
    if (expired || (reset['attempts'] as int) >= resetMaxAttempts) {
      await database.db
          .delete('password_resets', where: 'user_id = ?', whereArgs: [userId]);
      throw const AuthException('That code has expired. Request a new one.');
    }
    if (await _hashToken('$userId:${code.trim()}') != reset['code_hash']) {
      await database.db.rawUpdate(
          'UPDATE password_resets SET attempts = attempts + 1 WHERE user_id = ?',
          [userId]);
      throw invalid;
    }
    final hash = await _passwords.hash(newPassword);
    await database.db.transaction((txn) async {
      await txn.update('users', {'password_hash': hash},
          where: 'id = ?', whereArgs: [userId]);
      // Sign out everywhere, including saved fingerprint tokens.
      await txn
          .delete('auth_sessions', where: 'user_id = ?', whereArgs: [userId]);
      await txn
          .delete('password_resets', where: 'user_id = ?', whereArgs: [userId]);
    });
  }
}

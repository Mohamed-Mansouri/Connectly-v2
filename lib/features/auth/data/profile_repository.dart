import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import '../../../shared/data/local_database.dart';
import '../../discovery/data/people_repository.dart';
import '../domain/auth_models.dart';

class LocalProfile {
  const LocalProfile({
    required this.name,
    required this.email,
    required this.bio,
    required this.photo,
    required this.location,
  });

  final String name;
  final String email;
  final String bio;
  final Uint8List? photo;
  final PeopleLocation? location;
}

abstract class ProfileRepository {
  Future<LocalProfile> load();
  Future<LocalProfile> saveDetails({
    required String name,
    required String email,
    required String bio,
  });
  Future<LocalProfile> savePhoto(Uint8List? bytes);
  Future<LocalProfile> saveLocation(PeopleLocation location);
  Future<LocalProfile> removeLocation();
}

class SqliteProfileRepository implements ProfileRepository {
  SqliteProfileRepository(this.database, this.userId);

  final LocalDatabase database;
  final String userId;

  @override
  Future<LocalProfile> load() async {
    final rows = await database.db.rawQuery('''
      SELECT u.name, u.email, p.bio, p.photo,
             l.latitude, l.longitude, l.visible
      FROM users u
      LEFT JOIN user_profiles p ON p.user_id = u.id
      LEFT JOIN user_locations l ON l.user_id = u.id
      WHERE u.id = ? LIMIT 1
    ''', [userId]);
    if (rows.isEmpty) {
      throw const AuthException('Please sign in again.', statusCode: 401);
    }
    final row = rows.single;
    return LocalProfile(
      name: row['name'] as String,
      email: row['email'] as String,
      bio: row['bio'] as String? ?? '',
      photo: row['photo'] as Uint8List?,
      location: row['latitude'] == null
          ? null
          : PeopleLocation(
              (row['latitude'] as num).toDouble(),
              (row['longitude'] as num).toDouble(),
              visible: row['visible'] == 1,
            ),
    );
  }

  @override
  Future<LocalProfile> saveDetails({
    required String name,
    required String email,
    required String bio,
  }) async {
    final displayName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedBio = bio.trim();
    if (displayName.length < 2 || displayName.length > 80) {
      throw const AuthException('Name must contain 2–80 characters.');
    }
    if (normalizedEmail.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      throw const AuthException('Enter a valid email address.');
    }
    if (trimmedBio.length > 160) {
      throw const AuthException('Bio must be 160 characters or fewer.');
    }
    try {
      await database.db.transaction((txn) async {
        final changed = await txn.update(
            'users', {'name': displayName, 'email': normalizedEmail},
            where: 'id = ?', whereArgs: [userId]);
        if (changed == 0) {
          throw const AuthException('Please sign in again.', statusCode: 401);
        }
        await txn.rawInsert(
            '''INSERT INTO user_profiles (user_id, bio, updated_at)
          VALUES (?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET
          bio = excluded.bio, updated_at = excluded.updated_at''',
            [userId, trimmedBio, localTimestamp()]);
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const AuthException(
            'An account on this phone already uses this email address.');
      }
      rethrow;
    }
    return load();
  }

  @override
  Future<LocalProfile> savePhoto(Uint8List? bytes) async {
    if (bytes != null && (bytes.isEmpty || bytes.length > 2000000)) {
      throw const AuthException('Choose a photo smaller than 2 MB.');
    }
    await database.db.rawInsert('''INSERT INTO user_profiles
      (user_id, photo, updated_at) VALUES (?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET
      photo = excluded.photo, updated_at = excluded.updated_at''',
        [userId, bytes, localTimestamp()]);
    return load();
  }

  @override
  Future<LocalProfile> saveLocation(PeopleLocation location) async {
    await SqlitePeopleRepository(database, userId).saveLocation(location);
    return load();
  }

  @override
  Future<LocalProfile> removeLocation() async {
    await SqlitePeopleRepository(database, userId).removeLocation();
    return load();
  }
}

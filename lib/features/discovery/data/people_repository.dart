import 'dart:math';
import '../../../shared/data/local_database.dart';
import '../../feed/data/sqlite_feed_repository.dart';
import '../../feed/domain/feed_models.dart';

class PeopleLocation {
  const PeopleLocation(this.latitude, this.longitude, {this.visible = true});
  final double latitude;
  final double longitude;
  final bool visible;

  double distanceKm(PeopleLocation other) {
    double radians(double value) => value * pi / 180;
    final dLat = radians(other.latitude - latitude);
    final dLon = radians(other.longitude - longitude);
    final a = pow(sin(dLat / 2), 2) +
        cos(radians(latitude)) *
            cos(radians(other.latitude)) *
            pow(sin(dLon / 2), 2);
    return 6371 * 2 * asin(sqrt(a.clamp(0, 1)));
  }
}

class LocatedPerson {
  const LocatedPerson(this.person, this.location, this.distanceKm);
  final FeedPerson person;
  final PeopleLocation? location;
  final double? distanceKm;
}

class PeopleSnapshot {
  const PeopleSnapshot(this.ownLocation, this.people);
  final PeopleLocation? ownLocation;
  final List<LocatedPerson> people;
}

abstract class PeopleRepository {
  FeedRepository get connections;
  Future<PeopleSnapshot> load(
      {String search = '', String filter = 'all', double? radiusKm});
  Future<void> saveLocation(PeopleLocation location);
  Future<void> removeLocation();
}

class SqlitePeopleRepository implements PeopleRepository {
  SqlitePeopleRepository(this.database, this.userId);
  final LocalDatabase database;
  final String userId;
  @override
  FeedRepository get connections => SqliteFeedRepository(database, userId);

  PeopleLocation _location(Map<String, Object?> row) => PeopleLocation(
      (row['latitude'] as num).toDouble(), (row['longitude'] as num).toDouble(),
      visible: row['visible'] == 1);

  @override
  Future<PeopleSnapshot> load(
      {String search = '', String filter = 'all', double? radiusKm}) async {
    if (search.length > 80 ||
        !const ['all', 'friends', 'requests', 'following'].contains(filter)) {
      throw const FeedException(
          'Choose a valid people filter or shorter search.');
    }
    if (radiusKm != null && (!radiusKm.isFinite || radiusKm <= 0)) {
      throw const FeedException('Choose a positive distance.');
    }
    // One snapshot for the current pin, connections and other visible pins.
    return database.db.transaction((txn) async {
      final ownRows = await txn
          .query('user_locations', where: 'user_id = ?', whereArgs: [userId]);
      final own = ownRows.isEmpty ? null : _location(ownRows.first);
      final rows = await txn.rawQuery(
          '''SELECT u.id, u.name, l.latitude, l.longitude, l.visible,
        EXISTS(SELECT 1 FROM follows x WHERE x.follower_id = ? AND x.followed_id = u.id) AS following,
        CASE WHEN f.status = 'accepted' THEN 'friends' WHEN f.requested_by = ? THEN 'outgoing'
          WHEN f.status = 'pending' THEN 'incoming' ELSE 'none' END AS friendship
        FROM users u LEFT JOIN user_locations l ON l.user_id = u.id AND l.visible = 1
        LEFT JOIN friendships f ON ((f.user_low_id = ? AND f.user_high_id = u.id)
          OR (f.user_high_id = ? AND f.user_low_id = u.id))
        WHERE u.id <> ? AND instr(lower(u.name), lower(?)) > 0
        ORDER BY u.name COLLATE NOCASE, u.id''',
          [userId, userId, userId, userId, userId, search.trim()]);
      final people = <LocatedPerson>[];
      for (final row in rows) {
        final person = FeedPerson(
            id: row['id'] as String,
            name: row['name'] as String,
            isFollowing: row['following'] == 1,
            friendship: row['friendship'] as String);
        if (filter == 'friends' && person.friendship != 'friends') continue;
        if (filter == 'requests' &&
            !['incoming', 'outgoing'].contains(person.friendship)) {
          continue;
        }
        if (filter == 'following' && !person.isFollowing) continue;
        final location = row['latitude'] == null ? null : _location(row);
        final distance = location == null ? null : own?.distanceKm(location);
        if (radiusKm != null && (distance == null || distance > radiusKm)) {
          continue;
        }
        people.add(LocatedPerson(person, location, distance));
      }
      if (radiusKm != null) {
        people.sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
      }
      return PeopleSnapshot(own, people);
    });
  }

  @override
  Future<void> saveLocation(PeopleLocation location) async {
    if (!location.latitude.isFinite ||
        !location.longitude.isFinite ||
        location.latitude.abs() > 90 ||
        location.longitude.abs() > 180) {
      throw const FeedException('Choose a valid map location.');
    }
    await database.db.rawInsert(
        '''INSERT INTO user_locations (user_id, latitude, longitude, visible, updated_at)
      VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET latitude = excluded.latitude,
      longitude = excluded.longitude, visible = excluded.visible, updated_at = excluded.updated_at''',
        [
          userId,
          location.latitude,
          location.longitude,
          location.visible ? 1 : 0,
          localTimestamp()
        ]);
  }

  @override
  Future<void> removeLocation() => database.db.delete('user_locations',
      where: 'user_id = ?', whereArgs: [userId]).then((_) {});
}

import 'package:connectly/features/discovery/data/people_repository.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';

class FakePeopleRepository implements PeopleRepository {
  FakePeopleRepository(this.connections);
  @override
  final FeedRepository connections;
  PeopleLocation? own;
  Map<String, PeopleLocation> locations = {};
  final searches = <String>[];
  final radii = <double?>[];
  @override
  Future<PeopleSnapshot> load(
      {String search = '', String filter = 'all', double? radiusKm}) async {
    searches.add(search);
    radii.add(radiusKm);
    var people = await connections.people(
        search: search, requests: filter == 'requests');
    people = people
        .where((p) => p.name.toLowerCase().contains(search.toLowerCase()))
        .where((p) => switch (filter) {
              'friends' => p.friendship == 'friends',
              'following' => p.isFollowing,
              _ => true,
            })
        .toList();
    final entries = people
        .map((p) {
          final saved = locations[p.id];
          final shared = saved?.visible == true ? saved : null;
          return LocatedPerson(p, shared,
              own == null || shared == null ? null : own!.distanceKm(shared));
        })
        .where((p) =>
            radiusKm == null ||
            (p.distanceKm != null && p.distanceKm! <= radiusKm))
        .toList();
    if (radiusKm != null) {
      entries.sort((a, b) => a.distanceKm!.compareTo(b.distanceKm!));
    }
    return PeopleSnapshot(own, entries);
  }

  @override
  Future<void> saveLocation(PeopleLocation location) async {
    own = location;
  }

  @override
  Future<void> removeLocation() async {
    own = null;
  }
}

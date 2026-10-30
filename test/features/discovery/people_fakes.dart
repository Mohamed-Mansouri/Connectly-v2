import 'package:connectly/features/discovery/data/people_repository.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';

class FakePeopleRepository implements PeopleRepository {
  FakePeopleRepository(this.connections);
  @override
  final FeedRepository connections;
  PeopleLocation? own;
  Map<String, PeopleLocation> locations = {};
  final searches = <String>[];
  @override
  Future<PeopleSnapshot> load(
      {String search = '', String filter = 'all', double? radiusKm}) async {
    searches.add(search);
    var people = await connections.people(
        search: search, requests: filter == 'requests');
    people = people
        .where((p) => p.name.toLowerCase().contains(search.toLowerCase()))
        .toList();
    return PeopleSnapshot(
        own,
        people
            .map((p) => LocatedPerson(
                p,
                locations[p.id],
                own == null || locations[p.id] == null
                    ? null
                    : own!.distanceKm(locations[p.id]!)))
            .toList());
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

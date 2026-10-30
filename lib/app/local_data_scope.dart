import 'package:flutter/widgets.dart';
import '../shared/data/local_database.dart';
import '../features/discovery/data/people_repository.dart';
import '../features/feed/data/sqlite_feed_repository.dart';
import '../features/feed/domain/feed_models.dart';
import '../features/messaging/data/sqlite_messaging_repository.dart';
import '../features/messaging/domain/messaging_models.dart';

class LocalDataScope extends InheritedWidget {
  const LocalDataScope(
      {required this.database, required super.child, super.key});
  final LocalDatabase database;
  static LocalDataScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocalDataScope>();
    assert(scope != null, 'LocalDataScope must wrap the app.');
    return scope!;
  }

  FeedRepository feedFor(String userId) =>
      SqliteFeedRepository(database, userId);
  PeopleRepository peopleFor(String userId) =>
      SqlitePeopleRepository(database, userId);
  MessagingRepository messagingFor(String userId) =>
      SqliteMessagingRepository(database, userId);
  @override
  bool updateShouldNotify(LocalDataScope oldWidget) =>
      database != oldWidget.database;
}

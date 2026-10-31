import 'dart:io';
import 'dart:convert';
import 'package:connectly/app/connectly_theme.dart';
import 'package:connectly/features/discovery/data/people_repository.dart';
import 'package:connectly/features/discovery/presentation/location_sheet.dart';
import 'package:connectly/features/discovery/presentation/people_screen.dart';
import 'package:connectly/features/discovery/presentation/ariana_map.dart';
import 'package:connectly/features/feed/domain/feed_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import '../feed/feed_fakes.dart';
import 'people_fakes.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Map must work offline');
}

Future<void> waitForMap(WidgetTester tester) async {
  for (var i = 0; i < 50 && find.byType(FlutterMap).evaluate().isEmpty; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(find.byType(FlutterMap), findsOneWidget);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Ariana asset and pin boundaries match the installed coverage',
      () async {
    final json =
        jsonDecode(await rootBundle.loadString('assets/maps/ariana.json'))
            as Map<String, dynamic>;
    expect(json['bounds'], [
      arianaBounds.south,
      arianaBounds.west,
      arianaBounds.north,
      arianaBounds.east
    ]);
    expect((json['features'] as List).length, greaterThan(1000));
    expect(
        inAriana(PeopleLocation(arianaCenter.latitude, arianaCenter.longitude)),
        isTrue);
    expect(inAriana(const PeopleLocation(36.85, 10.16)), isTrue);
    expect(inAriana(const PeopleLocation(36.89, 10.20)), isTrue);
    expect(inAriana(const PeopleLocation(36.8065, 10.1815)), isFalse);
  });
  testWidgets('offline map selects a real account and exposes friend actions',
      (tester) async {
    final connections = FakeFeedRepository()
      ..members = [
        const FeedPerson(
            id: 'bob', name: 'Bob', isFollowing: false, friendship: 'none')
      ];
    final repository = FakePeopleRepository(connections)
      ..own = const PeopleLocation(36.8625, 10.19556)
      ..locations = {'bob': const PeopleLocation(36.864, 10.20)};
    await HttpOverrides.runWithHttpOverrides(() async {
      await tester.pumpWidget(MaterialApp(
          theme: ConnectlyTheme.dark,
          home: PeopleScreen(repository: repository)));
      await waitForMap(tester);
      expect(repository.radii.last, 1);
      expect(
          tester.widget<ArianaMap>(find.byType(ArianaMap)).onPlacePin, isNull);
      await tester.ensureVisible(find.byType(ArianaMap));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pin_bob')));
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      await tester.ensureVisible(find.text('Add friend'));
      await tester.tap(find.text('Add friend'));
      await tester.pumpAndSettle();
      expect(connections.actions, ['friend:bob:request']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, _NoNetwork());
  });

  testWidgets('debounced search changes the displayed accounts',
      (tester) async {
    final connections = FakeFeedRepository()
      ..members = [
        const FeedPerson(
            id: 'bob', name: 'Bob', isFollowing: false, friendship: 'none'),
        const FeedPerson(
            id: 'alice', name: 'Alice', isFollowing: false, friendship: 'none')
      ];
    final repository = FakePeopleRepository(connections);
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        home: PeopleScreen(repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bob');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('person_bob')), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(repository.searches.last, 'Bob');
  });

  testWidgets('map starts with only shared people inside the default 1 km',
      (tester) async {
    final connections = FakeFeedRepository()
      ..members = [
        const FeedPerson(
            id: 'near', name: 'Near', isFollowing: false, friendship: 'none'),
        const FeedPerson(
            id: 'far', name: 'Far', isFollowing: false, friendship: 'none'),
        const FeedPerson(
            id: 'hidden',
            name: 'Hidden',
            isFollowing: false,
            friendship: 'none')
      ];
    final repository = FakePeopleRepository(connections)
      ..own = const PeopleLocation(36.8625, 10.19556)
      ..locations = {
        'near': const PeopleLocation(36.864, 10.196),
        'far': const PeopleLocation(36.88, 10.196),
        'hidden': const PeopleLocation(36.863, 10.196, visible: false),
      };
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        home: PeopleScreen(repository: repository)));
    await waitForMap(tester);
    expect(repository.radii.last, 1);
    expect(find.byKey(const ValueKey('pin_near')), findsOneWidget);
    expect(find.byKey(const ValueKey('pin_far')), findsNothing);
    expect(find.byKey(const ValueKey('pin_hidden')), findsNothing);
    expect(tester.widget<ArianaMap>(find.byType(ArianaMap)).onPlacePin, isNull);
  });

  testWidgets('without own location, shared pins are not called nearby',
      (tester) async {
    final connections = FakeFeedRepository()
      ..members = [
        const FeedPerson(
            id: 'bob', name: 'Bob', isFollowing: false, friendship: 'none')
      ];
    final repository = FakePeopleRepository(connections)
      ..locations = {'bob': const PeopleLocation(36.864, 10.196)};
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        home: PeopleScreen(repository: repository)));
    await waitForMap(tester);
    expect(repository.radii.last, isNull);
    expect(find.byKey(const ValueKey('pin_bob')), findsOneWidget);
    expect(find.textContaining('Set your location to see who is nearby'),
        findsWidgets);
  });

  testWidgets(
      'location denial permits manual pin placement and saving hidden pin',
      (tester) async {
    LocationEdit? result;
    await tester.pumpWidget(MaterialApp(
        theme: ConnectlyTheme.dark,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showModalBottomSheet<LocationEdit>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => LocationSheet(
                              locate: () async => throw const LocationProblem(
                                  'Permission denied. Tap the map.')));
                    },
                    child: const Text('Edit'))))));
    await tester.tap(find.text('Edit'));
    await tester.pump(const Duration(milliseconds: 350));
    await waitForMap(tester);
    await tester.ensureVisible(find.text('Use my location'));
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(find.text('Permission denied. Tap the map.'), findsOneWidget);
    final map = tester.widget<ArianaMap>(find.byType(ArianaMap));
    map.onPlacePin!(const PeopleLocation(36.865, 10.19));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save pin'));
    await tester.tap(find.text('Save pin'));
    await tester.pumpAndSettle();
    expect(result!.location!.latitude, 36.865);
    expect(result!.location!.visible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest People screen requires sign in', (tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: ConnectlyTheme.dark, home: const PeopleScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Build your circle'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}

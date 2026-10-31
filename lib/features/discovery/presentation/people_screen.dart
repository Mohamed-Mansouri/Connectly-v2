import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../../../app/local_data_scope.dart';
import '../../auth/presentation/auth_scope.dart';
import '../../feed/application/feed_controller.dart';
import '../../feed/presentation/feed_widgets.dart';
import '../data/people_repository.dart';
import 'location_sheet.dart';
import 'person_card.dart';
import 'ariana_map.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({this.repository, super.key});
  final PeopleRepository? repository;
  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  PeopleRepository? _repository;
  String? _userId;
  final _search = TextEditingController();
  final Set<String> _busy = {};
  PeopleSnapshot? _snapshot;
  String _filter = 'all';
  bool _map = true;
  double? _radius;
  bool _radiusInitialized = false;
  String? _selectedId;
  String? _error;
  bool _loading = false;
  bool _saving = false;
  bool _active = false;
  int _revision = 0;
  Timer? _debounce;
  final _selectedCard = GlobalKey();

  void _selectPerson(String id) {
    setState(() => _selectedId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cardContext = _selectedCard.currentContext;
      if (mounted && cardContext != null) {
        Scrollable.ensureVisible(cardContext,
            duration: const Duration(milliseconds: 200), alignment: 1);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = AuthScope.maybeOf(context)?.user?.id;
    if (_userId != userId ||
        (_repository == null && widget.repository != null)) {
      _revision++;
      _debounce?.cancel();
      _userId = userId;
      _repository = widget.repository ??
          (userId == null
              ? null
              : LocalDataScope.of(context).peopleFor(userId));
      _snapshot = null;
      _search.clear();
      _filter = 'all';
      _map = true;
      _radius = null;
      _radiusInitialized = false;
      _selectedId = null;
      _busy.clear();
      _saving = false;
      _error = null;
      _active = false;
    }
    final active = TickerMode.valuesOf(context).enabled && _repository != null;
    if (active && !_active) unawaited(_load());
    _active = active;
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var result = await repository.load(
          search: _search.text, filter: _filter, radiusKm: _radius);
      if (!mounted || revision != _revision) return;
      if (!_radiusInitialized && result.ownLocation != null) {
        _radius = 1;
        _radiusInitialized = true;
        result = await repository.load(
            search: _search.text, filter: _filter, radiusKm: _radius);
        if (!mounted || revision != _revision) return;
      }
      setState(() {
        _snapshot = result;
        if (!result.people.any((p) => p.person.id == _selectedId)) {
          _selectedId = null;
        }
      });
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = FeedController.message(error));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  void _queryChanged() {
    _debounce?.cancel();
    // Invalidate the previous results immediately while the next search waits.
    _revision++;
    setState(() {
      _selectedId = null;
      _loading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _act(LocatedPerson entry, Future<void> Function() action) async {
    final repository = _repository;
    if (repository == null || !_busy.add(entry.person.id)) return;
    setState(() {});
    try {
      await action();
      if (mounted && identical(repository, _repository)) await _load();
    } catch (error) {
      if (mounted && identical(repository, _repository)) {
        _notice(FeedController.message(error));
      }
    } finally {
      if (mounted && identical(repository, _repository)) {
        setState(() => _busy.remove(entry.person.id));
      }
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _editLocation() async {
    final repository = _repository;
    if (repository == null || _saving) return;
    final edit = await showModalBottomSheet<LocationEdit>(
        context: context,
        isScrollControlled: true,
        backgroundColor: ConnectlyTheme.navy,
        showDragHandle: true,
        builder: (_) => LocationSheet(initial: _snapshot?.ownLocation));
    if (edit == null || !mounted || !identical(repository, _repository)) return;
    setState(() => _saving = true);
    try {
      if (edit.location == null) {
        await repository.removeLocation();
        if (mounted && identical(repository, _repository)) {
          _radius = null;
          _radiusInitialized = false;
        }
      } else {
        await repository.saveLocation(edit.location!);
      }
      if (mounted && identical(repository, _repository)) await _load();
    } catch (error) {
      if (mounted && identical(repository, _repository)) {
        _notice(FeedController.message(error));
      }
    } finally {
      if (mounted && identical(repository, _repository)) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _card(LocatedPerson entry) => PersonCard(
      key: ValueKey('person_${entry.person.id}'),
      entry: entry,
      busy: _busy.contains(entry.person.id),
      onFollow: () => _act(
          entry,
          () => _repository!.connections
              .follow(entry.person.id, !entry.person.isFollowing)),
      onFriend: (action) => _act(entry,
          () => _repository!.connections.friendship(entry.person.id, action)));

  @override
  void dispose() {
    _revision++;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final own = _snapshot?.ownLocation;
    final people = _snapshot?.people ?? const <LocatedPerson>[];
    final pins = people
        .where((p) => p.location != null && inAriana(p.location!))
        .toList();
    final selected =
        people.where((p) => p.person.id == _selectedId).firstOrNull;
    return Scaffold(
        appBar: AppBar(
            title: const Text('People',
                style: TextStyle(
                    fontFamily: 'Urbanist', fontWeight: FontWeight.w700))),
        body: SafeArea(
            top: false,
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _repository == null
                  ? const SingleChildScrollView(
                      child: FeedNotice(
                          icon: Icons.people_outline,
                          title: 'Build your circle',
                          message:
                              'Sign in to find local accounts, follow people, and send friend requests.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const Text('Find your people',
                                style: TextStyle(
                                    fontSize: 29, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            const Text(
                                'Explore people sharing a location around Ariana.',
                                style: TextStyle(color: feedMuted)),
                            const SizedBox(height: 6),
                            const Text(
                                'Accounts on this phone only. Location pins are saved, not live.',
                                style:
                                    TextStyle(color: feedMuted, fontSize: 12)),
                            const SizedBox(height: 18),
                            TextField(
                                controller: _search,
                                maxLength: 80,
                                decoration: const InputDecoration(
                                    hintText: 'Search people by name',
                                    prefixIcon: Icon(Icons.search),
                                    counterText: '',
                                    border: OutlineInputBorder()),
                                onChanged: (_) => _queryChanged()),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              for (final filter in const {
                                'all': 'Discover',
                                'friends': 'Friends',
                                'requests': 'Friend requests',
                                'following': 'Following'
                              }.entries)
                                ChoiceChip(
                                    label: Text(filter.value),
                                    selected: _filter == filter.key,
                                    onSelected: (_) {
                                      _debounce?.cancel();
                                      setState(() => _filter = filter.key);
                                      _load();
                                    }),
                            ]),
                            const SizedBox(height: 16),
                            Row(children: [
                              Expanded(
                                  child: SegmentedButton<bool>(
                                      segments: const [
                                    ButtonSegment(
                                        value: false,
                                        icon: Icon(Icons.list),
                                        label: Text('List')),
                                    ButtonSegment(
                                        value: true,
                                        icon: Icon(Icons.map_outlined),
                                        label: Text('Map'))
                                  ],
                                      selected: {
                                    _map
                                  },
                                      onSelectionChanged: (selection) =>
                                          setState(
                                              () => _map = selection.first))),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                  tooltip: 'Refresh people',
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh)),
                            ]),
                            const SizedBox(height: 12),
                            Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                      key: const Key('edit_people_location'),
                                      onPressed: _saving || _loading
                                          ? null
                                          : _editLocation,
                                      icon: const Icon(
                                          Icons.edit_location_alt_outlined),
                                      label: Text(_saving
                                          ? 'Saving…'
                                          : own == null
                                              ? 'Set my location'
                                              : 'Edit my location')),
                                  if (own != null)
                                    Text(
                                        own.visible
                                            ? 'Your pin is shared'
                                            : 'Your pin is hidden',
                                        style: const TextStyle(
                                            color: feedMuted, fontSize: 12)),
                                ]),
                            if (own != null && !inAriana(own))
                              const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Text(
                                      'Your saved pin is outside Ariana. Edit it to place a pin on this map.',
                                      style: TextStyle(color: feedMuted))),
                            if (own != null)
                              Wrap(spacing: 6, runSpacing: 4, children: [
                                for (final radius in const <double?>[
                                  null,
                                  1,
                                  5,
                                  10,
                                  25
                                ])
                                  ChoiceChip(
                                      label: Text(radius == null
                                          ? 'Any distance'
                                          : '${radius.toInt()} km'),
                                      selected: _radius == radius,
                                      onSelected: (_) {
                                        _debounce?.cancel();
                                        setState(() {
                                          _radius = radius;
                                          _radiusInitialized = true;
                                        });
                                        _load();
                                      }),
                              ])
                            else if (_map)
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                      'Set your location to see who is nearby. Until then, the map shows all shared pins.',
                                      style: TextStyle(color: feedMuted))),
                            const SizedBox(height: 12),
                            if (_loading) const LinearProgressIndicator(),
                            if (_error != null)
                              FeedNotice(
                                  icon: Icons.error_outline,
                                  title: 'Could not load people',
                                  message: _error!,
                                  action: TextButton(
                                      onPressed: _load,
                                      child: const Text('Try again')))
                            else if (!_loading) ...[
                              if (_map) ...[
                                SizedBox(
                                    height: 320,
                                    child: ArianaMap(
                                        ownLocation: own,
                                        people: pins,
                                        selectedId: _selectedId,
                                        radiusKm: _radius,
                                        onSelect: _selectPerson)),
                                const SizedBox(height: 12),
                                if (selected != null)
                                  KeyedSubtree(
                                      key: _selectedCard,
                                      child: _card(selected))
                                else
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Text(
                                          pins.isEmpty
                                              ? 'No matching shared pins in Ariana. People without a shared pin are available in List.'
                                              : own == null
                                                  ? '${pins.length} shared ${pins.length == 1 ? 'pin' : 'pins'} on the map. Set your location to see who is nearby.'
                                                  : '${pins.length} ${pins.length == 1 ? 'person' : 'people'} ${_radius == null ? 'with a shared pin' : 'within ${_radius!.toInt()} km'}. Tap a marker to follow or add a friend.',
                                          style: const TextStyle(
                                              color: feedMuted))),
                              ] else if (people.isEmpty)
                                FeedNotice(
                                    icon: Icons.people_outline,
                                    title: _filter == 'requests'
                                        ? 'No pending requests'
                                        : 'No people found',
                                    message: _radius != null
                                        ? 'Try a wider distance or Any distance. Only accounts with shared pins can match a radius.'
                                        : 'Try another name or filter. To add someone, create another account on this phone.')
                              else
                                ...people.map(_card),
                            ],
                          ])),
            ))));
  }
}

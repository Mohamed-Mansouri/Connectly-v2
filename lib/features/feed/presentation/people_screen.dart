import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../application/feed_controller.dart';
import '../domain/feed_models.dart';
import 'feed_widgets.dart';

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({required this.repository, super.key});
  final FeedRepository repository;
  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _search = TextEditingController();
  final Set<String> _busy = {};
  List<FeedPerson> _people = [];
  bool _requests = false;
  bool _loading = true;
  String? _error;
  Timer? _debounce;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people = await widget.repository
          .people(search: _search.text, requests: _requests);
      if (mounted && revision == _revision) setState(() => _people = people);
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = FeedController.message(error));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _act(FeedPerson person, Future<void> Function() action) async {
    if (!_busy.add(person.id)) return;
    setState(() {});
    try {
      await action();
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(FeedController.message(error))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(person.id));
    }
  }

  Widget _friendAction(FeedPerson p) {
    final disabled = _busy.contains(p.id);
    switch (p.friendship) {
      case 'incoming':
        return Wrap(spacing: 8, children: [
          FilledButton(
              onPressed: disabled
                  ? null
                  : () => _act(
                      p, () => widget.repository.friendship(p.id, 'accept')),
              child: const Text('Accept request')),
          TextButton(
              onPressed: disabled
                  ? null
                  : () => _act(
                      p, () => widget.repository.friendship(p.id, 'remove')),
              child: const Text('Decline')),
        ]);
      case 'outgoing':
        return TextButton.icon(
            onPressed: disabled
                ? null
                : () =>
                    _act(p, () => widget.repository.friendship(p.id, 'remove')),
            icon: const Icon(Icons.schedule, size: 18),
            label: const Text('Cancel request'));
      case 'friends':
        return PopupMenuButton<String>(
            enabled: !disabled,
            tooltip: 'Friend options',
            onSelected: (_) =>
                _act(p, () => widget.repository.friendship(p.id, 'remove')),
            itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'remove', child: Text('Remove friend'))
                ],
            child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Friends ✓',
                    style: TextStyle(color: ConnectlyTheme.yellow))));
      default:
        return TextButton.icon(
            onPressed: disabled
                ? null
                : () => _act(
                    p, () => widget.repository.friendship(p.id, 'request')),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Add friend'));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('People',
                style: TextStyle(
                    fontFamily: 'Urbanist', fontWeight: FontWeight.w700))),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  padding: const EdgeInsets.all(20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const Text('Build your circle',
                        style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontSize: 28,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text(
                        'Follow someone to see their posts, or send a friend request to connect both ways.',
                        style: TextStyle(color: feedMuted, height: 1.5)),
                    const SizedBox(height: 20),
                    TextField(
                        controller: _search,
                        maxLength: 80,
                        decoration: const InputDecoration(
                            hintText: 'Search people by name',
                            prefixIcon: Icon(Icons.search),
                            counterText: '',
                            border: OutlineInputBorder()),
                        onChanged: (_) {
                          _revision++;
                          _debounce?.cancel();
                          _debounce =
                              Timer(const Duration(milliseconds: 350), _load);
                        }),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, children: [
                      ChoiceChip(
                          label: const Text('Discover'),
                          selected: !_requests,
                          onSelected: (_) {
                            _debounce?.cancel();
                            setState(() {
                              _requests = false;
                              _people = [];
                            });
                            _load();
                          }),
                      ChoiceChip(
                          label: const Text('Friend requests'),
                          selected: _requests,
                          onSelected: (_) {
                            _debounce?.cancel();
                            setState(() {
                              _requests = true;
                              _people = [];
                            });
                            _load();
                          }),
                    ]),
                    const SizedBox(height: 20),
                    if (_loading)
                      const Center(
                          child: Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator()))
                    else if (_error != null)
                      FeedNotice(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load people',
                          message: _error!,
                          action: FilledButton(
                              onPressed: _load, child: const Text('Try again')))
                    else if (_people.isEmpty)
                      FeedNotice(
                          icon: Icons.people_outline,
                          title: _requests
                              ? 'No pending requests'
                              : 'No people found',
                          message: _requests
                              ? 'New requests will appear here. Pull down to refresh.'
                              : 'Try a different name, or invite someone to create an account.')
                    else
                      ..._people.map((p) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: ConnectlyTheme.surface,
                                borderRadius: BorderRadius.circular(18)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    FeedAvatar(p.name),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text(p.name,
                                            style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w600))),
                                    if (_busy.contains(p.id))
                                      const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)),
                                  ]),
                                  const SizedBox(height: 12),
                                  Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        OutlinedButton.icon(
                                            onPressed: _busy.contains(p.id)
                                                ? null
                                                : () => _act(
                                                    p,
                                                    () => widget.repository
                                                        .follow(p.id,
                                                            !p.isFollowing)),
                                            icon: Icon(
                                                p.isFollowing
                                                    ? Icons.check
                                                    : Icons.add,
                                                size: 18),
                                            label: Text(p.isFollowing
                                                ? 'Following'
                                                : 'Follow')),
                                        _friendAction(p),
                                      ]),
                                ]),
                          )),
                    if (!_loading && _people.length == 50)
                      const Text(
                          'Showing up to 50 people. Search by name to narrow the list.',
                          style: TextStyle(color: feedMuted)),
                  ])),
        ))),
      );
}

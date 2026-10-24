import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../application/chat_controller.dart';
import '../domain/messaging_models.dart';
import 'chat_widgets.dart';

class NewConversationScreen extends StatefulWidget {
  const NewConversationScreen({required this.repository, super.key});
  final MessagingRepository repository;
  @override
  State<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen> {
  final _search = TextEditingController();
  final _title = TextEditingController();
  final Map<String, ChatPerson> _selected = {};
  List<ChatPerson> _contacts = [];
  bool _group = false;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
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
      _loadError = null;
    });
    try {
      final contacts = await widget.repository.contacts(_search.text);
      if (mounted && revision == _revision) {
        setState(() => _contacts = contacts);
      }
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _loadError = chatError(error));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    if ((_group && _selected.length < 2) ||
        (!_group && _selected.length != 1)) {
      setState(() => _error = _group
          ? 'Select at least two people for a group.'
          : 'Select one person to start chatting.');
      return;
    }
    if (_group &&
        (_title.text.trim().length < 2 || _title.text.trim().length > 80)) {
      setState(() => _error = 'Enter a group name with 2–80 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final conversation = await widget.repository.create(
          kind: _group ? 'group' : 'direct',
          memberIds: _selected.keys.toList(),
          title: _group ? _title.text.trim() : null);
      if (mounted) Navigator.pop(context, conversation);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = chatError(error);
        });
      }
    }
  }

  void _select(ChatPerson person) {
    if (_busy) return;
    setState(() {
      if (_selected.containsKey(person.id)) {
        _selected.remove(person.id);
      } else if (!_group) {
        _selected
          ..clear()
          ..[person.id] = person;
      } else if (_selected.length < 19) {
        _selected[person.id] = person;
      } else {
        _error = 'A group can include you and up to 19 other people.';
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('New conversation')),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      const Text('Good conversations start here.',
                          style: TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 28,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      const Text(
                          'Choose friends or people you follow. Find new connections in Feed → People.',
                          style: TextStyle(color: chatMuted, height: 1.5)),
                      const SizedBox(height: 20),
                      Wrap(spacing: 8, children: [
                        ChoiceChip(
                            label: const Text('Direct message'),
                            selected: !_group,
                            onSelected: _busy
                                ? null
                                : (_) => setState(() {
                                      _group = false;
                                      _selected.clear();
                                      _error = null;
                                    })),
                        ChoiceChip(
                            label: const Text('Group chat'),
                            selected: _group,
                            onSelected: _busy
                                ? null
                                : (_) => setState(() {
                                      _group = true;
                                      _selected.clear();
                                      _error = null;
                                    })),
                      ]),
                      if (_group) ...[
                        const SizedBox(height: 16),
                        TextField(
                            key: const Key('group_title'),
                            controller: _title,
                            enabled: !_busy,
                            maxLength: 80,
                            decoration: const InputDecoration(
                                labelText: 'Group name',
                                border: OutlineInputBorder()))
                      ],
                      const SizedBox(height: 16),
                      TextField(
                          controller: _search,
                          enabled: !_busy,
                          maxLength: 80,
                          decoration: const InputDecoration(
                              hintText: 'Search your connections',
                              prefixIcon: Icon(Icons.search),
                              counterText: '',
                              border: OutlineInputBorder()),
                          onChanged: (_) {
                            _revision++;
                            _debounce?.cancel();
                            _debounce =
                                Timer(const Duration(milliseconds: 350), _load);
                          }),
                      if (_selected.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(spacing: 8, children: [
                              for (final p in _selected.values)
                                InputChip(
                                    label: Text(p.name),
                                    onDeleted: _busy ? null : () => _select(p))
                            ])),
                      const SizedBox(height: 16),
                      if (_loading)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator()))
                      else if (_loadError != null)
                        ChatNotice(
                            title: 'Could not load contacts',
                            message: _loadError!,
                            action: FilledButton(
                                onPressed: _load,
                                child: const Text('Try again')))
                      else if (_contacts.isEmpty)
                        const ChatNotice(
                            title: 'No connections found',
                            message:
                                'Follow someone or accept a friend request in Feed → People, then try again.')
                      else
                        ..._contacts.map((person) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CheckboxListTile(
                                key: Key('contact_${person.id}'),
                                value: _selected.containsKey(person.id),
                                onChanged:
                                    _busy ? null : (_) => _select(person),
                                secondary: ChatAvatar(person.name),
                                title: Text(person.name),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                tileColor: ConnectlyTheme.surface))),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                          key: const Key('start_conversation'),
                          onPressed: _busy ? null : _create,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.chat_bubble_outline),
                          label:
                              Text(_busy ? 'Opening…' : 'Start conversation')),
                    ])))),
      ));
}

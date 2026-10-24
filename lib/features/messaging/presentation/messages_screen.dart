import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../../auth/presentation/auth_scope.dart';
import '../application/chat_controller.dart';
import '../data/chat_local_store.dart';
import '../data/messaging_api.dart';
import '../domain/messaging_models.dart';
import 'chat_widgets.dart';
import 'conversation_screen.dart';
import 'new_conversation_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({this.repository, this.localStore, super.key});
  final MessagingRepository? repository;
  final ChatLocalStore? localStore;
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with WidgetsBindingObserver {
  MessagingRepository? _repository;
  MessagingApi? _ownedApi;
  Future<ChatLocalStore>? _store;
  String? _userId;
  List<Conversation> _conversations = [];
  final _search = TextEditingController();
  bool _loading = false;
  bool _busy = false;
  bool _visible = false;
  bool _resumed = true;
  bool _active = false;
  bool _temporaryStorage = false;
  String? _error;
  int _revision = 0;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AuthScope.maybeOf(context);
    if (_userId != auth?.user?.id) {
      _revision++;
      _ownedApi?.close();
      _ownedApi = null;
      _repository = null;
      _store = null;
      _userId = auth?.user?.id;
      _conversations = [];
      _error = null;
      _busy = false;
      _active = false;
      _temporaryStorage = false;
      _search.clear();
      if (_userId != null) {
        _repository = widget.repository ??
            (_ownedApi = MessagingApi(token: () => auth?.sessionToken));
      }
    }
    _visible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _updatePolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _updatePolling();
  }

  void _updatePolling() {
    final active = _visible && _resumed && _repository != null;
    if (active == _active) return;
    _active = active;
    _poll?.cancel();
    _poll = null;
    if (active) {
      unawaited(_load());
      _poll = Timer.periodic(
          const Duration(seconds: 10), (_) => unawaited(_load(quiet: true)));
    }
  }

  Future<void> _load({bool quiet = false}) async {
    final repository = _repository;
    if (repository == null || _busy) return;
    final revision = _revision;
    _busy = true;
    setState(() {
      if (!quiet) _loading = true;
    });
    try {
      final conversations = await repository.conversations();
      if (mounted && revision == _revision) {
        setState(() {
          _conversations = conversations;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = chatError(error));
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  Future<ChatLocalStore> _localStore() => _store ??= (() async {
        if (widget.localStore != null) return widget.localStore!;
        try {
          return await HiveChatLocalStore.open();
        } catch (_) {
          _temporaryStorage = true;
          return MemoryChatLocalStore();
        }
      })();
  Future<void> _open(Conversation conversation) async {
    final repository = _repository;
    final userId = _userId;
    if (repository == null || userId == null) return;
    final store = await _localStore();
    if (!mounted || userId != _userId) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
            conversation: conversation,
            repository: repository,
            store: store,
            userId: userId,
            temporaryStorage: _temporaryStorage)));
    if (mounted) unawaited(_load());
  }

  Future<void> _create() async {
    final repository = _repository;
    if (repository == null) return;
    final conversation = await Navigator.of(context).push<Conversation>(
        MaterialPageRoute(
            builder: (_) => NewConversationScreen(repository: repository)));
    if (mounted && conversation != null) await _open(conversation);
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _ownedApi?.close();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _conversations
        .where((c) =>
            c.title.toLowerCase().contains(_search.text.trim().toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
          title: const Text('Chats',
              style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 27)),
          actions: [
            if (_repository != null)
              Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton.filledTonal(
                      key: const Key('new_conversation'),
                      onPressed: _create,
                      tooltip: 'New conversation',
                      icon: const Icon(Icons.edit_square)))
          ]),
      body: SafeArea(
          top: false,
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _repository == null
                ? ListView(children: [
                    ChatNotice(
                        title: 'A place for your people',
                        message:
                            'Sign in to start a conversation and keep in touch with your friends.',
                        action: FilledButton(
                            onPressed: () => Navigator.of(context)
                                .popUntil((route) => route.isFirst),
                            child: const Text('Sign in')))
                  ])
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                        padding: const EdgeInsets.all(20),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const Text('Stay in the conversation.',
                              style: TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          const Text(
                              'Private chats and shared moments with your circle.',
                              style: TextStyle(color: chatMuted, height: 1.5)),
                          const SizedBox(height: 24),
                          TextField(
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                  hintText: 'Search conversations',
                                  prefixIcon: const Icon(Icons.search),
                                  filled: true,
                                  fillColor: ConnectlyTheme.surface,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none))),
                          const SizedBox(height: 20),
                          if (_loading)
                            const Padding(
                                padding: EdgeInsets.all(20),
                                child:
                                    Center(child: CircularProgressIndicator())),
                          if (_error != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_error!,
                                          style: const TextStyle(
                                              color: chatMuted)),
                                      TextButton(
                                          onPressed: _load,
                                          child: const Text('Try again'))
                                    ])),
                          if (!_loading && _error == null && visible.isEmpty)
                            ChatNotice(
                                title: _conversations.isEmpty
                                    ? 'Start a conversation'
                                    : 'No matching conversations',
                                message: _conversations.isEmpty
                                    ? 'Say hello to a friend or bring your people together in a group.'
                                    : 'Try another name.',
                                action: _conversations.isEmpty
                                    ? OutlinedButton.icon(
                                        onPressed: _create,
                                        icon: const Icon(
                                            Icons.add_comment_outlined),
                                        label: const Text('New conversation'))
                                    : null),
                          for (final conversation in visible)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                    color: ConnectlyTheme.surface,
                                    borderRadius: BorderRadius.circular(18),
                                    child: ListTile(
                                      key: Key(
                                          'conversation_${conversation.id}'),
                                      onTap: () => _open(conversation),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 10),
                                      leading: ChatAvatar(conversation.title,
                                          group: conversation.isGroup),
                                      title: Text(conversation.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontFamily: 'Urbanist',
                                              fontWeight: FontWeight.w700,
                                              fontSize: 17)),
                                      subtitle: Text(
                                          conversation.lastBody == null
                                              ? 'Say hello 👋'
                                              : '${conversation.isGroup ? '${conversation.lastSenderName}: ' : ''}${conversation.lastBody}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: chatMuted, height: 1.5)),
                                      trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                                conversation.lastMessageAt ==
                                                        null
                                                    ? ''
                                                    : messageDate(conversation
                                                        .lastMessageAt!),
                                                style: const TextStyle(
                                                    color: chatMuted,
                                                    fontSize: 11)),
                                            if (conversation.unreadCount > 0)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 6),
                                                  child: Badge(
                                                      label: Text(conversation
                                                                  .unreadCount >
                                                              99
                                                          ? '99+'
                                                          : '${conversation.unreadCount}'))),
                                          ]),
                                    ))),
                        ])),
          ))),
    );
  }
}

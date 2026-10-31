import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../application/chat_controller.dart';
import '../data/chat_local_store.dart';
import '../data/voice_recorder.dart';
import '../domain/messaging_models.dart';
import 'chat_widgets.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen(
      {required this.conversation,
      required this.repository,
      required this.store,
      required this.userId,
      this.temporaryStorage = false,
      this.voiceRecorder,
      super.key});
  final Conversation conversation;
  final MessagingRepository repository;
  final ChatLocalStore store;
  final String userId;
  final bool temporaryStorage;
  final VoiceRecorder? voiceRecorder;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  late final ChatController _chat;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _resumed = true;
  bool _current = true;
  bool _draftLoaded = false;
  VoiceRecorder? _recorder;
  VoiceRecorder get _voiceRecorder =>
      _recorder ??= widget.voiceRecorder ?? DeviceVoiceRecorder();
  VoiceClip? _voiceDraft;
  String? _voiceClientId;
  bool _recording = false;
  bool _voiceBusy = false;
  DateTime? _recordStarted;
  Timer? _recordTimer;
  AudioPlayer? _player;
  StreamSubscription<void>? _playerDone;
  int? _playingVoice;

  String _duration(int milliseconds) {
    final seconds = (milliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chat = ChatController(
        repository: widget.repository,
        store: widget.store,
        userId: widget.userId,
        conversationId: widget.conversation.id)
      ..addListener(_changed);
    unawaited(_chat.initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _current = ModalRoute.of(context)?.isCurrent ?? true;
    _chat.setActive(_resumed && _current);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _chat.setActive(_resumed && _current);
    if (!_resumed && _recording) unawaited(_cancelRecording());
  }

  void _voiceNotice(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(chatError(error))));
  }

  Future<void> _startRecording() async {
    if (_recording || _voiceBusy || _voiceDraft != null) return;
    setState(() => _voiceBusy = true);
    try {
      await _voiceRecorder.start();
      if (!mounted) {
        await _voiceRecorder.cancel();
        return;
      }
      _recordStarted = DateTime.now();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_recording) return;
        if (DateTime.now().difference(_recordStarted!).inSeconds >= 60) {
          unawaited(_stopRecording());
        } else {
          setState(() {});
        }
      });
      setState(() => _recording = true);
    } catch (error) {
      _voiceNotice(error);
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _voiceBusy) return;
    _recordTimer?.cancel();
    setState(() => _voiceBusy = true);
    try {
      final clip = await _voiceRecorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _voiceDraft = clip;
        _voiceClientId = newMessageId();
      });
    } catch (error) {
      if (mounted) setState(() => _recording = false);
      _voiceNotice(error);
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    if (mounted) setState(() => _recording = false);
    try {
      await _voiceRecorder.cancel();
    } catch (error) {
      _voiceNotice(error);
    }
  }

  Future<void> _sendVoice() async {
    final clip = _voiceDraft;
    final clientId = _voiceClientId;
    if (_voiceBusy || clip == null || clientId == null) return;
    setState(() => _voiceBusy = true);
    try {
      await widget.repository.sendVoice(
          widget.conversation.id, clientId, clip.bytes, clip.durationMs);
      if (!mounted) return;
      setState(() {
        _voiceDraft = null;
        _voiceClientId = null;
      });
      await _chat.sync();
    } catch (error) {
      _voiceNotice(error);
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _playVoice(int sequence, {Uint8List? draftBytes}) async {
    try {
      final player = _player ??= AudioPlayer();
      _playerDone ??= player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playingVoice = null);
      });
      if (_playingVoice == sequence) {
        await player.stop();
        if (mounted) setState(() => _playingVoice = null);
        return;
      }
      final bytes = draftBytes ??
          await widget.repository.voiceBytes(widget.conversation.id, sequence);
      await player.stop();
      await player.play(BytesSource(bytes, mimeType: 'audio/mp4'));
      if (mounted) setState(() => _playingVoice = sequence);
    } catch (error) {
      if (mounted) setState(() => _playingVoice = null);
      _voiceNotice(error);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!_chat.initializing && !_draftLoaded) {
      _input.text = _chat.draft;
      _draftLoaded = true;
    }
    setState(() {});
  }

  Future<void> _send() async {
    _chat.updateDraft(_input.text);
    if (_input.text.trim().isEmpty ||
        _input.text.trim().length > 4000 ||
        _chat.sending ||
        _chat.initializing) {
      return;
    }
    final send = _chat.sendDraft();
    _input.clear();
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
    }
    await send;
  }

  Future<void> _members() async {
    await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _MembersSheet(
            repository: widget.repository,
            conversation: widget.conversation,
            userId: widget.userId));
  }

  Widget _bubble(String body, bool own, String name, DateTime time,
          {String? status,
          Widget? action,
          int? voiceSequence,
          int? voiceDurationMs}) =>
      Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width.clamp(0, 720) * .82),
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: own ? ConnectlyTheme.yellow : ConnectlyTheme.surface,
                borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(own ? 18 : 4),
                    bottomRight: Radius.circular(own ? 4 : 18))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!own && widget.conversation.isGroup)
                Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(name,
                        style: const TextStyle(
                            color: ConnectlyTheme.yellow,
                            fontWeight: FontWeight.w700,
                            fontSize: 12))),
              if (voiceSequence != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    key: Key('voice_play_$voiceSequence'),
                    tooltip: _playingVoice == voiceSequence
                        ? 'Stop voice message'
                        : 'Play voice message',
                    onPressed: () => _playVoice(voiceSequence),
                    icon: Icon(_playingVoice == voiceSequence
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded),
                  ),
                  Text('Voice message · ${_duration(voiceDurationMs ?? 0)}',
                      style: TextStyle(
                          color: own ? ConnectlyTheme.navy : Colors.white)),
                ])
              else
                SelectableText(body,
                    style: TextStyle(
                        color: own ? ConnectlyTheme.navy : Colors.white,
                        fontSize: 16,
                        height: 1.4)),
              const SizedBox(height: 5),
              Text(
                  '${messageDate(time)} · ${messageTime(time)}${status == null ? '' : ' · $status'}',
                  style: TextStyle(
                      color: own
                          ? ConnectlyTheme.navy.withValues(alpha: .7)
                          : chatMuted,
                      fontSize: 11)),
              if (action != null) action,
            ])),
      );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chat.removeListener(_changed);
    _chat.dispose();
    _recordTimer?.cancel();
    if (_recorder != null) unawaited(_recorder!.dispose());
    unawaited(_playerDone?.cancel());
    if (_player != null) unawaited(_player!.dispose());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.conversation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w700,
                      fontSize: 19)),
              Text(
                  widget.conversation.isGroup
                      ? '${widget.conversation.memberCount} members'
                      : 'Direct message',
                  style: const TextStyle(color: chatMuted, fontSize: 12)),
            ]),
            actions: [
              IconButton(
                  onPressed: _members,
                  tooltip: 'Conversation members',
                  icon: const Icon(Icons.people_outline))
            ]),
        body: SafeArea(
            top: false,
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(children: [
                      if (_chat.error != null)
                        _errorBar(_chat.error!, () => _chat.sync()),
                      if (_chat.storageError != null || widget.temporaryStorage)
                        Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Text(
                                _chat.storageError ??
                                    'Drafts are available only until this app closes.',
                                style: const TextStyle(
                                    color: chatMuted, fontSize: 12))),
                      Expanded(
                          child: _chat.initializing || _chat.loading
                              ? const Center(child: CircularProgressIndicator())
                              : _chat.messages.isEmpty && _chat.outbox.isEmpty
                                  ? ListView(children: [
                                      ChatNotice(
                                          title: 'Say hello',
                                          message:
                                              'Start the conversation. New messages update every few seconds.',
                                          action: TextButton.icon(
                                              onPressed: _chat.sync,
                                              icon: const Icon(Icons.refresh),
                                              label: const Text('Refresh')))
                                    ])
                                  : ListView.builder(
                                      controller: _scroll,
                                      reverse: true,
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 12, 16, 16),
                                      itemCount: _chat.messages.length +
                                          _chat.outbox.length +
                                          (_chat.olderCursor == null ? 0 : 1),
                                      itemBuilder: (context, index) {
                                        if (index < _chat.outbox.length) {
                                          final item = _chat.outbox[
                                              _chat.outbox.length - 1 - index];
                                          return _bubble(item.body, true, 'You',
                                              item.createdAt,
                                              status: item.sending
                                                  ? 'Sending…'
                                                  : 'Not confirmed',
                                              action: item.sending
                                                  ? null
                                                  : Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                          if (item.error !=
                                                              null)
                                                            Text(item.error!,
                                                                style: const TextStyle(
                                                                    color:
                                                                        ConnectlyTheme
                                                                            .navy,
                                                                    fontSize:
                                                                        12)),
                                                          TextButton.icon(
                                                              key: Key(
                                                                  'retry_${item.clientId}'),
                                                              onPressed: _chat
                                                                      .sending
                                                                  ? null
                                                                  : () => _chat
                                                                      .retry(
                                                                          item),
                                                              style: TextButton.styleFrom(
                                                                  foregroundColor:
                                                                      ConnectlyTheme
                                                                          .navy),
                                                              icon: const Icon(
                                                                  Icons.refresh,
                                                                  size: 16),
                                                              label: const Text(
                                                                  'Retry')),
                                                        ]));
                                        }
                                        final messageIndex =
                                            _chat.messages.length -
                                                1 -
                                                (index - _chat.outbox.length);
                                        if (messageIndex < 0) {
                                          return Center(
                                              child: TextButton(
                                                  onPressed: _chat.loadingOlder
                                                      ? null
                                                      : _chat.loadOlder,
                                                  child: Text(_chat.loadingOlder
                                                      ? 'Loading…'
                                                      : 'Load earlier messages')));
                                        }
                                        final message =
                                            _chat.messages[messageIndex];
                                        return KeyedSubtree(
                                            key: ValueKey(message.sequence),
                                            child: _bubble(
                                                message.body,
                                                message.sender.id ==
                                                    widget.userId,
                                                message.sender.name,
                                                message.createdAt,
                                                voiceSequence: message.isVoice
                                                    ? message.sequence
                                                    : null,
                                                voiceDurationMs:
                                                    message.voiceDurationMs));
                                      })),
                      if (_recording)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            const Icon(Icons.mic, color: Colors.redAccent),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'Recording ${_duration(DateTime.now().difference(_recordStarted!).inMilliseconds)}')),
                            TextButton(
                                onPressed: _voiceBusy ? null : _cancelRecording,
                                child: const Text('Cancel')),
                            FilledButton(
                                key: const Key('voice_stop'),
                                onPressed: _voiceBusy ? null : _stopRecording,
                                child: const Text('Stop')),
                          ]),
                        ),
                      if (_voiceDraft != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            IconButton(
                                key: const Key('voice_preview'),
                                tooltip: 'Play recording',
                                onPressed: () => _playVoice(-1,
                                    draftBytes: _voiceDraft!.bytes),
                                icon: Icon(_playingVoice == -1
                                    ? Icons.stop_rounded
                                    : Icons.play_arrow_rounded)),
                            Expanded(
                                child: Text(
                                    'Voice clip · ${_duration(_voiceDraft!.durationMs)}')),
                            IconButton(
                                tooltip: 'Discard recording',
                                onPressed: _voiceBusy
                                    ? null
                                    : () => setState(() {
                                          _voiceDraft = null;
                                          _voiceClientId = null;
                                        }),
                                icon: const Icon(Icons.delete_outline)),
                            FilledButton(
                                key: const Key('voice_send'),
                                onPressed: _voiceBusy ? null : _sendVoice,
                                child: const Text('Send')),
                          ]),
                        ),
                      Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          color: ConnectlyTheme.surface,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                    child: TextField(
                                        key: const Key('message_input'),
                                        controller: _input,
                                        enabled: !_chat.initializing,
                                        minLines: 1,
                                        maxLines: 5,
                                        maxLength: 4000,
                                        textCapitalization:
                                            TextCapitalization.sentences,
                                        onChanged: (value) {
                                          _chat.updateDraft(value);
                                          setState(() {});
                                        },
                                        decoration: InputDecoration(
                                            hintText: 'Write a message…',
                                            counterText: '',
                                            border: InputBorder.none,
                                            errorText: _input.text
                                                        .trim()
                                                        .length >
                                                    4000
                                                ? 'Please shorten this message.'
                                                : null))),
                                IconButton(
                                    key: const Key('voice_record'),
                                    tooltip: 'Record voice message',
                                    onPressed: _chat.initializing ||
                                            _voiceBusy ||
                                            _recording ||
                                            _voiceDraft != null
                                        ? null
                                        : _startRecording,
                                    icon: const Icon(Icons.mic_none_rounded)),
                                IconButton.filled(
                                    key: const Key('send_message'),
                                    tooltip: 'Send message',
                                    onPressed: _chat.initializing ||
                                            _chat.sending ||
                                            _input.text.trim().isEmpty ||
                                            _input.text.trim().length > 4000
                                        ? null
                                        : _send,
                                    icon: _chat.sending
                                        ? const SizedBox.square(
                                            dimension: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.send_rounded)),
                              ])),
                    ])))),
      );
  Widget _errorBar(String message, VoidCallback retry) => Container(
      color: ConnectlyTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(
            child: Text(message,
                style: const TextStyle(color: chatMuted, fontSize: 12))),
        TextButton(onPressed: retry, child: const Text('Retry'))
      ]));
}

class _MembersSheet extends StatefulWidget {
  const _MembersSheet(
      {required this.repository,
      required this.conversation,
      required this.userId});
  final MessagingRepository repository;
  final Conversation conversation;
  final String userId;
  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  late Future<List<ChatPerson>> _members;
  @override
  void initState() {
    super.initState();
    _members = widget.repository.members(widget.conversation.id);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: FutureBuilder<List<ChatPerson>>(
              future: _members,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ChatNotice(
                      title: 'Could not load members',
                      message: chatError(snapshot.error!),
                      action: TextButton(
                          onPressed: () => setState(() => _members = widget
                              .repository
                              .members(widget.conversation.id)),
                          child: const Text('Try again')));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(padding: const EdgeInsets.all(20), children: [
                  Text('Conversation members',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  for (final person in snapshot.data!)
                    ListTile(
                        leading: ChatAvatar(person.name),
                        title: Text(
                            '${person.name}${person.id == widget.userId ? ' · You' : ''}'))
                ]);
              })));
}

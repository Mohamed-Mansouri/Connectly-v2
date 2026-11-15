import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../application/feed_controller.dart';
import '../domain/feed_models.dart';
import 'feed_widgets.dart';

/// Lists who reacted to a post, filterable by reaction kind.
class ReactorsSheet extends StatefulWidget {
  const ReactorsSheet(
      {required this.repository,
      required this.post,
      required this.userId,
      super.key});
  final FeedRepository repository;
  final FeedPost post;
  final String userId;
  @override
  State<ReactorsSheet> createState() => _ReactorsSheetState();
}

class _ReactorsSheetState extends State<ReactorsSheet> {
  late Future<List<FeedReactor>> _reactors =
      widget.repository.reactors(widget.post.id);
  String? _kind;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: FutureBuilder<List<FeedReactor>>(
            future: _reactors,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return FeedNotice(
                    icon: Icons.error_outline,
                    title: 'Reactions unavailable',
                    message: FeedController.message(snapshot.error!),
                    action: TextButton(
                        onPressed: () => setState(() => _reactors =
                            widget.repository.reactors(widget.post.id)),
                        child: const Text('Try again')));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data!;
              final kinds = {for (final r in all) r.kind};
              final shown =
                  all.where((r) => _kind == null || r.kind == _kind).toList();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                        padding: EdgeInsets.fromLTRB(24, 4, 24, 12),
                        child: Text('Reactions',
                            style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 22,
                                fontWeight: FontWeight.w700))),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(children: [
                        ChoiceChip(
                            label: Text('All ${all.length}'),
                            selected: _kind == null,
                            onSelected: (_) => setState(() => _kind = null)),
                        for (final kind
                            in reactionLabels.keys.where(kinds.contains))
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ChoiceChip(
                                key: Key('reactors_filter_$kind'),
                                avatar: Icon(reactionIcons[kind],
                                    size: 16, color: ConnectlyTheme.yellow),
                                label: Text(
                                    '${all.where((r) => r.kind == kind).length}'),
                                selected: _kind == kind,
                                onSelected: (_) =>
                                    setState(() => _kind = kind)),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: shown.isEmpty
                          ? const Center(
                              child: Text('No reactions yet',
                                  style: TextStyle(color: feedMuted)))
                          : ListView.builder(
                              itemCount: shown.length,
                              itemBuilder: (context, i) {
                                final r = shown[i];
                                return ListTile(
                                  leading: FeedAvatar(r.name),
                                  title: Text(
                                      '${r.name}${r.userId == widget.userId ? ' · You' : ''}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  trailing: Tooltip(
                                      message: reactionLabels[r.kind] ?? '',
                                      child: Icon(reactionIcons[r.kind],
                                          color: ConnectlyTheme.yellow)),
                                );
                              }),
                    ),
                  ]);
            },
          ),
        ),
      );
}

/// Shows a post's comments and lets the viewer write or remove them.
class CommentsSheet extends StatefulWidget {
  const CommentsSheet(
      {required this.repository,
      required this.post,
      required this.userId,
      required this.onCountChanged,
      super.key});
  final FeedRepository repository;
  final FeedPost post;
  final String userId;
  final ValueChanged<int> onCountChanged;
  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<FeedComment>? _comments;
  String? _error;
  bool _sending = false;
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final comments = await widget.repository.comments(widget.post.id);
      if (!mounted) return;
      setState(() => _comments = comments);
      widget.onCountChanged(comments.length);
    } catch (error) {
      if (mounted) setState(() => _error = FeedController.message(error));
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (_sending || body.isEmpty || body.length > 1000) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final comment = await widget.repository.addComment(widget.post.id, body);
      if (!mounted) return;
      _text.clear();
      setState(() => _comments = [...?_comments, comment]);
      widget.onCountChanged(_comments!.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = FeedController.message(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(FeedComment comment) async {
    if (!_deleting.add(comment.id)) return;
    setState(() {});
    try {
      await widget.repository.deleteComment(comment.id);
      if (!mounted) return;
      setState(() =>
          _comments = _comments!.where((c) => c.id != comment.id).toList());
      widget.onCountChanged(_comments!.length);
    } catch (error) {
      if (mounted) setState(() => _error = FeedController.message(error));
    } finally {
      _deleting.remove(comment.id);
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _commentTile(FeedComment c, bool canModerate) {
    final mine = c.authorId == widget.userId;
    return Padding(
      key: ValueKey(c.id),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FeedAvatar(c.authorName),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
                color: ConnectlyTheme.surface,
                borderRadius: BorderRadius.circular(16)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${c.authorName}${mine ? ' · You' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(postTime(c.createdAt),
                    style: const TextStyle(color: feedMuted, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              SelectableText(c.body, style: const TextStyle(height: 1.45)),
            ]),
          ),
        ),
        if (mine || canModerate)
          _deleting.contains(c.id)
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  tooltip: 'Delete comment',
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: feedMuted),
                  onPressed: () => _delete(c)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    final canModerate = widget.post.authorId == widget.userId;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                    comments == null
                        ? 'Comments'
                        : 'Comments · ${comments.length}',
                    style: const TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 22,
                        fontWeight: FontWeight.w700))),
            Expanded(
              child: comments == null
                  ? (_error == null
                      ? const Center(child: CircularProgressIndicator())
                      : Center(
                          child: TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'))))
                  : comments.isEmpty
                      ? const Center(
                          child: Text(
                              'No comments yet. Start the conversation.',
                              style: TextStyle(color: feedMuted)))
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: comments.length,
                          itemBuilder: (context, i) =>
                              _commentTile(comments[i], canModerate)),
            ),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                  child: Text(_error!,
                      style: const TextStyle(color: feedMuted, fontSize: 13))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('comment_input'),
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        hintText: 'Write a comment…', counterText: ''),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                    key: const Key('comment_send'),
                    tooltip: 'Send comment',
                    onPressed:
                        _sending || _text.text.trim().isEmpty ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            color: ConnectlyTheme.yellow)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

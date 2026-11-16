import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../application/feed_controller.dart';
import '../domain/feed_models.dart';
import '../domain/post_text.dart';
import 'feed_widgets.dart';
import 'post_card.dart';
import 'post_sheets.dart';
import 'suggestion_bar.dart';

/// Searches visible posts by words, #tags and @people.
/// With an empty box it shows trending tags and a shortcut to your mentions.
class PostSearchScreen extends StatefulWidget {
  const PostSearchScreen(
      {required this.repository,
      required this.userId,
      required this.userHandle,
      this.initialQuery = '',
      super.key});
  final FeedRepository repository;
  final String userId;
  final String userHandle;
  final String initialQuery;
  @override
  State<PostSearchScreen> createState() => _PostSearchScreenState();
}

class _PostSearchScreenState extends State<PostSearchScreen> {
  late final _input = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  int _revision = 0;
  String _query = '';
  List<FeedPost> _results = const [];
  List<FeedTrend> _trends = const [];
  final Set<String> _busy = {};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input.addListener(_typed);
    unawaited(_loadTrends());
    if (widget.initialQuery.isNotEmpty) unawaited(_run(widget.initialQuery));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadTrends() async {
    try {
      final trends = await widget.repository.trendingTags();
      if (mounted) setState(() => _trends = trends);
    } catch (_) {
      // Trends are optional; search still works.
    }
  }

  void _typed() {
    final text = _input.text.trim();
    if (text == _query) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(text));
  }

  /// Replaces the box content, e.g. after tapping a tag.
  void _searchFor(String text) {
    _input.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    unawaited(_run(text));
  }

  Future<void> _run(String text) async {
    final revision = ++_revision;
    setState(() {
      _query = text.trim();
      _error = null;
      _loading = _query.isNotEmpty;
      if (_query.isEmpty) _results = const [];
    });
    if (_query.isEmpty) return;
    try {
      final results = await widget.repository.search(_query);
      if (!mounted || revision != _revision) return;
      setState(() => _results = results);
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = FeedController.message(error));
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  void _replace(FeedPost updated) => setState(() => _results =
      _results.map((p) => p.id == updated.id ? updated : p).toList());

  Future<void> _react(FeedPost post, String? kind) async {
    if (!_busy.add(post.id)) return;
    setState(() {});
    try {
      _replace(await widget.repository.react(post.id, kind));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(FeedController.message(error))));
      }
    } finally {
      _busy.remove(post.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _comments(FeedPost post) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: ConnectlyTheme.navy,
      builder: (_) => CommentsSheet(
          repository: widget.repository,
          post: post,
          userId: widget.userId,
          onCountChanged: (count) {
            if (mounted) _replace(post.copyWith(commentCount: count));
          }));

  Future<void> _reactors(FeedPost post) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: ConnectlyTheme.navy,
      builder: (_) => ReactorsSheet(
          repository: widget.repository, post: post, userId: widget.userId));

  Widget _start() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text('Trending this month',
              style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_trends.isEmpty)
            const Text('No hashtags yet. Add #tags to your posts to start one.',
                style: TextStyle(color: feedMuted))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final trend in _trends)
                ActionChip(
                    key: Key('trend_${trend.tag}'),
                    onPressed: () => _searchFor('#${trend.tag}'),
                    label: Text('#${trend.tag} · ${trend.count}')),
            ]),
          if (widget.userHandle.isNotEmpty) ...[
            const SizedBox(height: 28),
            ListTile(
              key: const Key('search_my_mentions'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alternate_email,
                  color: ConnectlyTheme.yellow),
              title: const Text('Your posts and mentions'),
              subtitle: Text('@${widget.userHandle}',
                  style: const TextStyle(color: feedMuted)),
              onTap: () => _searchFor('@${widget.userHandle}'),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
              'Tips: type words to search post text, #tag for a topic, '
              'or @name for a person. Combine them, for example "#trip @amal beach".',
              style: TextStyle(color: feedMuted, height: 1.5)),
        ],
      );

  Widget _resultsList() {
    final words = PostQuery.parse(_query).words;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: feedMuted))),
        if (!_loading && _error == null && _results.isEmpty)
          const FeedNotice(
              icon: Icons.search_off,
              title: 'No posts found',
              message:
                  'Try fewer words, another #tag, or check the @name spelling.'),
        if (!_loading && _results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                '${_results.length} post${_results.length == 1 ? '' : 's'}',
                key: const Key('search_count'),
                style: const TextStyle(color: feedMuted)),
          ),
        for (final post in _results)
          PostCard(
            key: ValueKey('search_${post.id}'),
            post: post,
            isOwn: post.authorId == widget.userId,
            busy: _busy.contains(post.id),
            onDelete: null,
            onComment: () => _comments(post),
            onShowReactors: () => _reactors(post),
            onReact: (kind) => _react(post, kind),
            loadImage: () => widget.repository.postImage(post.id),
            onTag: (tag) => _searchFor('#$tag'),
            onMention: (handle) => _searchFor('@$handle'),
            highlight: words,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: TextField(
            key: const Key('search_input'),
            controller: _input,
            autofocus: widget.initialQuery.isEmpty,
            textInputAction: TextInputAction.search,
            maxLength: 200,
            onSubmitted: _searchFor,
            decoration: InputDecoration(
              hintText: 'Search posts, #tags, @people',
              border: InputBorder.none,
              counterText: '',
              suffixIcon: _input.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => _searchFor(''),
                      icon: const Icon(Icons.close)),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SuggestionBar(
                      controller: _input, repository: widget.repository),
                ),
                Expanded(child: _query.isEmpty ? _start() : _resultsList()),
              ]),
            ),
          ),
        ),
      );
}

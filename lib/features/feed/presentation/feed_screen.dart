import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/connectly_theme.dart';
import '../../../app/app_shell.dart';
import '../../../app/local_data_scope.dart';
import '../../auth/presentation/auth_scope.dart';
import '../application/feed_controller.dart';
import '../../messaging/domain/messaging_models.dart';
import '../domain/feed_models.dart';
import 'create_post_sheet.dart';
import 'feed_widgets.dart';
import 'post_card.dart';
import 'post_search_screen.dart';
import 'post_sheets.dart';
import 'share_sheets.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen(
      {this.repository, this.messaging, this.pickPostImage, super.key});
  final FeedRepository? repository;

  /// Used by "Send to a friend"; defaults to the local database.
  final MessagingRepository? messaging;

  /// Replaces the system photo picker in the composer (used by tests).
  final Future<Uint8List?> Function(ImageSource source)? pickPostImage;
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  FeedController? _controller;
  String? _userId;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AuthScope.maybeOf(context);
    final visible = TickerMode.valuesOf(context).enabled;
    if (_userId == auth?.user?.id) {
      if (visible && !_visible && _controller != null) {
        unawaited(_controller!.refresh());
      }
      _visible = visible;
      return;
    }
    _visible = visible;
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _controller = null;
    _userId = auth?.user?.id;
    if (_userId != null) {
      final repository =
          widget.repository ?? LocalDataScope.of(context).feedFor(_userId!);
      _controller = FeedController(repository)..addListener(_changed);
      unawaited(_controller!.refresh());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _compose() async {
    final controller = _controller;
    final user = AuthScope.maybeOf(context)?.user;
    if (controller == null || user == null) return;
    final post = await showModalBottomSheet<FeedPost>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: ConnectlyTheme.navy,
        showDragHandle: false,
        builder: (_) => CreatePostSheet(
            repository: controller.repository,
            name: user.name,
            pickImage: widget.pickPostImage));
    if (mounted && identical(controller, _controller) && post != null) {
      _published(controller, post, 'Posted.');
    }
  }

  /// The default view hides your own posts, so a new post or repost is
  /// shown in place only under "Me"; otherwise a snackbar points there.
  void _published(FeedController controller, FeedPost post, String text) {
    if (controller.scope == 'me') {
      controller.created(post);
      return;
    }
    unawaited(controller.refresh()); // Updates share counts.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$text You can find it under Me.'),
        action: SnackBarAction(
            label: 'View',
            onPressed: () {
              if (identical(controller, _controller)) {
                unawaited(controller.refresh(filter: 'me'));
              }
            })));
  }

  Future<void> _share(FeedPost post, String action) async {
    final controller = _controller;
    final userId = _userId;
    if (controller == null || userId == null) return;
    if (action == 'repost') {
      final repost = await showModalBottomSheet<FeedPost>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: ConnectlyTheme.navy,
          builder: (_) =>
              RepostSheet(repository: controller.repository, post: post));
      if (mounted && identical(controller, _controller) && repost != null) {
        _published(controller, repost, 'Reposted.');
      }
      return;
    }
    final messaging =
        widget.messaging ?? LocalDataScope.of(context).messagingFor(userId);
    final friend = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: ConnectlyTheme.navy,
        builder: (_) => SendToFriendSheet(messaging: messaging, post: post));
    if (friend != null) _message('Sent to $friend in Chats.');
  }

  void _message(String? message) {
    if (mounted && message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _delete(FeedPost post) async {
    final controller = _controller;
    if (controller == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Delete this post?'),
                content: const Text('This will also remove its reactions.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep post')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'))
                ]));
    if (confirmed == true && mounted) _message(await controller.delete(post));
  }

  Future<void> _comments(FeedPost post) async {
    final controller = _controller;
    final userId = _userId;
    if (controller == null || userId == null) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: ConnectlyTheme.navy,
        builder: (_) => CommentsSheet(
            repository: controller.repository,
            post: post,
            userId: userId,
            onCountChanged: (count) {
              if (identical(controller, _controller)) {
                controller.commentsChanged(post.id, count);
              }
            }));
  }

  Future<void> _reactors(FeedPost post) async {
    final controller = _controller;
    final userId = _userId;
    if (controller == null || userId == null) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: ConnectlyTheme.navy,
        builder: (_) => ReactorsSheet(
            repository: controller.repository, post: post, userId: userId));
  }

  /// Opens search; [query] may be a tapped `#tag` or `@handle`.
  Future<void> _search([String query = '']) async {
    final controller = _controller;
    final user = AuthScope.maybeOf(context)?.user;
    if (controller == null || user == null) return;
    final at = user.email.indexOf('@');
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PostSearchScreen(
            repository: controller.repository,
            userId: user.id,
            userHandle: at > 0 ? user.email.substring(0, at).toLowerCase() : '',
            initialQuery: query)));
    // Reactions or comments made in search show up in the feed.
    if (mounted && identical(controller, _controller)) {
      unawaited(controller.refresh());
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final user = AuthScope.maybeOf(context)?.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('connectly',
            style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 27,
                letterSpacing: -1)),
        actions: [
          if (controller != null)
            IconButton(
                key: const Key('feed_search'),
                tooltip: 'Search posts',
                onPressed: _search,
                icon: const Icon(Icons.search)),
        ],
      ),
      body: SafeArea(
          top: false,
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: controller == null
                ? ListView(children: [
                    FeedNotice(
                        icon: Icons.dynamic_feed_outlined,
                        title: 'Your people. Your feed.',
                        message:
                            'Sign in to share a moment, follow people, and see what your friends are posting.',
                        action: FilledButton(
                            onPressed: () => Navigator.of(context)
                                .popUntil((route) => route.isFirst),
                            child: const Text('Sign in')))
                  ])
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: ListView(
                      key: const PageStorageKey('feed_list'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        const Text('Your daily catch-up',
                            style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.6)),
                        const SizedBox(height: 6),
                        const Text(
                            'Little moments from the people you connect with.',
                            style: TextStyle(color: feedMuted, height: 1.5)),
                        const SizedBox(height: 24),
                        Material(
                            color: ConnectlyTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              key: const Key('create_post'),
                              onTap: _compose,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Row(children: [
                                    FeedAvatar(user!.name),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                        child: Text("What's on your mind?",
                                            style: TextStyle(
                                                color: feedMuted,
                                                fontSize: 15))),
                                    const Icon(Icons.edit_square,
                                        color: ConnectlyTheme.yellow, size: 23),
                                  ])),
                            )),
                        const SizedBox(height: 20),
                        // "All" (the default) = friends and followed people,
                        // without your own posts, which are under "Me".
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final filter in const {
                            'me': 'Me',
                            'all': 'All',
                            'friends': 'Friends',
                            'following': 'Following'
                          }.entries)
                            ChoiceChip(
                                key: Key('filter_${filter.key}'),
                                label: Text(filter.value),
                                selected: controller.scope == filter.key,
                                onSelected: (_) =>
                                    controller.refresh(filter: filter.key)),
                        ]),
                        const SizedBox(height: 20),
                        if (controller.loading)
                          const Padding(
                              padding: EdgeInsets.all(20),
                              child:
                                  Center(child: CircularProgressIndicator())),
                        if (controller.error != null)
                          Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                                color: ConnectlyTheme.surface,
                                borderRadius: BorderRadius.circular(16)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(controller.error!,
                                      style: const TextStyle(color: feedMuted)),
                                  TextButton.icon(
                                      onPressed: () => controller.refresh(),
                                      icon: const Icon(Icons.refresh, size: 18),
                                      label: const Text('Try again')),
                                ]),
                          ),
                        if (!controller.loading &&
                            controller.error == null &&
                            controller.posts.isEmpty)
                          controller.scope == 'me'
                              ? FeedNotice(
                                  icon: Icons.edit_note_rounded,
                                  title: 'You have not posted yet',
                                  message:
                                      'Your posts and reposts appear here.',
                                  action: FilledButton(
                                      onPressed: _compose,
                                      child: const Text('Write a post')))
                              : FeedNotice(
                                  icon: Icons.waving_hand_outlined,
                                  title: 'A fresh start for your feed',
                                  message:
                                      'Posts from your friends and the people you follow appear here. Your own posts are under Me.',
                                  action: OutlinedButton.icon(
                                      onPressed: () =>
                                          AppTabScope.people(context),
                                      icon: const Icon(Icons.person_add_alt),
                                      label: const Text('Find people'))),
                        for (final post in controller.posts)
                          PostCard(
                              key: ValueKey(post.id),
                              post: post,
                              isOwn: post.authorId == _userId,
                              busy: controller.busyPosts.contains(post.id),
                              onDelete: () => _delete(post),
                              onComment: () => _comments(post),
                              onShowReactors: () => _reactors(post),
                              loadImage: controller.repository.postImage,
                              onShare: (action) => _share(post, action),
                              onTag: (tag) => _search('#$tag'),
                              onMention: (handle) => _search('@$handle'),
                              onReact: (kind) async =>
                                  _message(await controller.react(post, kind))),
                        if (!controller.loading &&
                            controller.nextCursor != null)
                          Center(
                              child: OutlinedButton(
                                  onPressed: controller.loadingMore
                                      ? null
                                      : controller.loadMore,
                                  child: Text(controller.loadingMore
                                      ? 'Loading…'
                                      : 'Load more posts'))),
                        if (!controller.loading &&
                            controller.nextCursor == null &&
                            controller.posts.isNotEmpty)
                          const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text("You're all caught up",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: feedMuted, fontSize: 13))),
                      ],
                    )),
          ))),
    );
  }
}

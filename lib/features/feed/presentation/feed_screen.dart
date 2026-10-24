import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../../auth/presentation/auth_scope.dart';
import '../application/feed_controller.dart';
import '../data/feed_api.dart';
import '../domain/feed_models.dart';
import 'create_post_sheet.dart';
import 'feed_widgets.dart';
import 'people_screen.dart';
import 'post_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({this.repository, super.key});
  final FeedRepository? repository;
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  FeedController? _controller;
  FeedApi? _ownedApi;
  String? _userId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AuthScope.maybeOf(context);
    if (_userId == auth?.user?.id) return;
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _ownedApi?.close();
    _ownedApi = null;
    _controller = null;
    _userId = auth?.user?.id;
    if (_userId != null) {
      final repository = widget.repository ??
          (_ownedApi = FeedApi(token: () => auth?.sessionToken));
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
            repository: controller.repository, name: user.name));
    if (mounted && identical(controller, _controller) && post != null) {
      controller.created(post);
    }
  }

  Future<void> _people() async {
    final controller = _controller;
    if (controller == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PeopleScreen(repository: controller.repository)));
    if (mounted && identical(controller, _controller)) {
      await controller.refresh();
    }
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

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _ownedApi?.close();
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
            Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton.filledTonal(
                    key: const Key('feed_people'),
                    onPressed: _people,
                    tooltip: 'People and friend requests',
                    icon: const Icon(Icons.people_outline)))
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
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final filter in const {
                            'connections': 'Connections',
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
                          FeedNotice(
                              icon: Icons.waving_hand_outlined,
                              title: 'A fresh start for your feed',
                              message:
                                  'Share your first post or find people to connect with. Your posts always appear alongside this filter.',
                              action: OutlinedButton.icon(
                                  onPressed: _people,
                                  icon: const Icon(Icons.person_add_alt),
                                  label: const Text('Find people'))),
                        for (final post in controller.posts)
                          PostCard(
                              key: ValueKey(post.id),
                              post: post,
                              isOwn: post.authorId == _userId,
                              busy: controller.busyPosts.contains(post.id),
                              onDelete: () => _delete(post),
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

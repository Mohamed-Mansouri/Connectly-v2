import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../domain/feed_models.dart';
import 'feed_widgets.dart';
import 'post_image_view.dart';
import 'post_text_view.dart';

class PostCard extends StatelessWidget {
  const PostCard(
      {required this.post,
      required this.isOwn,
      required this.busy,
      required this.onReact,
      required this.onDelete,
      required this.onComment,
      required this.onShowReactors,
      this.onTag,
      this.onMention,
      this.highlight = const [],
      this.loadImage,
      this.onShare,
      super.key});
  final FeedPost post;
  final bool isOwn;
  final bool busy;
  final ValueChanged<String?> onReact;

  /// Null hides the delete option.
  final VoidCallback? onDelete;
  final VoidCallback onComment;
  final VoidCallback onShowReactors;
  final ValueChanged<String>? onTag;
  final ValueChanged<String>? onMention;
  final List<String> highlight;

  /// Loads a post's photo bytes (this post's or the reposted original's).
  final Future<Uint8List> Function(String postId)? loadImage;

  /// `repost` or `send`; null hides the Share button.
  final ValueChanged<String>? onShare;

  /// The post a Share action would send: the original for a repost.
  bool get _canShare => !post.isRepost || post.shared != null;

  Widget _original(FeedSharedPost? original) {
    if (original == null) {
      return Container(
        key: Key('repost_missing_${post.id}'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .12))),
        child: const Text('This post is no longer available.',
            style: TextStyle(color: feedMuted, fontStyle: FontStyle.italic)),
      );
    }
    return Container(
      key: Key('repost_original_${post.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .12))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox.square(
              dimension: 28,
              child: FittedBox(child: FeedAvatar(original.authorName))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(original.authorName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(postTime(original.createdAt),
              style: const TextStyle(color: feedMuted, fontSize: 12)),
        ]),
        if (original.body.isNotEmpty) ...[
          const SizedBox(height: 10),
          PostTextView(original.body,
              onTag: onTag, onMention: onMention, highlight: highlight),
        ],
        if (original.hasImage && loadImage != null) ...[
          const SizedBox(height: 10),
          PostImageView(
              postId: original.id,
              heroTag: 'repost_image_${post.id}',
              width: original.imageWidth!,
              height: original.imageHeight!,
              load: () => loadImage!(original.id)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: ConnectlyTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .05))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            FeedAvatar(post.authorName),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${post.authorName}${isOwn ? ' · You' : ''}',
                      style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  if (post.isRepost)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Row(children: [
                        Icon(Icons.repeat_rounded, size: 14, color: feedMuted),
                        SizedBox(width: 4),
                        Text('reposted',
                            style: TextStyle(color: feedMuted, fontSize: 12)),
                      ]),
                    ),
                  const SizedBox(height: 3),
                  Tooltip(
                      message: post.createdAt.toLocal().toString(),
                      child: Text(postTime(post.createdAt),
                          style:
                              const TextStyle(color: feedMuted, fontSize: 12))),
                ])),
            if (isOwn && onDelete != null)
              PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: 'Post options',
                  onSelected: (_) => onDelete!(),
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete post'))
                      ]),
          ]),
          const SizedBox(height: 18),
          if (post.body.isNotEmpty)
            PostTextView(post.body,
                onTag: onTag, onMention: onMention, highlight: highlight),
          if (post.hasImage && loadImage != null) ...[
            if (post.body.isNotEmpty) const SizedBox(height: 14),
            PostImageView(
                postId: post.id,
                width: post.imageWidth!,
                height: post.imageHeight!,
                load: () => loadImage!(post.id)),
          ],
          if (post.isRepost) ...[
            if (post.body.isNotEmpty) const SizedBox(height: 14),
            _original(post.shared),
          ],
          const SizedBox(height: 20),
          if (post.reactionCount > 0 ||
              post.commentCount > 0 ||
              post.shareCount > 0)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  if (post.reactionCount > 0)
                    Flexible(
                        child: InkWell(
                      key: Key('reactors_${post.id}'),
                      onTap: onShowReactors,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 2),
                        child: Semantics(
                          button: true,
                          label:
                              '${post.reactionCount} reactions. Show who reacted',
                          child: Wrap(spacing: 12, runSpacing: 8, children: [
                            for (final entry in post.reactions.entries
                                .where((e) => e.value > 0))
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(reactionIcons[entry.key],
                                    size: 16, color: ConnectlyTheme.yellow),
                                const SizedBox(width: 5),
                                Text('${entry.value}',
                                    style: const TextStyle(
                                        color: feedMuted, fontSize: 13)),
                              ]),
                          ]),
                        ),
                      ),
                    )),
                  const Spacer(),
                  if (post.commentCount > 0)
                    InkWell(
                      onTap: onComment,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 2),
                        child: Text(
                            '${post.commentCount} comment${post.commentCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                                color: feedMuted, fontSize: 13)),
                      ),
                    ),
                  if (post.shareCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                          '${post.shareCount} share${post.shareCount == 1 ? '' : 's'}',
                          key: Key('shares_${post.id}'),
                          style:
                              const TextStyle(color: feedMuted, fontSize: 13)),
                    ),
                ])),
          Divider(color: Colors.white.withValues(alpha: .08), height: 1),
          const SizedBox(height: 8),
          // Equal thirds on one line; labels shrink instead of wrapping on
          // narrow screens or with large text.
          Row(children: [
            Expanded(child: _reactButton()),
            Expanded(
              child: InkWell(
                key: Key('comment_${post.id}'),
                onTap: onComment,
                borderRadius: BorderRadius.circular(10),
                child: _action(
                    const Icon(Icons.mode_comment_outlined,
                        size: 20, color: feedMuted),
                    'Comment',
                    feedMuted),
              ),
            ),
            if (onShare != null && _canShare)
              Expanded(
                  child: PopupMenuButton<String>(
                key: Key('share_${post.id}'),
                enabled: !busy,
                tooltip: 'Share this post',
                onSelected: onShare,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      key: Key('share_repost'),
                      value: 'repost',
                      child: ListTile(
                          leading: Icon(Icons.repeat_rounded),
                          title: Text('Repost to my feed'))),
                  PopupMenuItem(
                      key: Key('share_send'),
                      value: 'send',
                      child: ListTile(
                          leading: Icon(Icons.send_outlined),
                          title: Text('Send to a friend'))),
                ],
                child: _action(
                    const Icon(Icons.share_outlined,
                        size: 20, color: feedMuted),
                    'Share',
                    feedMuted),
              )),
          ]),
        ]),
      );

  Widget _reactButton() => PopupMenuButton<String>(
        key: Key('react_${post.id}'),
        enabled: !busy,
        tooltip: 'Choose a reaction',
        onSelected: (kind) => onReact(kind == 'remove' ? null : kind),
        itemBuilder: (_) => [
          for (final entry in reactionLabels.entries)
            PopupMenuItem(
                value: entry.key,
                child: Row(children: [
                  Icon(reactionIcons[entry.key],
                      color: post.myReaction == entry.key
                          ? ConnectlyTheme.yellow
                          : null),
                  const SizedBox(width: 12),
                  Text(entry.value),
                ])),
          if (post.myReaction != null)
            const PopupMenuItem(
                value: 'remove', child: Text('Remove reaction')),
        ],
        child: _action(
            busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    reactionIcons[post.myReaction] ??
                        Icons.add_reaction_outlined,
                    size: 21,
                    color: post.myReaction == null
                        ? feedMuted
                        : ConnectlyTheme.yellow),
            reactionLabels[post.myReaction] ?? 'React',
            post.myReaction == null ? feedMuted : ConnectlyTheme.yellow),
      );

  /// Icon + label centred in its third of the action row.
  Widget _action(Widget icon, String label, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              icon,
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../domain/feed_models.dart';
import 'feed_widgets.dart';

class PostCard extends StatelessWidget {
  const PostCard(
      {required this.post,
      required this.isOwn,
      required this.busy,
      required this.onReact,
      required this.onDelete,
      required this.onComment,
      required this.onShowReactors,
      super.key});
  final FeedPost post;
  final bool isOwn;
  final bool busy;
  final ValueChanged<String?> onReact;
  final VoidCallback onDelete;
  final VoidCallback onComment;
  final VoidCallback onShowReactors;

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
                  const SizedBox(height: 3),
                  Tooltip(
                      message: post.createdAt.toLocal().toString(),
                      child: Text(postTime(post.createdAt),
                          style:
                              const TextStyle(color: feedMuted, fontSize: 12))),
                ])),
            if (isOwn)
              PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: 'Post options',
                  onSelected: (_) => onDelete(),
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete post'))
                      ]),
          ]),
          const SizedBox(height: 18),
          SelectableText(post.body,
              style: const TextStyle(fontSize: 16, height: 1.55)),
          const SizedBox(height: 20),
          if (post.reactionCount > 0 || post.commentCount > 0)
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
                ])),
          Divider(color: Colors.white.withValues(alpha: .08), height: 1),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 4, children: [
            _reactButton(),
            TextButton.icon(
              key: Key('comment_${post.id}'),
              onPressed: onComment,
              style: TextButton.styleFrom(foregroundColor: feedMuted),
              icon: const Icon(Icons.mode_comment_outlined, size: 20),
              label: const Text('Comment',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
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
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (busy)
                const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(
                    reactionIcons[post.myReaction] ??
                        Icons.add_reaction_outlined,
                    size: 21,
                    color: post.myReaction == null
                        ? feedMuted
                        : ConnectlyTheme.yellow),
              const SizedBox(width: 8),
              Text(reactionLabels[post.myReaction] ?? 'React',
                  style: TextStyle(
                      color: post.myReaction == null
                          ? feedMuted
                          : ConnectlyTheme.yellow,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 18, color: feedMuted),
            ])),
      );
}

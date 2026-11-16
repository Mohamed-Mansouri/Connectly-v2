import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../../messaging/domain/messaging_models.dart';
import '../application/feed_controller.dart';
import '../domain/feed_models.dart';
import 'feed_widgets.dart';
import 'suggestion_bar.dart';

/// The original post a share refers to (a repost shares its original).
({String id, String author, String body}) shareTarget(FeedPost post) =>
    post.shared == null
        ? (id: post.id, author: post.authorName, body: post.body)
        : (
            id: post.shared!.id,
            author: post.shared!.authorName,
            body: post.shared!.body
          );

Widget _preview(FeedPost post) {
  final target = shareTarget(post);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .12))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(target.author, style: const TextStyle(fontWeight: FontWeight.w700)),
      if (target.body.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(target.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: feedMuted, height: 1.4)),
      ],
    ]),
  );
}

/// Repost with an optional comment. Pops with the new [FeedPost].
class RepostSheet extends StatefulWidget {
  const RepostSheet({required this.repository, required this.post, super.key});
  final FeedRepository repository;
  final FeedPost post;
  @override
  State<RepostSheet> createState() => _RepostSheetState();
}

class _RepostSheetState extends State<RepostSheet> {
  final _comment = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final post = await widget.repository
          .repost(shareTarget(widget.post).id, _comment.text);
      if (mounted) Navigator.of(context).pop(post);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = FeedController.message(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Repost',
                      style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('repost_comment'),
                    controller: _comment,
                    enabled: !_busy,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 3000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        hintText: 'Say something about this (optional)',
                        counterText: ''),
                  ),
                  SuggestionBar(
                      controller: _comment, repository: widget.repository),
                  const SizedBox(height: 12),
                  _preview(widget.post),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('repost_submit'),
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                          backgroundColor: ConnectlyTheme.yellow,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.all(16)),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.repeat_rounded),
                      label: Text(_busy ? 'Reposting…' : 'Repost'),
                    ),
                  ),
                ]),
          ),
        ),
      );
}

/// Lists your friends; tapping one sends the post in your direct chat.
/// Pops with the friend's name once sent.
class SendToFriendSheet extends StatefulWidget {
  const SendToFriendSheet(
      {required this.messaging, required this.post, super.key});
  final MessagingRepository messaging;
  final FeedPost post;
  @override
  State<SendToFriendSheet> createState() => _SendToFriendSheetState();
}

class _SendToFriendSheetState extends State<SendToFriendSheet> {
  late final Future<List<ChatPerson>> _friends = widget.messaging.friends();
  String? _sending;
  String? _error;

  Future<void> _send(ChatPerson friend) async {
    setState(() {
      _sending = friend.id;
      _error = null;
    });
    try {
      final chat =
          await widget.messaging.create(kind: 'direct', memberIds: [friend.id]);
      await widget.messaging.sendPost(chat.id, shareTarget(widget.post).id);
      if (mounted) Navigator.of(context).pop(friend.name);
    } on MessagingException catch (error) {
      if (mounted) {
        setState(() {
          _sending = null;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = null;
          _error = 'Could not send the post. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Send to a friend',
                    style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _preview(widget.post),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Flexible(
              child: FutureBuilder<List<ChatPerson>>(
                future: _friends,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Could not load your friends.',
                            style: TextStyle(color: feedMuted)));
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  final friends = snapshot.data!;
                  if (friends.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'You have no friends to send to yet. '
                            'Add friends in the People tab.',
                            style: TextStyle(color: feedMuted)));
                  }
                  return ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final friend in friends)
                        ListTile(
                          key: Key('send_to_${friend.id}'),
                          enabled: _sending == null,
                          leading: FeedAvatar(friend.name),
                          title: Text(friend.name),
                          trailing: _sending == friend.id
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send_outlined,
                                  color: ConnectlyTheme.yellow),
                          onTap: () => _send(friend),
                        ),
                    ],
                  );
                },
              ),
            ),
          ]),
        ),
      );
}

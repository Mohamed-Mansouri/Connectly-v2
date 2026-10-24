import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import '../application/feed_controller.dart';
import '../domain/feed_models.dart';
import 'feed_widgets.dart';

class CreatePostSheet extends StatefulWidget {
  const CreatePostSheet(
      {required this.repository, required this.name, super.key});
  final FeedRepository repository;
  final String name;
  @override
  State<CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<CreatePostSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _publish() async {
    final body = _text.text.trim();
    if (_busy || body.isEmpty || body.length > 3000) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final post = await widget.repository.create(body);
      if (mounted) Navigator.of(context).pop(post);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = FeedController.message(error);
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: SafeArea(
            child: Padding(
          padding: EdgeInsets.fromLTRB(
              24, 12, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  const Expanded(
                      child: Text('Create a post',
                          style: TextStyle(
                              fontFamily: 'Urbanist',
                              fontSize: 24,
                              fontWeight: FontWeight.w700))),
                  IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  FeedAvatar(widget.name),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(widget.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const Text('For friends and people following you',
                            style: TextStyle(color: feedMuted, fontSize: 12)),
                      ])),
                ]),
                const SizedBox(height: 20),
                TextField(
                    key: const Key('post_body'),
                    controller: _text,
                    autofocus: true,
                    enabled: !_busy,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 3000,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        hintText: "What's on your mind?",
                        border: InputBorder.none),
                    style: const TextStyle(fontSize: 17, height: 1.5)),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('publish_post'),
                      onPressed:
                          _busy || _text.text.trim().isEmpty ? null : _publish,
                      style: FilledButton.styleFrom(
                          backgroundColor: ConnectlyTheme.yellow,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.all(16)),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 19),
                      label: Text(_busy ? 'Sharing…' : 'Share post'),
                    )),
              ])),
        )),
      );
}

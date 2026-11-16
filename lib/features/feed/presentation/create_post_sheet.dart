import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/connectly_theme.dart';
import '../../../shared/presentation/photo_crop_screen.dart';
import '../application/feed_controller.dart';
import '../domain/feed_models.dart';
import 'feed_widgets.dart';
import 'suggestion_bar.dart';

class CreatePostSheet extends StatefulWidget {
  const CreatePostSheet(
      {required this.repository,
      required this.name,
      this.pickImage,
      super.key});
  final FeedRepository repository;
  final String name;

  /// Replaces the system photo picker (used by tests).
  final Future<Uint8List?> Function(ImageSource source)? pickImage;
  @override
  State<CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<CreatePostSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  bool _preparing = false;
  String? _error;

  /// The picked photo before cropping, and the processed one to publish.
  Uint8List? _original;
  PostPhoto? _photo;

  Future<Uint8List?> _pick(ImageSource source) async {
    if (widget.pickImage != null) return widget.pickImage!(source);
    final picked = await ImagePicker().pickImage(
        source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 92);
    return picked?.readAsBytes();
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: ConnectlyTheme.navy,
        showDragHandle: true,
        builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    key: const Key('photo_source_gallery'),
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Choose from gallery'),
                    onTap: () => Navigator.pop(context, ImageSource.gallery)),
                ListTile(
                    key: const Key('photo_source_camera'),
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: const Text('Take a photo'),
                    onTap: () => Navigator.pop(context, ImageSource.camera)),
              ]),
            ));
    if (source == null || !mounted) return;
    try {
      final bytes = await _pick(source);
      if (bytes == null || !mounted) return;
      _original = bytes;
      await _prepare(bytes);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open this photo.');
    }
  }

  /// Resizes in a background isolate (longest side 1280 px, JPEG).
  Future<void> _prepare(Uint8List bytes) async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final photo = await compute(resizePostPhoto, bytes);
      if (mounted) setState(() => _photo = photo);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open this photo.');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _crop() async {
    final original = _original;
    if (original == null) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => PhotoCropScreen(image: original, circle: false)));
    if (cropped != null && mounted) await _prepare(cropped);
  }

  Widget _preview() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(children: [
            // Fixed height so the layout does not jump while decoding.
            SizedBox(
              height: 220,
              width: double.infinity,
              child: Image.memory(_photo!.bytes,
                  key: const Key('post_photo_preview'),
                  fit: BoxFit.cover,
                  cacheWidth: 900),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton.filledTonal(
                    key: const Key('post_crop_photo'),
                    tooltip: 'Crop or rotate photo',
                    onPressed: _busy ? null : _crop,
                    icon: const Icon(Icons.crop)),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                    key: const Key('post_remove_photo'),
                    tooltip: 'Remove photo',
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _photo = null;
                              _original = null;
                            }),
                    icon: const Icon(Icons.close)),
              ]),
            ),
          ]),
        ),
      );

  Future<void> _publish() async {
    final body = _text.text.trim();
    if (_busy || _preparing || body.length > 3000) return;
    if (body.isEmpty && _photo == null) return;
    final photo = _photo;
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final post = await widget.repository.create(body,
          image: photo == null
              ? null
              : FeedImageUpload(
                  bytes: photo.bytes,
                  width: photo.width,
                  height: photo.height));
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
                    decoration: InputDecoration(
                        hintText: _photo == null
                            ? "What's on your mind?"
                            : 'Write a caption (optional)…',
                        border: InputBorder.none),
                    style: const TextStyle(fontSize: 17, height: 1.5)),
                SuggestionBar(controller: _text, repository: widget.repository),
                const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                        'Add #tags so people can find your post, '
                        'or type @ to mention someone.',
                        style: TextStyle(color: feedMuted, fontSize: 12))),
                if (_preparing)
                  const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator()),
                if (_photo != null) _preview(),
                if (_photo == null && !_preparing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                        key: const Key('post_add_photo'),
                        onPressed: _busy ? null : _choosePhoto,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add photo')),
                  ),
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
                      onPressed: _busy ||
                              _preparing ||
                              (_text.text.trim().isEmpty && _photo == null)
                          ? null
                          : _publish,
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

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../app/connectly_theme.dart';
import 'feed_widgets.dart';

/// A post photo. Space is reserved from the stored width/height so the list
/// does not jump; bytes are loaded lazily. Tapping opens a zoomable viewer.
class PostImageView extends StatefulWidget {
  const PostImageView(
      {required this.postId,
      required this.width,
      required this.height,
      required this.load,
      this.heroTag,
      super.key});
  final String postId;

  /// Must be unique on screen (a post and its repost can both be visible).
  final String? heroTag;
  final int width;
  final int height;
  final Future<Uint8List> Function() load;
  @override
  State<PostImageView> createState() => _PostImageViewState();
}

class _PostImageViewState extends State<PostImageView> {
  late Future<Uint8List> _bytes = widget.load();
  String get _hero => widget.heroTag ?? 'post_image_${widget.postId}';

  @override
  void didUpdateWidget(PostImageView old) {
    super.didUpdateWidget(old);
    if (old.postId != widget.postId) _bytes = widget.load();
  }

  void _open(Uint8List bytes) =>
      Navigator.of(context).push(PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black,
          pageBuilder: (_, __, ___) =>
              PostPhotoViewer(bytes: bytes, heroTag: _hero),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child)));

  @override
  Widget build(BuildContext context) {
    // Very tall or wide photos are shown cropped; the viewer shows all of it.
    final ratio = (widget.width / widget.height).clamp(.8, 1.9);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: ratio,
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Container(
                color: ConnectlyTheme.navy,
                alignment: Alignment.center,
                child: TextButton.icon(
                    onPressed: () => setState(() => _bytes = widget.load()),
                    icon: const Icon(Icons.broken_image_outlined),
                    label: const Text('Photo unavailable. Retry')),
              );
            }
            if (!snapshot.hasData) {
              return Container(
                  color: ConnectlyTheme.navy,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_outlined,
                      color: feedMuted, size: 36));
            }
            return Semantics(
              image: true,
              button: true,
              label: 'Post photo. Open full screen',
              child: GestureDetector(
                key: Key('post_image_${widget.postId}'),
                onTap: () => _open(snapshot.data!),
                child: Hero(
                  tag: _hero,
                  child: Image.memory(snapshot.data!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // Decode at display size to save memory.
                      cacheWidth: 1080),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Full-screen photo with pinch-to-zoom.
class PostPhotoViewer extends StatelessWidget {
  const PostPhotoViewer(
      {required this.bytes, required this.heroTag, super.key});
  final Uint8List bytes;
  final String heroTag;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            leading: IconButton(
                key: const Key('photo_viewer_close'),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close))),
        extendBodyBehindAppBar: true,
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: Hero(tag: heroTag, child: Image.memory(bytes))),
        ),
      );
}

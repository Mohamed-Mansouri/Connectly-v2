import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Side length, in pixels, of every saved profile photo.
const profilePhotoSize = 512;

/// Resizes a cropped square to [profilePhotoSize] and re-encodes it as JPEG.
/// Runs in a background isolate through [compute].
Uint8List resizeProfilePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image.');
  final square = decoded.width == decoded.height
      ? decoded
      : img.copyResizeCropSquare(decoded,
          size:
              decoded.width < decoded.height ? decoded.width : decoded.height);
  final sized = square.width > profilePhotoSize
      ? img.copyResize(square,
          width: profilePhotoSize,
          height: profilePhotoSize,
          interpolation: img.Interpolation.cubic)
      : square;
  return Uint8List.fromList(img.encodeJpg(sized, quality: 85));
}

/// Longest side, in pixels, of a photo attached to a post.
const postPhotoMaxSide = 1280;

/// A processed post photo and its size (used to reserve space while loading).
typedef PostPhoto = ({Uint8List bytes, int width, int height});

/// Shrinks a post photo so its longest side is at most [postPhotoMaxSide]
/// and re-encodes it as JPEG. Runs in a background isolate.
PostPhoto resizePostPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image.');
  final longest =
      decoded.width > decoded.height ? decoded.width : decoded.height;
  final sized = longest > postPhotoMaxSide
      ? (decoded.width >= decoded.height
          ? img.copyResize(decoded,
              width: postPhotoMaxSide, interpolation: img.Interpolation.cubic)
          : img.copyResize(decoded,
              height: postPhotoMaxSide, interpolation: img.Interpolation.cubic))
      : decoded;
  return (
    bytes: Uint8List.fromList(img.encodeJpg(sized, quality: 82)),
    width: sized.width,
    height: sized.height
  );
}

/// Rotates an image a quarter turn clockwise (JPEG output).
Uint8List rotatePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image.');
  return Uint8List.fromList(
      img.encodeJpg(img.copyRotate(decoded, angle: 90), quality: 92));
}

/// Crop and rotate a photo. Returns the cropped (not yet resized) image, or
/// null if cancelled.
///
/// * [circle] (profile): move and zoom the photo under a fixed circle.
/// * free (posts): drag the corners of a rectangle of any shape.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({required this.image, this.circle = true, super.key});
  final Uint8List image;
  final bool circle;
  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final _crop = CropController();
  late Uint8List _image = widget.image;
  bool _ready = false;
  bool _busy = false;

  Future<void> _rotate() async {
    setState(() => _busy = true);
    try {
      final rotated = await compute(rotatePhoto, _image);
      if (!mounted) return;
      setState(() {
        _image = rotated;
        _ready = false;
      });
      _crop.image = rotated;
    } catch (_) {
      _fail();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    setState(() => _busy = true);
    _crop.crop();
  }

  Future<void> _cropped(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        try {
          final photo = widget.circle
              ? await compute(resizeProfilePhoto, croppedImage)
              : croppedImage;
          if (mounted) Navigator.of(context).pop(photo);
        } catch (_) {
          _fail();
        }
      case CropFailure():
        _fail();
    }
  }

  void _fail() {
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not edit this photo. Try another one.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Crop photo'),
          actions: [
            IconButton(
                key: const Key('crop_rotate'),
                tooltip: 'Rotate',
                onPressed: _busy || !_ready ? null : _rotate,
                icon: const Icon(Icons.rotate_90_degrees_cw_outlined)),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Stack(children: [
                Crop(
                  image: _image,
                  controller: _crop,
                  withCircleUi: widget.circle,
                  interactive: widget.circle,
                  fixCropRect: widget.circle,
                  initialRectBuilder: widget.circle
                      ? null
                      : InitialRectBuilder.withSizeAndRatio(size: 1),
                  baseColor: Colors.black,
                  maskColor: Colors.black.withValues(alpha: .6),
                  onStatusChanged: (status) {
                    if (mounted) {
                      setState(() => _ready = status == CropStatus.ready);
                    }
                  },
                  onCropped: _cropped,
                ),
                if (_busy || !_ready)
                  const Center(child: CircularProgressIndicator()),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                  widget.circle
                      ? 'Pinch to zoom and drag to place your face in the circle.'
                      : 'Drag the corners to keep the part you want.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      key: const Key('crop_done'),
                      onPressed: _busy || !_ready ? null : _done,
                      child: const Text('Use photo')),
                ),
              ]),
            ),
          ]),
        ),
      );
}

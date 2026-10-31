import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../shared/data/local_database.dart';
import '../domain/messaging_models.dart';

class VoiceClip {
  const VoiceClip(this.bytes, this.durationMs);
  final Uint8List bytes;
  final int durationMs;
}

abstract class VoiceRecorder {
  Future<void> start();
  Future<VoiceClip> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class DeviceVoiceRecorder implements VoiceRecorder {
  DeviceVoiceRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;
  DateTime? _startedAt;

  @override
  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw const MessagingException(
          'Allow microphone access to record a voice message.');
    }
    final temporary = await getTemporaryDirectory();
    final target = path.join(temporary.path, 'connectly-${localId()}.m4a');
    await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 32000,
            sampleRate: 24000,
            numChannels: 1),
        path: target);
    _path = target;
    _startedAt = DateTime.now();
  }

  @override
  Future<VoiceClip> stop() async {
    final target = _path;
    final startedAt = _startedAt;
    if (target == null || startedAt == null) {
      throw const MessagingException(
          'Start recording before sending a voice message.');
    }
    _path = null;
    _startedAt = null;
    try {
      final recordedPath = await _recorder.stop();
      if (recordedPath == null) {
        throw const MessagingException('Could not finish the recording.');
      }
      final bytes = await File(recordedPath).readAsBytes();
      final durationMs = DateTime.now().difference(startedAt).inMilliseconds;
      if (bytes.isEmpty || bytes.length > 2000000 || durationMs > 120000) {
        throw const MessagingException(
            'Voice messages must be shorter than two minutes and 2 MB.');
      }
      return VoiceClip(bytes, durationMs.clamp(1, 120000));
    } finally {
      final file = File(target);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> cancel() async {
    final target = _path;
    _path = null;
    _startedAt = null;
    await _recorder.cancel();
    if (target != null) {
      final file = File(target);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> dispose() async {
    if (_path != null) await cancel();
    await _recorder.dispose();
  }
}

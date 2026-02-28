import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../runtime/audio_capture_gateway.dart';
import '../runtime/audio_frame_stream.dart';

/// [AudioCaptureGateway] backed by the `record` package.
///
/// Streams PCM16 / 16 kHz / mono frames via [AudioRecorder.startStream].
/// Each [start] call creates a fresh stream subscription; [stop] cancels it.
final class PlatformAudioCaptureGateway implements AudioCaptureGateway {
  final AudioRecorder _recorder = AudioRecorder();

  StreamController<Uint8List>? _framesController;
  StreamSubscription<Uint8List>? _recordSub;
  bool _isActive = false;

  @override
  AudioFrameStream get audioFrames =>
      _framesController?.stream ?? const Stream.empty();

  @override
  bool get isActive => _isActive;

  @override
  Future<bool> start() async {
    try {
      _framesController ??= StreamController<Uint8List>.broadcast();
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _recordSub = stream.listen((bytes) {
        if (!(_framesController?.isClosed ?? true)) {
          _framesController!.add(bytes);
        }
      });
      _isActive = true;
      return true;
    } catch (_) {
      _isActive = false;
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _isActive = false;
    await _recordSub?.cancel();
    _recordSub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  void dispose() {
    _isActive = false;
    _recordSub?.cancel();
    _framesController?.close();
    _framesController = null;
    _recorder.dispose();
  }
}

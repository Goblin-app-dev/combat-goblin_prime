import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../runtime/audio_capture_gateway.dart';
import '../runtime/audio_frame_stream.dart';

/// [AudioCaptureGateway] backed by the `record` package.
///
/// Streams PCM16 / 16 kHz / mono frames via [AudioRecorder.startStream].
/// [start] is idempotent — recorder starts once and stays running (warm mic).
/// [stop] ends a capture session but does not stop the recorder so that a
/// [WakeWordDetector] can continue receiving frames between sessions.
/// Full teardown occurs only in [dispose].
final class PlatformAudioCaptureGateway implements AudioCaptureGateway {
  final AudioRecorder _recorder = AudioRecorder();

  StreamController<Uint8List>? _framesController;
  StreamSubscription<Uint8List>? _recordSub;
  bool _isActive = false;
  bool _disposed = false;

  @override
  AudioFrameStream get audioFrames =>
      _framesController?.stream ?? const Stream.empty();

  @override
  bool get isActive => _isActive;

  @override
  Future<bool> start() async {
    if (_disposed) return false;
    if (_recordSub != null) {
      // Recorder is already streaming (e.g., started by WakeWordDetector).
      // Re-use the existing broadcast stream; do not open a second session.
      // TODO(12E): make this policy-driven so PTT-only mode can stop recorder
      // on stop() to conserve battery/privacy when wake word is disabled.
      _isActive = true;
      return true;
    }
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
    // Session-stop only. The recorder intentionally stays running so
    // WakeWordDetector continues to receive frames between sessions.
    // Full teardown (recorder stop + subscription cancel) is in dispose().
    _isActive = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _isActive = false;
    _recordSub?.cancel();
    _recordSub = null;
    _framesController?.close();
    _framesController = null;
    _recorder.dispose();
  }
}

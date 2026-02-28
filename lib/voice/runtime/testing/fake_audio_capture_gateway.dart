import 'dart:async';
import 'dart:typed_data';

import 'package:combat_goblin_prime/voice/runtime/audio_capture_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/audio_frame_stream.dart';

/// Configurable fake [AudioCaptureGateway] for tests and non-mobile platforms.
///
/// - [pushFrame] injects frames into [audioFrames] while [isActive].
/// - [startCallCount] / [stopCallCount] let tests assert call counts.
/// - [allowStart] controls whether [start] returns `true`.
final class FakeAudioCaptureGateway implements AudioCaptureGateway {
  /// Whether [start] succeeds. Defaults to `true`.
  final bool allowStart;

  FakeAudioCaptureGateway({this.allowStart = true});

  // sync: true so pushFrame delivers frames immediately (no microtask delay),
  // matching the test contract: frame is visible to the listener before the
  // next call returns.
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast(sync: true);

  bool _isActive = false;

  /// Number of times [start] was called.
  int startCallCount = 0;

  /// Number of times [stop] was called.
  int stopCallCount = 0;

  @override
  AudioFrameStream get audioFrames => _frames.stream;

  @override
  bool get isActive => _isActive;

  /// Injects [frame] into [audioFrames].
  ///
  /// Silently dropped if [isActive] is false, matching the session guard
  /// contract: frames from a previous session are ignored.
  void pushFrame(Uint8List frame) {
    if (_isActive && !_frames.isClosed) _frames.add(frame);
  }

  @override
  Future<bool> start() async {
    startCallCount++;
    _isActive = allowStart;
    return allowStart;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    _isActive = false;
  }

  @override
  void dispose() {
    _isActive = false;
    _frames.close();
  }
}

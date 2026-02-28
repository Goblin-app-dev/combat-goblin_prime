import 'audio_frame_stream.dart';

/// Injectable boundary for raw microphone capture.
///
/// Produces a canonical [AudioFrameStream] (PCM16 / 16 kHz / mono) that the
/// controller subscribes to during [ListeningState]. Real platform adapter
/// ([PlatformAudioCaptureGateway]) is provided in Phase 12C. Tests use
/// [FakeAudioCaptureGateway].
///
/// ## Canonical audio format (locked Phase 12C)
/// - PCM 16-bit signed little-endian
/// - 16 000 Hz sample rate
/// - 1 channel (mono)
/// - Frames delivered as [Uint8List] chunks of any size
///
/// ## Platform responsibility
/// All resampling and channel-mixing happen inside the adapter implementation,
/// never inside [VoiceRuntimeController].
abstract interface class AudioCaptureGateway {
  /// Stream of raw audio frames in canonical format.
  ///
  /// The stream is a broadcast stream; multiple subscribers are allowed.
  /// Frames are only delivered while [isActive] is `true`.
  AudioFrameStream get audioFrames;

  /// Whether the gateway is currently capturing.
  bool get isActive;

  /// Requests mic capture to begin.
  ///
  /// Returns `true` if capture started successfully, `false` otherwise
  /// (e.g. mic hardware unavailable, platform unsupported). The caller
  /// should treat `false` as a session error.
  Future<bool> start();

  /// Stops capture and closes the current frame sequence.
  ///
  /// No-op if not currently capturing. After [stop], [isActive] becomes
  /// `false` but [audioFrames] remains valid for future [start] calls.
  Future<void> stop();

  /// Release all native resources. Must be called when the gateway is no
  /// longer needed (typically from [VoiceRuntimeController.dispose]).
  void dispose();
}

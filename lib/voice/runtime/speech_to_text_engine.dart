import 'dart:typed_data';

import '../models/text_candidate.dart';

/// Injectable boundary for speech-to-text transcription.
///
/// Accepts a buffered PCM16 / 16 kHz / mono audio blob and returns a
/// [TextCandidate]. The engine does not manage mic access — audio collection
/// is the responsibility of [AudioCaptureGateway].
///
/// ## Determinism contract
/// - Given the same [pcm] bytes, the same engine version, and the same
///   configuration, [transcribe] must return the same [TextCandidate.text]
///   (Skill 10).
/// - [contextHints] may influence the output (ASR vocabulary bias) but the
///   result must still be deterministic for a given (pcm, contextHints) pair.
/// - The returned [TextCandidate.sessionId], [TextCandidate.mode], and
///   [TextCandidate.trigger] fields are filled with placeholder values (0 /
///   defaults) by the engine. [VoiceRuntimeController] replaces them with the
///   correct session context after receiving the result.
///
/// ## Implementations in Phase 12C
/// - [OfflineSpeechToTextEngine] — Sherpa ONNX offline ASR (bundled assets).
/// - [OnlineSpeechToTextEngine] — stub that throws [UnsupportedError] until
///   Phase 12D.
abstract interface class SpeechToTextEngine {
  /// Transcribes [pcm] audio to text.
  ///
  /// [pcm] must be PCM16 / 16 kHz / mono (canonical format).
  /// [contextHints] is an ordered list of domain terms (faction names, unit
  /// keys) used to bias the engine vocabulary. Ignored if unsupported.
  ///
  /// Throws on unrecoverable engine error. [VoiceRuntimeController] catches
  /// any exception and transitions to [ErrorState(VoiceStopReason.sttFailed)].
  Future<TextCandidate> transcribe(
    Uint8List pcm, {
    required List<String> contextHints,
  });
}

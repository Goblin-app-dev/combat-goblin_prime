import '../runtime/voice_listen_mode.dart';
import '../runtime/voice_listen_trigger.dart';

/// The output of a speech-to-text session.
///
/// Produced by [SpeechToTextEngine.transcribe] and enriched by
/// [VoiceRuntimeController] with session context before being emitted as a
/// [TextCandidateProducedEvent] and delivered to the [onTextCandidate] callback.
///
/// ## Determinism contract
/// - No timestamps are stored here.
/// - Given the same audio input and the same STT engine, the same
///   [TextCandidate] is produced on every run (Skill 10).
/// - [isFinal] is always `true` in Phase 12C (streaming transcription deferred
///   to Phase 12D+).
final class TextCandidate {
  /// Transcribed text as returned by the STT engine (un-canonicalized).
  ///
  /// Empty string if the engine produced no speech. Never null.
  final String text;

  /// Engine confidence in [0.0, 1.0], or `-1.0` if the engine did not report
  /// a confidence score.
  final double confidence;

  /// Always `true` in Phase 12C (streaming incremental results deferred).
  final bool isFinal;

  /// Session counter value at the moment this candidate was produced.
  ///
  /// Matches the [VoiceRuntimeState.sessionId] of the session that produced the
  /// audio. Use for log correlation and stale-result detection.
  final int sessionId;

  /// Interaction mode that was active during the session.
  final VoiceListenMode mode;

  /// What triggered the session that produced this candidate.
  final VoiceListenTrigger trigger;

  const TextCandidate({
    required this.text,
    required this.confidence,
    required this.isFinal,
    required this.sessionId,
    required this.mode,
    required this.trigger,
  });

  @override
  String toString() =>
      'TextCandidate(text: "$text", confidence: $confidence, '
      'sessionId: $sessionId, mode: ${mode.name}, trigger: ${trigger.name})';
}

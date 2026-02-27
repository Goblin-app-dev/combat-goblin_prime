/// Who or what originated a [VoiceRuntimeController.beginListening] call.
///
/// Recorded in [ArmingState], [ListeningState], and [ListeningBegan] events
/// for diagnostics and log explainability (Skill 11).
enum VoiceListenTrigger {
  /// A push-to-talk button or gesture initiated listening.
  pushToTalk,

  /// A [WakeWordDetector] wake event initiated listening.
  wakeWord,
}

/// Data class carrying information about a detected wake phrase.
///
/// Does not carry timestamps — deterministic contract (Skill 10).
class WakeEvent {
  /// The phrase that was detected (e.g. "hey goblin").
  final String phrase;

  /// Optional model confidence score in [0.0, 1.0].
  final double? confidence;

  const WakeEvent({required this.phrase, this.confidence});
}

/// Plug point for wake-word detection engines.
///
/// In Phase 12B this interface has no real implementation — only a
/// [FakeWakeWordDetector] is provided for testing and UI wiring.
/// Sherpa ONNX keyword spotting is plugged in Phase 12C.
///
/// The controller subscribes to [wakeEvents] on construction and
/// unsubscribes on [dispose].
abstract interface class WakeWordDetector {
  /// Broadcast stream of detected wake events.
  Stream<WakeEvent> get wakeEvents;

  /// Release resources. Called by [VoiceRuntimeController.dispose].
  void dispose();
}

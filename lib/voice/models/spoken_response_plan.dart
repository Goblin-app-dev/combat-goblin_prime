import 'spoken_entity.dart';

/// Structured output from [VoiceAssistantCoordinator.handleTranscript].
///
/// Contains everything the UI (and later TTS in Phase 12E) needs to present
/// the assistant's response for a single voice turn.
///
/// **Invariants:**
/// - [primaryText] is never empty.
/// - [entities] may be empty (e.g. "No matches").
/// - [selectedIndex] is non-null only when a [VoiceSelectionSession] is active;
///   always a valid index into [entities] when present.
/// - [debugSummary] contains no timestamps; safe for deterministic test assertions.
final class SpokenResponsePlan {
  /// Text to display at the top of the results area and speak (Phase 12E+).
  final String primaryText;

  /// Ranked entity candidates. Empty when no search was run or no results found.
  final List<SpokenEntity> entities;

  /// Index of the currently highlighted entity, or null if no session is active.
  final int? selectedIndex;

  /// Suggested spoken follow-up commands (e.g. ['next', 'select', 'cancel']).
  final List<String> followUps;

  /// Deterministic summary for logging and test assertions. Never timestamps.
  final String debugSummary;

  const SpokenResponsePlan({
    required this.primaryText,
    required this.entities,
    required this.followUps,
    required this.debugSummary,
    this.selectedIndex,
  });
}

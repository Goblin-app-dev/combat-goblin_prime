import 'spoken_entity.dart';

/// Structured output from [VoiceAssistantCoordinator.handleTranscript].
///
/// Contains everything the UI (and later TTS in Phase 12E) needs to present
/// the assistant's response for a single voice turn.
///
/// **Invariants (enforced at construction; asserted in debug mode):**
/// - [primaryText] is never empty.
/// - [entities] may be empty (e.g. "No matches").
/// - [selectedIndex] is non-null only when a [VoiceSelectionSession] is active;
///   always a valid index into [entities] when present.
/// - [debugSummary] contains no timestamps; safe for deterministic test assertions.
///
/// **Immutability:**
/// [entities] and [followUps] are defensively copied and wrapped in an
/// unmodifiable view at construction time. The plan is a stable snapshot safe
/// for concurrent UI rendering and TTS playback.
final class SpokenResponsePlan {
  /// Text to display at the top of the results area and speak (Phase 12E+).
  final String primaryText;

  /// Ranked entity candidates. Empty when no search was run or no results found.
  /// Always an unmodifiable view; never shares the caller's list reference.
  final List<SpokenEntity> entities;

  /// Index of the currently highlighted entity, or null if no session is active.
  final int? selectedIndex;

  /// Suggested spoken follow-up commands (e.g. ['next', 'select', 'cancel']).
  /// Always an unmodifiable view; never shares the caller's list reference.
  final List<String> followUps;

  /// Deterministic summary for logging and test assertions. Never timestamps.
  final String debugSummary;

  SpokenResponsePlan({
    required String primaryText,
    required List<SpokenEntity> entities,
    required List<String> followUps,
    required this.debugSummary,
    this.selectedIndex,
  })  : primaryText = primaryText,
        entities = List.unmodifiable(List.of(entities)),
        followUps = List.unmodifiable(List.of(followUps)) {
    assert(primaryText.trim().isNotEmpty, 'SpokenResponsePlan: primaryText must not be empty');
    final idx = selectedIndex;
    assert(
      idx == null ||
          (this.entities.isNotEmpty && idx >= 0 && idx < this.entities.length),
      'SpokenResponsePlan: selectedIndex $idx out of bounds '
      'for ${this.entities.length} entities',
    );
  }
}

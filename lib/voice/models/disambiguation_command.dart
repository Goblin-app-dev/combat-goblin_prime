/// Commands recognized during an active [VoiceSelectionSession].
///
/// Matched deterministically by [VoiceIntentClassifier]: trim + lowercase.
/// Multiple surface forms map to the same command (e.g. "back" → [previous]).
enum DisambiguationCommand {
  /// Move to the next entity. Clamped at last entity (no wrap).
  next,

  /// Move to the previous entity. Clamped at first entity (no wrap).
  previous,

  /// Confirm the currently highlighted entity.
  select,

  /// Abort the disambiguation session; return to idle.
  cancel,
}

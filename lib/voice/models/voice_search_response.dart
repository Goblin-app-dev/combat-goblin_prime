import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

import 'spoken_entity.dart';

/// The complete response from [VoiceSearchFacade.searchText].
///
/// Invariants:
/// - [entities] is deterministically ordered: slotId → groupKey →
///   first variant tieBreakKey.
/// - [spokenSummary] is a pure function of [entities]; no timestamps,
///   no relative dates, no randomness.
class VoiceSearchResponse {
  /// Deterministically ordered, grouped entities.
  final List<SpokenEntity> entities;

  final List<SearchDiagnostic> diagnostics;

  /// Short stable text summary. Pure function of [entities].
  final String spokenSummary;

  const VoiceSearchResponse({
    required this.entities,
    required this.diagnostics,
    required this.spokenSummary,
  });

  static const empty = VoiceSearchResponse(
    entities: [],
    diagnostics: [],
    spokenSummary: '',
  );
}

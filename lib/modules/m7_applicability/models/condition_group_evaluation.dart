import 'applicability_result.dart';
import 'condition_evaluation.dart';

/// Result of evaluating a `<conditionGroup type="and|or">`.
///
/// Group logic (unknown-aware):
///
/// **AND group:**
/// - If any child is [ApplicabilityState.skipped] → group [ApplicabilityState.skipped]
/// - Else if any child is [ApplicabilityState.unknown] → group [ApplicabilityState.unknown]
/// - Else → [ApplicabilityState.applies]
///
/// **OR group:**
/// - If any child is [ApplicabilityState.applies] → group [ApplicabilityState.applies]
/// - Else if any child is [ApplicabilityState.unknown] → group [ApplicabilityState.unknown]
/// - Else → [ApplicabilityState.skipped]
///
/// This prevents "unknown treated as false" errors.
///
/// Part of M7 Applicability (Phase 5).
class ConditionGroupEvaluation {
  /// Group type: "and" or "or".
  final String groupType;

  /// Individual condition results.
  final List<ConditionEvaluation> conditions;

  /// Nested group results.
  final List<ConditionGroupEvaluation> nestedGroups;

  /// Group outcome.
  final ApplicabilityState state;

  const ConditionGroupEvaluation({
    required this.groupType,
    required this.conditions,
    required this.nestedGroups,
    required this.state,
  });

  /// Computes the group state from conditions and nested groups.
  ///
  /// Follows unknown-aware logic as documented in class doc.
  static ApplicabilityState computeGroupState({
    required String groupType,
    required List<ConditionEvaluation> conditions,
    required List<ConditionGroupEvaluation> nestedGroups,
  }) {
    // Collect all child states
    final childStates = <ApplicabilityState>[
      ...conditions.map((c) => c.state),
      ...nestedGroups.map((g) => g.state),
    ];

    if (childStates.isEmpty) {
      // No conditions = applies
      return ApplicabilityState.applies;
    }

    if (groupType.toLowerCase() == 'and') {
      // AND: any skipped → skipped; else any unknown → unknown; else applies
      if (childStates.any((s) => s == ApplicabilityState.skipped)) {
        return ApplicabilityState.skipped;
      }
      if (childStates.any((s) => s == ApplicabilityState.unknown)) {
        return ApplicabilityState.unknown;
      }
      return ApplicabilityState.applies;
    } else {
      // OR: any applies → applies; else any unknown → unknown; else skipped
      if (childStates.any((s) => s == ApplicabilityState.applies)) {
        return ApplicabilityState.applies;
      }
      if (childStates.any((s) => s == ApplicabilityState.unknown)) {
        return ApplicabilityState.unknown;
      }
      return ApplicabilityState.skipped;
    }
  }

  @override
  String toString() =>
      'ConditionGroupEvaluation(type: $groupType, state: $state, '
      'conditions: ${conditions.length}, nestedGroups: ${nestedGroups.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConditionGroupEvaluation &&
          runtimeType == other.runtimeType &&
          groupType == other.groupType &&
          _listEquals(conditions, other.conditions) &&
          _listEquals(nestedGroups, other.nestedGroups) &&
          state == other.state;

  @override
  int get hashCode =>
      groupType.hashCode ^
      _deepListHash(conditions) ^
      _deepListHash(nestedGroups) ^
      state.hashCode;

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Computes a deterministic hash for a list based on element hashes.
  static int _deepListHash<T>(List<T> list) {
    var hash = 0;
    for (var i = 0; i < list.length; i++) {
      hash = hash ^ (list[i].hashCode * (i + 1));
    }
    return hash;
  }
}

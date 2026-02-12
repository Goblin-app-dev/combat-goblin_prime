import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'applicability_result.dart';

/// Result of evaluating a single `<condition>` leaf.
///
/// Contains:
/// - Condition attributes (type, field, scope, childId, value)
/// - Child inclusion flags (includeChildSelections, includeChildForces)
/// - Evaluation result (actualValue, state, reasonCode)
/// - Provenance (sourceFileId, sourceNode)
///
/// Rules:
/// - Unknown field/scope/type must produce [state] = [ApplicabilityState.unknown], NOT skipped.
/// - [actualValue] == null whenever [state] == [ApplicabilityState.unknown].
///
/// Part of M7 Applicability (Phase 5).
class ConditionEvaluation {
  /// Condition type: atLeast, atMost, greaterThan, lessThan, equalTo,
  /// notEqualTo, instanceOf, notInstanceOf.
  final String conditionType;

  /// Field: keyword (selections, forces) OR id-like (costTypeId).
  final String field;

  /// Scope: keyword (self, parent, ancestor, roster, force) OR id-like
  /// (categoryId, entryId).
  final String scope;

  /// Entry/category/other referenced ID (when present).
  final String? childId;

  /// Threshold from condition element.
  final int requiredValue;

  /// Computed value from roster (null if unknown).
  final int? actualValue;

  /// Evaluation result for this leaf.
  final ApplicabilityState state;

  /// Whether to count subtree selections.
  final bool includeChildSelections;

  /// Whether to include nested forces.
  final bool includeChildForces;

  /// Diagnostic code when state is skipped/unknown.
  final String? reasonCode;

  /// Provenance: source file ID.
  final String sourceFileId;

  /// Provenance: source node reference.
  final NodeRef sourceNode;

  const ConditionEvaluation({
    required this.conditionType,
    required this.field,
    required this.scope,
    this.childId,
    required this.requiredValue,
    this.actualValue,
    required this.state,
    required this.includeChildSelections,
    required this.includeChildForces,
    this.reasonCode,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  String toString() =>
      'ConditionEvaluation(type: $conditionType, field: $field, scope: $scope, '
      'state: $state, actual: $actualValue, required: $requiredValue)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConditionEvaluation &&
          runtimeType == other.runtimeType &&
          conditionType == other.conditionType &&
          field == other.field &&
          scope == other.scope &&
          childId == other.childId &&
          requiredValue == other.requiredValue &&
          actualValue == other.actualValue &&
          state == other.state &&
          includeChildSelections == other.includeChildSelections &&
          includeChildForces == other.includeChildForces &&
          reasonCode == other.reasonCode &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode;

  @override
  int get hashCode =>
      conditionType.hashCode ^
      field.hashCode ^
      scope.hashCode ^
      childId.hashCode ^
      requiredValue.hashCode ^
      actualValue.hashCode ^
      state.hashCode ^
      includeChildSelections.hashCode ^
      includeChildForces.hashCode ^
      reasonCode.hashCode ^
      sourceFileId.hashCode ^
      sourceNode.hashCode;
}

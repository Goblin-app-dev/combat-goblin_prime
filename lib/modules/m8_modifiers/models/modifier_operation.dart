import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'modifier_target_ref.dart';
import 'modifier_value.dart';

/// Single modifier operation with parsed data.
///
/// Contains operation type, target, value, and applicability.
/// Operations with `isApplicable=false` are recorded but not applied.
///
/// Part of M8 Modifiers (Phase 6).
class ModifierOperation {
  /// Operation type: set, increment, decrement, append.
  final String operationType;

  /// What is being modified.
  final ModifierTargetRef target;

  /// The modifier value.
  final ModifierValue value;

  /// Whether this operation is applicable (derived from M7 applicability).
  final bool isApplicable;

  /// Reason for skipping (if not applicable).
  final String? reasonSkipped;

  /// Provenance: source file ID.
  final String sourceFileId;

  /// Provenance: source node reference.
  final NodeRef sourceNode;

  const ModifierOperation({
    required this.operationType,
    required this.target,
    required this.value,
    required this.isApplicable,
    this.reasonSkipped,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  String toString() =>
      'ModifierOperation(type: $operationType, target: ${target.targetId}.${target.field}, '
      'value: $value, applicable: $isApplicable)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModifierOperation &&
          runtimeType == other.runtimeType &&
          operationType == other.operationType &&
          target == other.target &&
          value == other.value &&
          isApplicable == other.isApplicable &&
          reasonSkipped == other.reasonSkipped &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode;

  @override
  int get hashCode =>
      operationType.hashCode ^
      target.hashCode ^
      value.hashCode ^
      isApplicable.hashCode ^
      reasonSkipped.hashCode ^
      sourceFileId.hashCode ^
      sourceNode.hashCode;
}

import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Reference to source definition for traceability.
///
/// Part of M6 Evaluate (Phase 4).
class EvaluationSourceRef {
  /// File containing source.
  final String sourceFileId;

  /// Entry containing constraint.
  final String? entryId;

  /// The constraint ID (if present).
  final String? constraintId;

  /// Node reference for traceability.
  final NodeRef? sourceNode;

  const EvaluationSourceRef({
    required this.sourceFileId,
    this.entryId,
    this.constraintId,
    this.sourceNode,
  });

  @override
  String toString() =>
      'EvaluationSourceRef(sourceFileId: $sourceFileId, entryId: $entryId, constraintId: $constraintId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationSourceRef &&
          runtimeType == other.runtimeType &&
          sourceFileId == other.sourceFileId &&
          entryId == other.entryId &&
          constraintId == other.constraintId &&
          sourceNode == other.sourceNode;

  @override
  int get hashCode =>
      sourceFileId.hashCode ^
      entryId.hashCode ^
      constraintId.hashCode ^
      sourceNode.hashCode;
}

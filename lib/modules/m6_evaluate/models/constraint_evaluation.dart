import 'constraint_evaluation_outcome.dart';
import 'constraint_violation.dart';
import 'evaluation_scope.dart';
import 'evaluation_source_ref.dart';

/// Result of evaluating a single (constraint, boundary instance) pair.
///
/// Part of M6 Evaluate (Phase 4).
class ConstraintEvaluation {
  /// ID of the BoundConstraint (if present).
  final String? constraintId;

  /// Evaluation result.
  final ConstraintEvaluationOutcome outcome;

  /// Details if violated.
  final ConstraintViolation? violation;

  /// Boundary used for evaluation.
  final EvaluationScope scope;

  /// The selection instance defining the boundary.
  final String boundarySelectionId;

  /// Reference to source constraint.
  final EvaluationSourceRef sourceRef;

  /// The computed value from count table.
  final int actualValue;

  /// The constraint's required value.
  final int requiredValue;

  /// Constraint type (min, max, etc.).
  final String constraintType;

  const ConstraintEvaluation({
    this.constraintId,
    required this.outcome,
    this.violation,
    required this.scope,
    required this.boundarySelectionId,
    required this.sourceRef,
    required this.actualValue,
    required this.requiredValue,
    required this.constraintType,
  });

  @override
  String toString() =>
      'ConstraintEvaluation(type: $constraintType, outcome: $outcome, actual: $actualValue, required: $requiredValue)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstraintEvaluation &&
          runtimeType == other.runtimeType &&
          constraintId == other.constraintId &&
          outcome == other.outcome &&
          violation == other.violation &&
          scope == other.scope &&
          boundarySelectionId == other.boundarySelectionId &&
          sourceRef == other.sourceRef &&
          actualValue == other.actualValue &&
          requiredValue == other.requiredValue &&
          constraintType == other.constraintType;

  @override
  int get hashCode =>
      constraintId.hashCode ^
      outcome.hashCode ^
      violation.hashCode ^
      scope.hashCode ^
      boundarySelectionId.hashCode ^
      sourceRef.hashCode ^
      actualValue.hashCode ^
      requiredValue.hashCode ^
      constraintType.hashCode;
}

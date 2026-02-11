import 'evaluation_scope.dart';

/// Details of a constraint violation.
///
/// Part of M6 Evaluate (Phase 4).
class ConstraintViolation {
  /// Constraint type (min, max, etc.).
  final String constraintType;

  /// Current count from boundary.
  final int actualValue;

  /// Constraint's required value.
  final int requiredValue;

  /// The entry with the violation.
  final String affectedEntryId;

  /// The boundary instance.
  final String boundarySelectionId;

  /// Boundary where violation occurred.
  final EvaluationScope scope;

  /// Human-readable violation description.
  final String message;

  const ConstraintViolation({
    required this.constraintType,
    required this.actualValue,
    required this.requiredValue,
    required this.affectedEntryId,
    required this.boundarySelectionId,
    required this.scope,
    required this.message,
  });

  @override
  String toString() =>
      'ConstraintViolation(type: $constraintType, actual: $actualValue, required: $requiredValue)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstraintViolation &&
          runtimeType == other.runtimeType &&
          constraintType == other.constraintType &&
          actualValue == other.actualValue &&
          requiredValue == other.requiredValue &&
          affectedEntryId == other.affectedEntryId &&
          boundarySelectionId == other.boundarySelectionId &&
          scope == other.scope &&
          message == other.message;

  @override
  int get hashCode =>
      constraintType.hashCode ^
      actualValue.hashCode ^
      requiredValue.hashCode ^
      affectedEntryId.hashCode ^
      boundarySelectionId.hashCode ^
      scope.hashCode ^
      message.hashCode;
}

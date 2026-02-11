import 'evaluation_source_ref.dart';

/// Non-fatal issue detected during evaluation.
///
/// Warning codes (closed set):
/// - UNKNOWN_CONSTRAINT_TYPE: Constraint type not recognized
/// - UNKNOWN_CONSTRAINT_FIELD: Constraint field not recognized
/// - UNKNOWN_CONSTRAINT_SCOPE: Constraint scope not recognized
/// - UNDEFINED_FORCE_BOUNDARY: Force scope requested but no force root found
/// - MISSING_ENTRY_REFERENCE: Selection references entry not in bundle
///
/// Part of M6 Evaluate (Phase 4).
class EvaluationWarning {
  /// Warning code.
  final String code;

  /// Human-readable description.
  final String message;

  /// Source of warning.
  final EvaluationSourceRef? sourceRef;

  const EvaluationWarning({
    required this.code,
    required this.message,
    this.sourceRef,
  });

  /// Constraint type not recognized.
  static const codeUnknownConstraintType = 'UNKNOWN_CONSTRAINT_TYPE';

  /// Constraint field not recognized.
  static const codeUnknownConstraintField = 'UNKNOWN_CONSTRAINT_FIELD';

  /// Constraint scope not recognized.
  static const codeUnknownConstraintScope = 'UNKNOWN_CONSTRAINT_SCOPE';

  /// Force scope requested but no force root found.
  static const codeUndefinedForceBoundary = 'UNDEFINED_FORCE_BOUNDARY';

  /// Selection references entry not in bundle.
  static const codeMissingEntryReference = 'MISSING_ENTRY_REFERENCE';

  @override
  String toString() => 'EvaluationWarning(code: $code, message: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationWarning &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          sourceRef == other.sourceRef;

  @override
  int get hashCode => code.hashCode ^ message.hashCode ^ sourceRef.hashCode;
}

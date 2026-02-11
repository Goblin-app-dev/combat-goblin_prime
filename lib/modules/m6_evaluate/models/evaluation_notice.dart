import 'evaluation_source_ref.dart';

/// Informational message from evaluation.
///
/// Notice codes (closed set):
/// - CONSTRAINT_SKIPPED: Constraint skipped (condition not met, deferred)
/// - EMPTY_SNAPSHOT: Snapshot has no selections
///
/// Part of M6 Evaluate (Phase 4).
class EvaluationNotice {
  /// Notice code.
  final String code;

  /// Human-readable description.
  final String message;

  /// Source of notice.
  final EvaluationSourceRef? sourceRef;

  const EvaluationNotice({
    required this.code,
    required this.message,
    this.sourceRef,
  });

  /// Constraint skipped (condition not met, deferred).
  static const codeConstraintSkipped = 'CONSTRAINT_SKIPPED';

  /// Snapshot has no selections.
  static const codeEmptySnapshot = 'EMPTY_SNAPSHOT';

  @override
  String toString() => 'EvaluationNotice(code: $code, message: $message)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationNotice &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          sourceRef == other.sourceRef;

  @override
  int get hashCode => code.hashCode ^ message.hashCode ^ sourceRef.hashCode;
}

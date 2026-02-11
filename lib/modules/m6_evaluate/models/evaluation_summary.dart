/// Aggregate summary of all evaluations.
///
/// Part of M6 Evaluate (Phase 4).
class EvaluationSummary {
  /// Total boundary evaluations performed.
  final int totalEvaluations;

  /// Evaluations that passed.
  final int satisfiedCount;

  /// Evaluations that failed.
  final int violatedCount;

  /// Evaluations that didn't apply.
  final int notApplicableCount;

  /// Evaluations that failed to evaluate.
  final int errorCount;

  /// Mechanical check: violatedCount > 0.
  ///
  /// Does NOT imply roster legality; only constraint violation presence.
  bool get hasViolations => violatedCount > 0;

  const EvaluationSummary({
    required this.totalEvaluations,
    required this.satisfiedCount,
    required this.violatedCount,
    required this.notApplicableCount,
    required this.errorCount,
  });

  @override
  String toString() =>
      'EvaluationSummary(total: $totalEvaluations, satisfied: $satisfiedCount, violated: $violatedCount, notApplicable: $notApplicableCount, error: $errorCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationSummary &&
          runtimeType == other.runtimeType &&
          totalEvaluations == other.totalEvaluations &&
          satisfiedCount == other.satisfiedCount &&
          violatedCount == other.violatedCount &&
          notApplicableCount == other.notApplicableCount &&
          errorCount == other.errorCount;

  @override
  int get hashCode =>
      totalEvaluations.hashCode ^
      satisfiedCount.hashCode ^
      violatedCount.hashCode ^
      notApplicableCount.hashCode ^
      errorCount.hashCode;
}

/// Enum representing constraint evaluation result.
///
/// Part of M6 Evaluate (Phase 4).
enum ConstraintEvaluationOutcome {
  /// Constraint requirements are met.
  satisfied,

  /// Constraint requirements are NOT met.
  violated,

  /// Constraint does not apply in current context.
  notApplicable,

  /// Evaluation failed due to error (unknown type, etc).
  error,
}

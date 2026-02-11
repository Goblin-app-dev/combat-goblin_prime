/// Non-deterministic instrumentation data from evaluation.
///
/// **Explicitly excluded from determinism contract and equality comparisons.**
///
/// Part of M6 Evaluate (Phase 4).
class EvaluationTelemetry {
  /// Runtime measurement.
  final Duration evaluationDuration;

  const EvaluationTelemetry({
    required this.evaluationDuration,
  });

  @override
  String toString() =>
      'EvaluationTelemetry(duration: ${evaluationDuration.inMilliseconds}ms)';

  // Note: No equality or hashCode implementation.
  // Telemetry is explicitly non-deterministic and should not be compared.
}

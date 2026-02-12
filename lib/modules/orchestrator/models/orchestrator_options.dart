/// Configuration options for orchestration behavior.
///
/// Options control output verbosity, not evaluation semantics.
///
/// Part of Orchestrator v1 (PROPOSED).
class OrchestratorOptions {
  /// Include skipped modifier operations in output.
  final bool includeSkippedOperations;

  /// Include all diagnostics or filter by severity.
  final bool includeAllDiagnostics;

  const OrchestratorOptions({
    this.includeSkippedOperations = true,
    this.includeAllDiagnostics = true,
  });

  /// Default options with all features enabled.
  static const OrchestratorOptions defaults = OrchestratorOptions();

  @override
  String toString() =>
      'OrchestratorOptions(includeSkippedOperations: $includeSkippedOperations, '
      'includeAllDiagnostics: $includeAllDiagnostics)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrchestratorOptions &&
          runtimeType == other.runtimeType &&
          includeSkippedOperations == other.includeSkippedOperations &&
          includeAllDiagnostics == other.includeAllDiagnostics;

  @override
  int get hashCode =>
      includeSkippedOperations.hashCode ^ includeAllDiagnostics.hashCode;
}

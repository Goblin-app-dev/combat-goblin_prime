class RepoSearchDiagnostics {
  const RepoSearchDiagnostics({
    this.statusCode,
    this.rateLimitRemaining,
    this.rateLimitResetEpochSeconds,
    this.requestId,
  });

  final int? statusCode;
  final int? rateLimitRemaining;
  final int? rateLimitResetEpochSeconds;
  final String? requestId;
}

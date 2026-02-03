/// Failure during acquisition with actionable information.
class AcquireFailure implements Exception {
  /// Human-readable failure message.
  final String message;

  /// Additional details about the failure.
  final String? details;

  /// List of dependency targetIds that could not be resolved.
  /// UI can use this to prompt user to download specific dependencies.
  final List<String> missingTargetIds;

  const AcquireFailure({
    required this.message,
    this.details,
    this.missingTargetIds = const [],
  });

  @override
  String toString() {
    final buffer = StringBuffer('AcquireFailure: $message');
    if (details != null) {
      buffer.write(' ($details)');
    }
    if (missingTargetIds.isNotEmpty) {
      buffer.write(' [missing: ${missingTargetIds.join(", ")}]');
    }
    return buffer.toString();
  }
}

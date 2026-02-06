/// Fatal exception for M5 Bind failures.
///
/// Thrown ONLY for:
/// 1. Corrupted M4 input — LinkedPackBundle violates frozen M4 contracts
/// 2. Internal invariant violation — M5 implementation bug
///
/// NOT thrown for:
/// - Unresolved links → diagnostic
/// - Shadowed definitions → diagnostic
/// - Missing type references → diagnostic
///
/// In normal operation, no BindFailure is thrown.
///
/// Part of M5 Bind (Phase 3).
class BindFailure implements Exception {
  final String message;
  final String? fileId;
  final String? details;

  const BindFailure(
    this.message, {
    this.fileId,
    this.details,
  });

  @override
  String toString() {
    final buffer = StringBuffer('BindFailure: $message');
    if (fileId != null) {
      buffer.write(' (file: $fileId)');
    }
    if (details != null) {
      buffer.write('\n$details');
    }
    return buffer.toString();
  }
}

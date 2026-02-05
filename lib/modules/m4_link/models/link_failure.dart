/// Fatal exception for M4 Link failures.
///
/// Thrown ONLY for:
/// - Corrupted M3 input (WrappedPackBundle violates frozen contracts)
/// - Internal invariant violation (M4 implementation bug)
///
/// NOT thrown for:
/// - Unresolved references → UNRESOLVED_TARGET diagnostic
/// - Duplicate IDs → DUPLICATE_ID_REFERENCE diagnostic
/// - Missing/empty targetId → INVALID_LINK_FORMAT diagnostic
///
/// In normal operation, no LinkFailure is thrown.
/// All resolution issues produce diagnostics and continue.
///
/// Part of M4 Link (Phase 2).
class LinkFailure implements Exception {
  final String message;
  final String? fileId;
  final String? details;

  const LinkFailure(
    this.message, {
    this.fileId,
    this.details,
  });

  @override
  String toString() {
    final buffer = StringBuffer('LinkFailure: $message');
    if (fileId != null) {
      buffer.write(' (file: $fileId)');
    }
    if (details != null) {
      buffer.write('\nDetails: $details');
    }
    return buffer.toString();
  }
}

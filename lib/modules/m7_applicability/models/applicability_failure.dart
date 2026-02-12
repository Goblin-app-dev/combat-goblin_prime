/// Fatal exception for M7 Applicability failures.
///
/// Thrown ONLY for:
/// 1. Corrupted M5 input — BoundPackBundle violates frozen contracts
/// 2. Internal invariant violation — M7 implementation bug
///
/// **NOT thrown for:**
/// - Unknown condition types → diagnostic, state unknown
/// - Unknown scopes → diagnostic, state unknown
/// - Unresolved IDs → diagnostic, state unknown
///
/// **In normal operation, no ApplicabilityFailure is thrown.**
///
/// Part of M7 Applicability (Phase 5).
class ApplicabilityFailure implements Exception {
  final String message;
  final String? fileId;
  final String? details;
  final String invariant;

  const ApplicabilityFailure({
    required this.message,
    required this.invariant,
    this.fileId,
    this.details,
  });

  /// Corrupted M5 input.
  static const invariantCorruptedInput = 'CORRUPTED_M5_INPUT';

  /// M7 implementation bug.
  static const invariantInternalAssertion = 'INTERNAL_ASSERTION';

  @override
  String toString() =>
      'ApplicabilityFailure(invariant: $invariant, message: $message'
      '${fileId != null ? ', fileId: $fileId' : ''}'
      '${details != null ? ', details: $details' : ''})';
}

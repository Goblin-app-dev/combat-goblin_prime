/// Fatal exception for M8 Modifiers failures.
///
/// Thrown ONLY for:
/// 1. Corrupted M5 input — BoundPackBundle violates frozen contracts
/// 2. Internal invariant violation — M8 implementation bug
///
/// **NOT thrown for:**
/// - Unknown modifier types → diagnostic, operation skipped
/// - Unknown fields/scopes → diagnostic, operation skipped
/// - Unresolved targets → diagnostic, operation skipped
///
/// **In normal operation, no ModifierFailure is thrown.**
///
/// Part of M8 Modifiers (Phase 6).
class ModifierFailure implements Exception {
  final String message;
  final String? fileId;
  final String? details;
  final String invariant;

  const ModifierFailure({
    required this.message,
    required this.invariant,
    this.fileId,
    this.details,
  });

  /// Corrupted M5 input.
  static const invariantCorruptedInput = 'CORRUPTED_M5_INPUT';

  /// M8 implementation bug.
  static const invariantInternalAssertion = 'INTERNAL_ASSERTION';

  @override
  String toString() =>
      'ModifierFailure(invariant: $invariant, message: $message'
      '${fileId != null ? ', fileId: $fileId' : ''}'
      '${details != null ? ', details: $details' : ''})';
}

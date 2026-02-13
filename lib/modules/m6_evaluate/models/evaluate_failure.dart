/// Fatal exception for M6 failures.
///
/// Thrown ONLY for enumerated invariant violations:
/// - CYCLE_DETECTED: Cycle in selection hierarchy
/// - INVALID_CHILDREN_TYPE: childrenOf must return a List (not Set)
/// - DUPLICATE_CHILD_ID: childrenOf contains duplicate selection IDs
/// - UNKNOWN_CHILD_ID: childrenOf references unknown selection ID
/// - INTERNAL_ASSERTION: M6 implementation bug
///
/// Note: NULL_PROVENANCE was removed as provenance is enforced at compile
/// time via non-nullable types in BoundPackBundle.linkedBundle.
///
/// **In normal operation, no EvaluateFailure is thrown.**
///
/// Part of M6 Evaluate (Phase 4).
class EvaluateFailure implements Exception {
  final String message;
  final String? entryId;
  final String? details;
  final String invariant;

  const EvaluateFailure({
    required this.message,
    required this.invariant,
    this.entryId,
    this.details,
  });

  /// Cycle in selection hierarchy.
  static const invariantCycleDetected = 'CYCLE_DETECTED';

  /// childrenOf must return a List (not Set).
  static const invariantInvalidChildrenType = 'INVALID_CHILDREN_TYPE';

  /// childrenOf contains duplicate selection IDs.
  static const invariantDuplicateChildId = 'DUPLICATE_CHILD_ID';

  /// childrenOf references unknown selection ID.
  static const invariantUnknownChildId = 'UNKNOWN_CHILD_ID';

  /// M6 implementation bug.
  static const invariantInternalAssertion = 'INTERNAL_ASSERTION';

  @override
  String toString() =>
      'EvaluateFailure(invariant: $invariant, message: $message${entryId != null ? ', entryId: $entryId' : ''}${details != null ? ', details: $details' : ''})';
}

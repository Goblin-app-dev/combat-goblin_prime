import 'node_ref.dart';

/// Exception for structural corruption during M3 wrapping.
///
/// Used only for:
/// - Structural corruption
/// - Internal invariant violation
/// - Impossible traversal states
///
/// Not used for:
/// - Duplicate IDs
/// - Missing IDs
/// - Semantic issues
///
/// Part of M3 Wrap (Phase 1C).
class WrapFailure implements Exception {
  /// Human-readable error description.
  final String message;

  /// Which file failed (if known).
  final String? fileId;

  /// Node where error occurred (if known).
  final NodeRef? node;

  /// Additional context.
  final String? details;

  const WrapFailure({
    required this.message,
    this.fileId,
    this.node,
    this.details,
  });

  @override
  String toString() {
    final parts = ['WrapFailure: $message'];
    if (fileId != null) parts.add('fileId=$fileId');
    if (node != null) parts.add('node=${node!.nodeIndex}');
    if (details != null) parts.add('details=$details');
    return parts.join(', ');
  }
}

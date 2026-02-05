import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Result of resolving a single cross-file reference.
///
/// Records outcomes without enforcing correctness.
///
/// Target ordering contract:
/// 1. By file resolution order: primaryCatalog → dependencyCatalogs (list order) → gameSystem
/// 2. Within each file: by WrappedFile.nodes index order (M3 traversal order)
///
/// Invariants:
/// - targets.isEmpty ⇔ UNRESOLVED_TARGET diagnostic emitted
/// - targets.length > 1 ⇔ DUPLICATE_ID_REFERENCE diagnostic emitted
/// - targets.length == 1 ⇔ unique resolution (no diagnostic)
///
/// Part of M4 Link (Phase 2).
class ResolvedRef {
  /// File containing the link element.
  final String sourceFileId;

  /// The link element node.
  final NodeRef sourceNode;

  /// The targetId attribute value being resolved.
  final String targetId;

  /// Resolved targets as (fileId, NodeRef) pairs.
  ///
  /// List is ordered deterministically:
  /// - File order: primaryCatalog → dependencyCatalogs → gameSystem
  /// - Within file: node index order
  final List<({String fileId, NodeRef nodeRef})> targets;

  const ResolvedRef({
    required this.sourceFileId,
    required this.sourceNode,
    required this.targetId,
    required this.targets,
  });

  /// True if the reference resolved to at least one target.
  bool get isResolved => targets.isNotEmpty;

  /// True if the reference resolved to exactly one target.
  bool get isUnique => targets.length == 1;

  /// True if the reference resolved to multiple targets.
  bool get isMultiHit => targets.length > 1;

  @override
  String toString() =>
      'ResolvedRef(source: $sourceFileId/$sourceNode, targetId: $targetId, targets: ${targets.length})';
}

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';

import 'node_ref.dart';

/// Indexed, navigable representation of an XML element with explicit provenance.
///
/// Part of a flat node table in WrappedFile.
/// Part of M3 Wrap (Phase 1C).
///
/// Invariants:
/// - parent == null ⇔ depth == 0
/// - If A.children contains B, then B.parent == A
/// - depth == (parent == null ? 0 : parent.depth + 1)
/// - children order matches traversal order
class WrappedNode {
  /// This node's own reference.
  final NodeRef ref;

  /// XML element tag name.
  final String tagName;

  /// All XML attributes as key-value pairs.
  final Map<String, String> attributes;

  /// Text content if present (null if element has only children).
  final String? textContent;

  /// Parent node reference (null for root).
  final NodeRef? parent;

  /// Child node references in document order.
  final List<NodeRef> children;

  /// Depth in tree (root=0, child of root=1, etc.).
  final int depth;

  /// Provenance: fileId from ParsedFile.
  final String fileId;

  /// Provenance: fileType from ParsedFile.
  final SourceFileType fileType;

  /// Copied from ElementDto.sourceIndex (best-effort, nullable).
  final int? sourceIndex;

  const WrappedNode({
    required this.ref,
    required this.tagName,
    required this.attributes,
    this.textContent,
    this.parent,
    required this.children,
    required this.depth,
    required this.fileId,
    required this.fileType,
    this.sourceIndex,
  });
}

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';

import 'node_ref.dart';
import 'wrapped_node.dart';

/// Per-file node table produced by M3 Wrap.
///
/// Contains flat list of WrappedNode plus idIndex mapping `id` attribute
/// to List<NodeRef>. No cross-file linking.
///
/// Part of M3 Wrap (Phase 1C).
class WrappedFile {
  /// Provenance: fileId from ParsedFile.
  final String fileId;

  /// Provenance: fileType from ParsedFile.
  final SourceFileType fileType;

  /// Flat list of all nodes in pre-order depth-first traversal order.
  /// nodes[0] is always the root.
  final List<WrappedNode> nodes;

  /// Maps `id` attribute → List<NodeRef>.
  /// Nodes without an `id` attribute are excluded.
  /// Duplicate IDs are preserved (list contains all occurrences).
  final Map<String, List<NodeRef>> idIndex;

  const WrappedFile({
    required this.fileId,
    required this.fileType,
    required this.nodes,
    required this.idIndex,
  });

  /// Returns the root node (always at index 0).
  WrappedNode get root => nodes[0];

  /// Returns the NodeRef for the root node.
  NodeRef get rootRef => const NodeRef(0);

  /// Looks up a node by its NodeRef.
  WrappedNode nodeAt(NodeRef ref) => nodes[ref.nodeIndex];
}

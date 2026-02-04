import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';

import '../models/node_ref.dart';
import '../models/wrapped_file.dart';
import '../models/wrapped_node.dart';
import '../models/wrapped_pack_bundle.dart';

/// Service that wraps ParsedPackBundle into WrappedPackBundle.
///
/// Traversal contract:
/// - Pre-order depth-first traversal
/// - Children visited in ElementDto.children order
/// - root.nodeIndex == 0
/// - nodeIndex increments by +1 per node
///
/// Part of M3 Wrap (Phase 1C).
class WrapService {
  /// Wraps a ParsedPackBundle into a WrappedPackBundle.
  ///
  /// For each ParsedFile:
  /// 1. Traverse ElementDto tree in pre-order depth-first
  /// 2. Build flat nodes list with deterministic nodeIndex
  /// 3. Assign parent, children, depth
  /// 4. Copy fileId, fileType to each node for provenance
  /// 5. Build idIndex map from attributes['id']
  Future<WrappedPackBundle> wrapBundle({
    required ParsedPackBundle parsedBundle,
  }) async {
    final gameSystem = _wrapFile(parsedBundle.gameSystem);
    final primaryCatalog = _wrapFile(parsedBundle.primaryCatalog);
    final dependencyCatalogs = parsedBundle.dependencyCatalogs
        .map((pf) => _wrapFile(pf))
        .toList();

    return WrappedPackBundle(
      packId: parsedBundle.packId,
      wrappedAt: DateTime.now().toUtc(),
      gameSystem: gameSystem,
      primaryCatalog: primaryCatalog,
      dependencyCatalogs: dependencyCatalogs,
    );
  }

  WrappedFile _wrapFile(ParsedFile parsedFile) {
    final nodes = <WrappedNode>[];
    final idIndex = <String, List<NodeRef>>{};

    // Pre-order depth-first traversal
    _traverseAndWrap(
      element: parsedFile.root,
      parent: null,
      depth: 0,
      nodes: nodes,
      idIndex: idIndex,
      fileId: parsedFile.fileId,
      fileType: parsedFile.fileType,
    );

    return WrappedFile(
      fileId: parsedFile.fileId,
      fileType: parsedFile.fileType,
      nodes: nodes,
      idIndex: idIndex,
    );
  }

  void _traverseAndWrap({
    required ElementDto element,
    required NodeRef? parent,
    required int depth,
    required List<WrappedNode> nodes,
    required Map<String, List<NodeRef>> idIndex,
    required String fileId,
    required SourceFileType fileType,
  }) {
    // Assign nodeIndex (current list length before adding)
    final nodeIndex = nodes.length;
    final ref = NodeRef(nodeIndex);

    // Collect child refs (we'll fill them after traversing children)
    final childRefs = <NodeRef>[];

    // Create placeholder node (children will be filled after traversal)
    // We need to add the node first to maintain pre-order traversal
    final placeholderNode = WrappedNode(
      ref: ref,
      tagName: element.tagName,
      attributes: Map.unmodifiable(element.attributes),
      textContent: element.textContent,
      parent: parent,
      children: childRefs, // Will be populated during child traversal
      depth: depth,
      fileId: fileId,
      fileType: fileType,
      sourceIndex: element.sourceIndex,
    );

    nodes.add(placeholderNode);

    // Add to idIndex if has id attribute
    final id = element.attributes['id'];
    if (id != null) {
      idIndex.putIfAbsent(id, () => []).add(ref);
    }

    // Traverse children in document order
    for (final childElement in element.children) {
      final childIndex = nodes.length;
      final childRef = NodeRef(childIndex);
      childRefs.add(childRef);

      _traverseAndWrap(
        element: childElement,
        parent: ref,
        depth: depth + 1,
        nodes: nodes,
        idIndex: idIndex,
        fileId: fileId,
        fileType: fileType,
      );
    }
  }
}

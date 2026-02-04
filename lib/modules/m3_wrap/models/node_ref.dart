/// Strongly-typed handle for node identity within a WrappedFile.
///
/// Prevents raw integer indices from leaking outside M3 internals.
/// Part of M3 Wrap (Phase 1C).
class NodeRef {
  /// The index of the node within the WrappedFile.nodes list.
  final int nodeIndex;

  const NodeRef(this.nodeIndex);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeRef &&
          runtimeType == other.runtimeType &&
          nodeIndex == other.nodeIndex;

  @override
  int get hashCode => nodeIndex.hashCode;

  @override
  String toString() => 'NodeRef($nodeIndex)';
}

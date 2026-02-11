/// Contract interface for roster state input to M6.
///
/// SelectionSnapshot defines the operations M6 requires to evaluate constraints.
/// The concrete implementation is outside M6 scope. Any type that satisfies
/// this contract can be used.
///
/// **Determinism requirement:** The snapshot MUST provide children in a
/// stable, deterministic order.
///
/// Part of M6 Evaluate (Phase 4).
abstract class SelectionSnapshot {
  /// Returns an ordered list of all selection instances.
  ///
  /// Order must be root-first DFS traversal.
  /// Must return a List (not Set or other unordered type).
  List<String> orderedSelections();

  /// Returns the entry ID for a selection.
  ///
  /// Maps a selection instance to its bound entry definition.
  String entryIdFor(String selectionId);

  /// Returns the parent selection ID, or null for root selections.
  String? parentOf(String selectionId);

  /// Returns an ordered list of child selection IDs.
  ///
  /// Must return a List with stable order.
  /// Must not contain duplicates.
  /// All child IDs must exist in orderedSelections().
  List<String> childrenOf(String selectionId);

  /// Returns the count for this selection instance.
  ///
  /// Represents how many of this entry are selected.
  int countFor(String selectionId);

  /// Returns true if this selection is a force root.
  ///
  /// Used for force scope boundary detection.
  bool isForceRoot(String selectionId);
}

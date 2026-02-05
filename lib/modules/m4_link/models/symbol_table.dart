import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Cross-file ID registry built from M3 output.
///
/// One SymbolTable per LinkedPackBundle. Indexes all `id` attributes
/// across all WrappedFile instances.
///
/// Construction order: primaryCatalog → dependencyCatalogs (list order) → gameSystem.
/// This matches the lookup/targets ordering rule.
///
/// Rules:
/// - Duplicate IDs are allowed and preserved
/// - All occurrences retained
/// - No throwing during construction
///
/// SymbolTable is a lookup structure, not a semantic authority.
///
/// Part of M4 Link (Phase 2).
class SymbolTable {
  /// Internal storage: ID → list of (fileId, NodeRef) pairs.
  /// Ordered by file resolution order, then node order within file.
  final Map<String, List<({String fileId, NodeRef nodeRef})>> _entries;

  SymbolTable._(this._entries);

  /// Build a SymbolTable by aggregating idIndex from each file.
  ///
  /// Files are processed in resolution order:
  /// primaryCatalog → dependencyCatalogs (list order) → gameSystem.
  ///
  /// No re-traversal of nodes; uses existing idIndex from each WrappedFile.
  factory SymbolTable.fromWrappedBundle(WrappedPackBundle bundle) {
    final entries = <String, List<({String fileId, NodeRef nodeRef})>>{};

    void aggregateFile(WrappedFile file) {
      for (final entry in file.idIndex.entries) {
        final id = entry.key;
        final nodeRefs = entry.value;

        // Add all node refs for this ID, preserving node order
        for (final nodeRef in nodeRefs) {
          entries.putIfAbsent(id, () => []);
          entries[id]!.add((fileId: file.fileId, nodeRef: nodeRef));
        }
      }
    }

    // Aggregate in file resolution order
    aggregateFile(bundle.primaryCatalog);
    for (final dep in bundle.dependencyCatalogs) {
      aggregateFile(dep);
    }
    aggregateFile(bundle.gameSystem);

    return SymbolTable._(entries);
  }

  /// Lookup all nodes with the given ID.
  ///
  /// Returns results in file resolution order (primary → deps → gamesystem),
  /// then node order within each file.
  ///
  /// Returns empty list if ID not found.
  List<({String fileId, NodeRef nodeRef})> lookup(String id) {
    return _entries[id] ?? const [];
  }

  /// All indexed IDs.
  Iterable<String> get allIds => _entries.keys;

  /// IDs with more than one definition (across all files).
  List<String> get duplicateIds =>
      _entries.entries.where((e) => e.value.length > 1).map((e) => e.key).toList();

  /// Total number of unique IDs indexed.
  int get idCount => _entries.length;

  /// Total number of entries (including duplicates).
  int get entryCount => _entries.values.fold(0, (sum, list) => sum + list.length);
}

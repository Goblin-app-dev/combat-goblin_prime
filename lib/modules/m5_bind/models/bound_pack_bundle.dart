import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';

import 'bind_diagnostic.dart';
import 'bound_category.dart';
import 'bound_cost.dart';
import 'bound_entry.dart';
import 'bound_profile.dart';

/// Complete M5 output with bound entities and query surface.
///
/// Query Semantics:
/// - *ById(id): Returns null if ID not found
/// - all* getters: Returns empty iterable if none bound
/// - *ForEntry(id): Returns empty iterable if entry not found or relationship empty
/// - entriesInCategory(id): Returns empty iterable if category not found
///
/// No query throws on missing data. All return null or empty.
///
/// Deterministic Ordering:
/// All list-returning queries return results in binding order:
/// 1. File resolution order (primaryCatalog → dependencyCatalogs → gameSystem)
/// 2. Within each file: node index order (pre-order depth-first from M3)
///
/// Hidden Content:
/// Queries return all bound content including hidden entries.
/// Use BoundEntry.isHidden to filter.
///
/// Part of M5 Bind (Phase 3).
class BoundPackBundle {
  final String packId;
  final DateTime boundAt;

  /// All bound entries (flat list, binding order).
  final List<BoundEntry> entries;

  /// All bound profiles (flat list, binding order).
  final List<BoundProfile> profiles;

  /// All bound categories (flat list, binding order).
  final List<BoundCategory> categories;

  /// Semantic issues detected during binding.
  final List<BindDiagnostic> diagnostics;

  /// Reference to M4 input (immutable).
  final LinkedPackBundle linkedBundle;

  // Query indices (built on construction)
  final Map<String, BoundEntry> _entryIndex;
  final Map<String, BoundProfile> _profileIndex;
  final Map<String, BoundCategory> _categoryIndex;
  final Map<String, List<BoundEntry>> _entriesByCategoryIndex;
  final Map<String, List<BoundProfile>> _profilesByEntryIndex;
  final Map<String, List<BoundCategory>> _categoriesByEntryIndex;
  final Map<String, List<BoundCost>> _costsByEntryIndex;

  BoundPackBundle({
    required this.packId,
    required this.boundAt,
    required this.entries,
    required this.profiles,
    required this.categories,
    required this.diagnostics,
    required this.linkedBundle,
  })  : _entryIndex = {for (final e in entries) e.id: e},
        _profileIndex = {for (final p in profiles) p.id: p},
        _categoryIndex = {for (final c in categories) c.id: c},
        _entriesByCategoryIndex = _buildEntriesByCategoryIndex(entries),
        _profilesByEntryIndex = _buildProfilesByEntryIndex(entries),
        _categoriesByEntryIndex = _buildCategoriesByEntryIndex(entries),
        _costsByEntryIndex = _buildCostsByEntryIndex(entries);

  // --- Lookup by ID ---

  /// Returns entry with given ID, or null if not found.
  BoundEntry? entryById(String id) => _entryIndex[id];

  /// Returns profile with given ID, or null if not found.
  BoundProfile? profileById(String id) => _profileIndex[id];

  /// Returns category with given ID, or null if not found.
  BoundCategory? categoryById(String id) => _categoryIndex[id];

  // --- List all ---

  /// All bound entries in binding order.
  Iterable<BoundEntry> get allEntries => entries;

  /// All bound profiles in binding order.
  Iterable<BoundProfile> get allProfiles => profiles;

  /// All bound categories in binding order.
  Iterable<BoundCategory> get allCategories => categories;

  // --- Relationship queries ---

  /// Entries that have the given category, in binding order.
  Iterable<BoundEntry> entriesInCategory(String categoryId) =>
      _entriesByCategoryIndex[categoryId] ?? const [];

  /// Profiles for the given entry, in binding order.
  Iterable<BoundProfile> profilesForEntry(String entryId) =>
      _profilesByEntryIndex[entryId] ?? const [];

  /// Categories for the given entry, in binding order.
  Iterable<BoundCategory> categoriesForEntry(String entryId) =>
      _categoriesByEntryIndex[entryId] ?? const [];

  /// Costs for the given entry, in binding order.
  Iterable<BoundCost> costsForEntry(String entryId) =>
      _costsByEntryIndex[entryId] ?? const [];

  // --- Diagnostic helpers ---

  int get unresolvedEntryLinkCount => diagnostics
      .where((d) => d.code == BindDiagnosticCode.unresolvedEntryLink)
      .length;

  int get unresolvedInfoLinkCount => diagnostics
      .where((d) => d.code == BindDiagnosticCode.unresolvedInfoLink)
      .length;

  int get unresolvedCategoryLinkCount => diagnostics
      .where((d) => d.code == BindDiagnosticCode.unresolvedCategoryLink)
      .length;

  int get shadowedDefinitionCount => diagnostics
      .where((d) => d.code == BindDiagnosticCode.shadowedDefinition)
      .length;

  // --- Index builders (static to avoid capturing 'this') ---

  static Map<String, List<BoundEntry>> _buildEntriesByCategoryIndex(
      List<BoundEntry> entries) {
    final index = <String, List<BoundEntry>>{};
    for (final entry in entries) {
      for (final cat in entry.categories) {
        index.putIfAbsent(cat.id, () => []).add(entry);
      }
    }
    return index;
  }

  static Map<String, List<BoundProfile>> _buildProfilesByEntryIndex(
      List<BoundEntry> entries) {
    final index = <String, List<BoundProfile>>{};
    for (final entry in entries) {
      if (entry.profiles.isNotEmpty) {
        index[entry.id] = entry.profiles;
      }
    }
    return index;
  }

  static Map<String, List<BoundCategory>> _buildCategoriesByEntryIndex(
      List<BoundEntry> entries) {
    final index = <String, List<BoundCategory>>{};
    for (final entry in entries) {
      if (entry.categories.isNotEmpty) {
        index[entry.id] = entry.categories;
      }
    }
    return index;
  }

  static Map<String, List<BoundCost>> _buildCostsByEntryIndex(
      List<BoundEntry> entries) {
    final index = <String, List<BoundCost>>{};
    for (final entry in entries) {
      if (entry.costs.isNotEmpty) {
        index[entry.id] = entry.costs;
      }
    }
    return index;
  }
}

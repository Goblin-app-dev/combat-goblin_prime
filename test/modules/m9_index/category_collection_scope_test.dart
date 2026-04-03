/// Category Collection Scope Tests
///
/// PURPOSE
/// -------
/// Permanent regression guards for _collectCategoryKeywords traversal scope.
/// Locked after the fix that stopped traversal at game-system-sourced entries,
/// mirroring the identical fix in _collectWeaponRefs (commit 399aabe).
///
/// THREE INVARIANTS
/// ----------------
///
///   a) CATALOG-SOURCED CATEGORIES RETAINED
///      A unit entry whose direct categories are sourced from a catalog keeps
///      those keywords. The fix must not strip legitimate catalog categories.
///
///   b) GAME-SYSTEM BRANCH EXCLUDED
///      A unit entry that has a child entry sourced from the game system
///      (sourceFileId == gameSystemFileId) does NOT collect categories from
///      that child. Campaign-structure categories (e.g. "Monster Hunters",
///      "Striding Behemoths", "Tyrannic War Veteran") must be blocked.
///
///   c) DEPENDENCY CATALOG CHILDREN COLLECTED
///      A unit entry that has a child sourced from a dependency catalog
///      (not the game system) still collects categories from that child.
///      Normal shared-library category entries must continue to work.
///
/// APPROACH
/// --------
/// All tests build minimal BoundPackBundle objects in-memory without catalog
/// fixture files. This makes the tests fast, hermetic, and independent of
/// fixture availability. No full M1→M9 pipeline is run.
///
/// RUNNING
/// -------
///   flutter test test/modules/m9_index/category_collection_scope_test.dart --reporter expanded

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

// ---------------------------------------------------------------------------
// File ID constants (same scheme as weapon_collection_scope_test.dart)
// ---------------------------------------------------------------------------

const _gstFileId = 'gst-cat-scope-0001';
const _catFileId = 'cat-cat-scope-0001';
const _libDepFileId = 'lib-dep-cat-scope-0001';
const _depCatFileId = 'dep-cat-cat-scope-0001';

// ---------------------------------------------------------------------------
// Minimal in-memory factory helpers
// ---------------------------------------------------------------------------

WrappedFile _minimalWrappedFile(String fileId, SourceFileType type) {
  final node = WrappedNode(
    ref: const NodeRef(0),
    tagName: 'catalogue',
    attributes: const {},
    parent: null,
    children: const [],
    depth: 0,
    fileId: fileId,
    fileType: type,
  );
  return WrappedFile(
    fileId: fileId,
    fileType: type,
    nodes: [node],
    idIndex: const {},
  );
}

WrappedPackBundle _minimalWrappedBundle() {
  return WrappedPackBundle(
    packId: 'test-cat-pack',
    wrappedAt: DateTime(2026, 1, 1),
    gameSystem: _minimalWrappedFile(_gstFileId, SourceFileType.gst),
    primaryCatalog: _minimalWrappedFile(_catFileId, SourceFileType.cat),
    dependencyCatalogs: [
      _minimalWrappedFile(_libDepFileId, SourceFileType.cat),
      _minimalWrappedFile(_depCatFileId, SourceFileType.cat),
    ],
  );
}

LinkedPackBundle _minimalLinkedBundle(WrappedPackBundle wrappedBundle) {
  return LinkedPackBundle(
    packId: wrappedBundle.packId,
    linkedAt: DateTime(2026, 1, 1),
    symbolTable: SymbolTable.fromWrappedBundle(wrappedBundle),
    resolvedRefs: const [],
    diagnostics: const [],
    wrappedBundle: wrappedBundle,
  );
}

BoundProfile _unitProfile({
  required String id,
  required String sourceFileId,
}) {
  return BoundProfile(
    id: id,
    name: 'Test Unit Profile',
    typeId: 'type-unit',
    typeName: 'unit',
    characteristics: const [
      (name: 'M', value: '6"'),
      (name: 'T', value: '4'),
      (name: 'SV', value: '3+'),
      (name: 'W', value: '2'),
      (name: 'LD', value: '7+'),
      (name: 'OC', value: '1'),
    ],
    sourceFileId: sourceFileId,
    sourceNode: const NodeRef(0),
  );
}

BoundCategory _category(String name) {
  return BoundCategory(
    id: 'cat-${name.toLowerCase().replaceAll(' ', '-')}',
    name: name,
    isPrimary: false,
    sourceFileId: _catFileId,
    sourceNode: const NodeRef(0),
  );
}

BoundEntry _entry({
  required String id,
  required String name,
  required String sourceFileId,
  required List<BoundProfile> profiles,
  List<BoundEntry> children = const [],
  List<BoundCategory> categories = const [],
}) {
  return BoundEntry(
    id: id,
    name: name,
    isGroup: false,
    isHidden: false,
    children: children,
    profiles: profiles,
    categories: categories,
    costs: const [],
    constraints: const [],
    sourceFileId: sourceFileId,
    sourceNode: const NodeRef(0),
  );
}

BoundPackBundle _boundBundle({
  required List<BoundEntry> entries,
  required List<BoundProfile> allProfiles,
}) {
  final wrappedBundle = _minimalWrappedBundle();
  final linked = _minimalLinkedBundle(wrappedBundle);
  return BoundPackBundle(
    packId: 'test-cat-pack',
    boundAt: DateTime(2026, 1, 1),
    entries: entries,
    profiles: allProfiles,
    categories: const [],
    diagnostics: const [],
    linkedBundle: linked,
  );
}

// ---------------------------------------------------------------------------
// Helper: extract keywordTokens for a named unit from an IndexBundle
// ---------------------------------------------------------------------------

List<String> _keywordTokensFor(IndexBundle index, String unitName) {
  final units = index.findUnitsByName(unitName);
  if (units.isEmpty) return [];
  return units.first.keywordTokens;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('_collectCategoryKeywords scope invariants', () {
    // ── Invariant a: catalog-sourced categories retained ─────────────────────

    test(
        'a: unit with catalog-sourced categories retains those keywords', () {
      // Category is on the unit entry directly, sourced from the primary catalog.
      //
      // Expectation: keyword IS collected — the traversal stop only applies to
      // children whose sourceFileId == gameSystemFileId. Direct categories on
      // the unit entry are always included.

      final unitProf = _unitProfile(id: 'unit-prof-cat-a', sourceFileId: _catFileId);

      final unitEntry = _entry(
        id: 'entry-cat-a-001',
        name: 'Test Warrior',
        sourceFileId: _catFileId,
        profiles: [unitProf],
        categories: [_category('Faction: Adeptus Astartes')],
      );

      final bundle = _boundBundle(
        entries: [unitEntry],
        allProfiles: [unitProf],
      );

      final index = IndexService().buildIndex(bundle);
      final keywords = _keywordTokensFor(index, 'Test Warrior');

      print('[TEST-cat-a] keywordTokens: $keywords');

      expect(
        keywords,
        contains('adeptus astartes'),
        reason: 'Catalog-sourced category on unit entry must be collected. '
            'The traversal stop only applies to game-system-sourced CHILDREN, '
            'not to direct categories on the unit entry itself.',
      );
    });

    // ── Invariant b: game-system child categories excluded ───────────────────

    test(
        'b: child entry sourced from game system does not contribute categories', () {
      // The unit entry has:
      //   - A legitimate category directly (catalog-sourced) → must be collected
      //   - A child entry sourced from the game system with its own category → must NOT be collected
      //
      // This models the exact campaign-structure categories (e.g. "Monster Hunters",
      // "Striding Behemoths", "Tyrannic War Veteran") that were over-collecting.

      final unitProf = _unitProfile(id: 'unit-prof-cat-b', sourceFileId: _catFileId);

      // Child entry sourced from game system — traversal must stop here.
      final gstChild = _entry(
        id: 'child-gst-cat-001',
        name: 'Crusade Option',
        sourceFileId: _gstFileId,
        profiles: const [],
        categories: [_category('Monster Hunters')],
      );

      final unitEntry = _entry(
        id: 'entry-cat-b-001',
        name: 'Test Psyker',
        sourceFileId: _catFileId,
        profiles: [unitProf],
        categories: [_category('Faction: Adeptus Astartes')],
        children: [gstChild],
      );

      final bundle = _boundBundle(
        entries: [unitEntry, gstChild],
        allProfiles: [unitProf],
      );

      final index = IndexService().buildIndex(bundle);
      final keywords = _keywordTokensFor(index, 'Test Psyker');

      print('[TEST-cat-b] keywordTokens: $keywords');

      // The direct catalog category must still be present.
      expect(
        keywords,
        contains('adeptus astartes'),
        reason: 'Direct catalog-sourced category on unit entry must be collected.',
      );

      // The game-system child's category must NOT be present.
      expect(
        keywords,
        isNot(contains('monster hunters')),
        reason: 'Category from a game-system-sourced child entry must NOT be '
            'collected. This is the campaign-structure over-collection fix. '
            'If this fails, the traversal stop at sourceFileId==gameSystemFileId '
            'has regressed in _collectCategoryKeywords.',
      );
    });

    // ── Invariant c: dependency catalog child categories collected ────────────

    test(
        'c: child entry from dependency catalog contributes categories normally', () {
      // A unit entry has a child entry sourced from a dependency catalog
      // (not the game system). This models shared library category entries.
      //
      // Expectation: dep-catalog child categories ARE collected. Only game-system
      // children are blocked — all other catalog sources pass through.

      final unitProf = _unitProfile(id: 'unit-prof-cat-c', sourceFileId: _catFileId);

      final depChild = _entry(
        id: 'child-dep-cat-001',
        name: 'Category Option',
        sourceFileId: _depCatFileId,
        profiles: const [],
        categories: [_category('Infantry')],
      );

      final unitEntry = _entry(
        id: 'entry-cat-c-001',
        name: 'Test Infantry Unit',
        sourceFileId: _catFileId,
        profiles: [unitProf],
        children: [depChild],
      );

      final bundle = _boundBundle(
        entries: [unitEntry, depChild],
        allProfiles: [unitProf],
      );

      final index = IndexService().buildIndex(bundle);
      final keywords = _keywordTokensFor(index, 'Test Infantry Unit');

      print('[TEST-cat-c] keywordTokens: $keywords');

      expect(
        keywords,
        contains('infantry'),
        reason: 'Category from a dependency-catalog-sourced child entry must be '
            'collected. Only children whose sourceFileId equals the game system '
            'file ID are stopped. Dep-catalog children pass through normally.',
      );
    });

    // ── Invariant d: game-system stop blocks full subtree ────────────────────

    test(
        'd: game-system stop blocks the entire subtree below that child', () {
      // A game-system child has its own dep-catalog grandchildren with categories.
      // Even those grandchildren must be blocked — the stop at the game-system
      // entry boundary prunes the entire subtree below that point.

      final unitProf = _unitProfile(id: 'unit-prof-cat-d', sourceFileId: _catFileId);

      // Grandchild is dep-catalog sourced, but its parent is game-system.
      final grandchild = _entry(
        id: 'grandchild-gst-cat-001',
        name: 'Inner Crusade Option',
        sourceFileId: _depCatFileId,
        profiles: const [],
        categories: [_category('Tyrannic War Veteran')],
      );
      final gstChild = _entry(
        id: 'child-gst-cat-d-001',
        name: 'Crusade Branch',
        sourceFileId: _gstFileId, // stop here
        profiles: const [],
        children: [grandchild],
      );

      final unitEntry = _entry(
        id: 'entry-cat-d-001',
        name: 'Test Subtree Unit',
        sourceFileId: _catFileId,
        profiles: [unitProf],
        children: [gstChild],
      );

      final bundle = _boundBundle(
        entries: [unitEntry, gstChild, grandchild],
        allProfiles: [unitProf],
      );

      final index = IndexService().buildIndex(bundle);
      final keywords = _keywordTokensFor(index, 'Test Subtree Unit');

      print('[TEST-cat-d] keywordTokens: $keywords');

      expect(
        keywords,
        isNot(contains('tyrannic war veteran')),
        reason: 'A category inside a subtree rooted at a game-system entry must '
            'not be collected, even if the category itself is in a dep-catalog '
            'entry. The traversal stop prunes the entire gst-rooted subtree.',
      );
    });
  });
}

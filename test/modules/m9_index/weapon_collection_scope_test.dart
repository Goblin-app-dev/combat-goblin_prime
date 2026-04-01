/// Weapon Collection Scope Tests
///
/// PURPOSE
/// -------
/// Permanent regression guards for _collectWeaponRefs traversal scope.
/// Locked after the fix in commit 399aabe that stopped traversal at
/// game-system-sourced entries.
///
/// THREE INVARIANTS
/// ----------------
///
///   a) LIBRARY-LINKED WEAPONS RETAINED
///      A unit entry whose direct profiles include weapons sourced from a
///      library/dependency catalog (sourceFileId != gameSystemFileId) keeps
///      those weapons. The fix must not strip legitimate catalog weapons.
///
///   b) GAME-SYSTEM BRANCH EXCLUDED
///      A unit entry that has a child entry sourced from the game system
///      (sourceFileId == gameSystemFileId) does NOT collect weapons from that
///      child. The Crusade / Legendary Relics / Vertebrax of Vodun chain is
///      the canonical example of what must be blocked.
///
///   c) DEPENDENCY CATALOG CHILDREN COLLECTED
///      A unit entry that has a child sourced from a dependency catalog
///      (not the game system) still collects weapons from that child. Normal
///      shared-library weapon entries must continue to work.
///
/// APPROACH
/// --------
/// All tests build minimal BoundPackBundle objects in-memory without catalog
/// fixture files. This makes the tests fast, hermetic, and independent of
/// fixture availability. No full M1→M9 pipeline is run.
///
/// RUNNING
/// -------
///   flutter test test/modules/m9_index/weapon_collection_scope_test.dart --reporter expanded

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

// ---------------------------------------------------------------------------
// Minimal in-memory BoundPackBundle factory
// ---------------------------------------------------------------------------
//
// Builds a minimal but structurally complete BoundPackBundle without running
// the full M1→M5 pipeline. All IDs, nodes, and entries are synthetic.
//
// File ID constants:
//   _gstFileId         — game system file
//   _catFileId         — primary catalog file
//   _libDepFileId      — library dependency catalog file
//   _depCatFileId      — second dependency catalog file

const _gstFileId = 'gst-test-0001';
const _catFileId = 'cat-test-0001';
const _libDepFileId = 'lib-dep-test-0001';
const _depCatFileId = 'dep-cat-test-0001';

/// Builds a minimal WrappedFile with a single root node.
WrappedFile _minimalWrappedFile(String fileId, SourceFileType type) {
  const rootNode = WrappedNode(
    ref: NodeRef(0),
    tagName: 'catalogue',
    attributes: {},
    parent: null,
    children: [],
    depth: 0,
    fileId: _catFileId, // placeholder — overridden per-file below
    fileType: SourceFileType.cat,
  );
  // Re-construct with correct fileId/fileType since WrappedNode is const.
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

/// Builds the minimal WrappedPackBundle used by all scope tests.
///
/// Contains:
///   - gameSystem  (fileId = _gstFileId)
///   - primaryCatalog  (fileId = _catFileId)
///   - dependencyCatalogs: [libDep, depCat]
WrappedPackBundle _minimalWrappedBundle() {
  return WrappedPackBundle(
    packId: 'test-pack',
    wrappedAt: DateTime(2026, 1, 1),
    gameSystem: _minimalWrappedFile(_gstFileId, SourceFileType.gst),
    primaryCatalog: _minimalWrappedFile(_catFileId, SourceFileType.cat),
    dependencyCatalogs: [
      _minimalWrappedFile(_libDepFileId, SourceFileType.cat),
      _minimalWrappedFile(_depCatFileId, SourceFileType.cat),
    ],
  );
}

/// Builds the minimal LinkedPackBundle wrapping the given WrappedPackBundle.
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

/// Builds a unit-type BoundProfile (typeName == 'unit').
///
/// An entry must have one of these for IndexService to create a UnitDoc.
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

/// Builds a ranged-weapon BoundProfile.
BoundProfile _weaponProfile({
  required String id,
  required String name,
  required String sourceFileId,
}) {
  return BoundProfile(
    id: id,
    name: name,
    typeId: 'type-wpn',
    typeName: 'Ranged Weapons',
    characteristics: const [
      (name: 'Range', value: '24"'),
      (name: 'A', value: '1'),
    ],
    sourceFileId: sourceFileId,
    sourceNode: const NodeRef(0),
  );
}

/// Builds a minimal BoundEntry (non-group, non-hidden).
BoundEntry _entry({
  required String id,
  required String name,
  required String sourceFileId,
  required List<BoundProfile> profiles,
  List<BoundEntry> children = const [],
}) {
  return BoundEntry(
    id: id,
    name: name,
    isGroup: false,
    isHidden: false,
    children: children,
    profiles: profiles,
    categories: const [],
    costs: const [],
    constraints: const [],
    sourceFileId: sourceFileId,
    sourceNode: const NodeRef(0),
  );
}

/// Builds a BoundPackBundle from a list of top-level entries and flat profiles.
///
/// [entries]  — top-level entries (unit entries go here, children nested inside)
/// [allProfiles] — flat list of ALL profiles (weapon + unit); used by
///                 _buildWeaponDocs to create WeaponDoc objects.
BoundPackBundle _boundBundle({
  required List<BoundEntry> entries,
  required List<BoundProfile> allProfiles,
  LinkedPackBundle? linkedBundle,
}) {
  final wrappedBundle = _minimalWrappedBundle();
  final linked = linkedBundle ?? _minimalLinkedBundle(wrappedBundle);
  return BoundPackBundle(
    packId: 'test-pack',
    boundAt: DateTime(2026, 1, 1),
    entries: entries,
    profiles: allProfiles,
    categories: const [],
    diagnostics: const [],
    linkedBundle: linked,
  );
}

// ---------------------------------------------------------------------------
// Helper: extract weapon doc IDs for a named unit from an IndexBundle
// ---------------------------------------------------------------------------

List<String> _weaponDocIdsFor(IndexBundle index, String unitName) {
  final units = index.findUnitsByName(unitName);
  if (units.isEmpty) return [];
  return units.first.weaponDocRefs;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('_collectWeaponRefs scope invariants', () {
    // ── Invariant a: library-linked weapons retained ─────────────────────────

    test(
        'a: unit with library-dep weapon profile retains that weapon', () {
      // Weapon profile is on the unit entry directly and sourced from a library
      // dependency catalog (not the game system).
      //
      // Expectation: weapon IS collected — the traversal stop only applies to
      // children whose sourceFileId == gameSystemFileId. Direct profiles on the
      // unit entry and catalog/dep-sourced children are always included.

      final wpnProfile = _weaponProfile(
        id: 'wpn-lib-001',
        name: 'Bolt Rifle',
        sourceFileId: _libDepFileId, // from library dep, not game system
      );
      final unitProf = _unitProfile(
        id: 'unit-prof-a',
        sourceFileId: _catFileId,
      );

      final unitEntry = _entry(
        id: 'entry-a-001',
        name: 'Test Warrior',
        sourceFileId: _catFileId,
        profiles: [unitProf, wpnProfile],
        children: const [],
      );

      final bundle = _boundBundle(
        entries: [unitEntry],
        allProfiles: [unitProf, wpnProfile],
      );

      final index = IndexService().buildIndex(bundle);
      final weaponRefs = _weaponDocIdsFor(index, 'Test Warrior');

      print('[TEST-a] weaponDocRefs: $weaponRefs');

      // The weapon from the library dep must be present.
      expect(
        weaponRefs,
        contains('weapon:wpn-lib-001'),
        reason: 'Library-dep weapon profile on unit entry must be collected. '
            'The traversal stop only applies to game-system-sourced CHILDREN, '
            'not to direct profiles on the unit entry itself.',
      );
    });

    // ── Invariant b: game-system branch children excluded ────────────────────

    test(
        'b: child entry sourced from game system does not contribute weapons', () {
      // The unit entry has:
      //   - A legitimate weapon directly (catalog-sourced) → must be collected
      //   - A child entry sourced from the game system with its own weapon → must NOT be collected
      //
      // This models the exact Crusade → Legendary Relics → Vertebrax of Vodun
      // chain that was over-collecting before the fix.

      final directWpn = _weaponProfile(
        id: 'wpn-direct-001',
        name: 'Heavy Bolter',
        sourceFileId: _catFileId,
      );
      final gstWpn = _weaponProfile(
        id: 'wpn-gst-001',
        name: 'Vertebrax Weapon',
        sourceFileId: _gstFileId, // from game system
      );
      final unitProf = _unitProfile(
        id: 'unit-prof-b',
        sourceFileId: _catFileId,
      );

      // Child entry sourced from game system — traversal must stop here.
      final gstChild = _entry(
        id: 'child-gst-001',
        name: 'Crusade Option',
        sourceFileId: _gstFileId,
        profiles: [gstWpn],
        children: const [],
      );

      final unitEntry = _entry(
        id: 'entry-b-001',
        name: 'Test Psyker',
        sourceFileId: _catFileId,
        profiles: [unitProf, directWpn],
        children: [gstChild],
      );

      final bundle = _boundBundle(
        entries: [unitEntry, gstChild],
        allProfiles: [unitProf, directWpn, gstWpn],
      );

      final index = IndexService().buildIndex(bundle);
      final weaponRefs = _weaponDocIdsFor(index, 'Test Psyker');

      print('[TEST-b] weaponDocRefs: $weaponRefs');

      // The direct weapon must still be present.
      expect(
        weaponRefs,
        contains('weapon:wpn-direct-001'),
        reason: 'Direct catalog-sourced weapon on unit entry must be collected.',
      );

      // The game-system child's weapon must NOT be present.
      expect(
        weaponRefs,
        isNot(contains('weapon:wpn-gst-001')),
        reason: 'Weapon from a game-system-sourced child entry must NOT be '
            'collected. This is the Vertebrax-of-Vodun over-collection fix. '
            'If this fails, the traversal stop at sourceFileId==gameSystemFileId '
            'has regressed in _collectWeaponRefs.',
      );
    });

    // ── Invariant c: dependency catalog child weapons collected ──────────────

    test(
        'c: child entry from dependency catalog contributes weapons normally', () {
      // A unit entry has a child entry sourced from a dependency catalog
      // (not the game system). This models shared library weapon entries
      // that are legitimately linked from faction catalogs.
      //
      // Expectation: dep-catalog child weapons ARE collected. Only game-system
      // children are blocked — all other catalog sources pass through.

      final depWpn = _weaponProfile(
        id: 'wpn-dep-001',
        name: 'Rending Claw',
        sourceFileId: _depCatFileId, // from dep catalog, not game system
      );
      final unitProf = _unitProfile(
        id: 'unit-prof-c',
        sourceFileId: _catFileId,
      );

      // Child entry sourced from dep catalog — traversal must continue.
      final depChild = _entry(
        id: 'child-dep-001',
        name: 'Weapon Option',
        sourceFileId: _depCatFileId,
        profiles: [depWpn],
        children: const [],
      );

      final unitEntry = _entry(
        id: 'entry-c-001',
        name: 'Test Claw Beast',
        sourceFileId: _catFileId,
        profiles: [unitProf],
        children: [depChild],
      );

      final bundle = _boundBundle(
        entries: [unitEntry, depChild],
        allProfiles: [unitProf, depWpn],
      );

      final index = IndexService().buildIndex(bundle);
      final weaponRefs = _weaponDocIdsFor(index, 'Test Claw Beast');

      print('[TEST-c] weaponDocRefs: $weaponRefs');

      expect(
        weaponRefs,
        contains('weapon:wpn-dep-001'),
        reason: 'Weapon from a dependency-catalog-sourced child entry must be '
            'collected. Only children whose sourceFileId equals the game system '
            'file ID are stopped. Dep-catalog children pass through normally.',
      );
    });

    // ── Invariant d: game-system traversal stop is file-ID exact match ───────

    test(
        'd: traversal stop is exact fileId match — no partial blocking', () {
      // Regression guard: the stop condition is `child.sourceFileId == gameSystemFileId`.
      // A child whose fileId merely CONTAINS the game system ID substring must
      // NOT be stopped. Only an exact match stops traversal.

      // Synthetic file ID that contains the GST id as a substring but is distinct.
      const nearGstFileId = '${_gstFileId}-extended-catalog';

      final nearGstWpn = _weaponProfile(
        id: 'wpn-near-gst-001',
        name: 'Valid Weapon',
        sourceFileId: nearGstFileId,
      );
      final unitProf = _unitProfile(
        id: 'unit-prof-d',
        sourceFileId: _catFileId,
      );

      final nearGstChild = _entry(
        id: 'child-near-gst-001',
        name: 'Near GST Option',
        sourceFileId: nearGstFileId,
        profiles: [nearGstWpn],
        children: const [],
      );

      final unitEntry = _entry(
        id: 'entry-d-001',
        name: 'Test Precision Unit',
        sourceFileId: _catFileId,
        profiles: [unitProf],
        children: [nearGstChild],
      );

      final bundle = _boundBundle(
        entries: [unitEntry, nearGstChild],
        allProfiles: [unitProf, nearGstWpn],
      );

      final index = IndexService().buildIndex(bundle);
      final weaponRefs = _weaponDocIdsFor(index, 'Test Precision Unit');

      print('[TEST-d] weaponDocRefs: $weaponRefs');

      expect(
        weaponRefs,
        contains('weapon:wpn-near-gst-001'),
        reason: 'Child with a fileId that only contains the GST id as a '
            'substring must NOT be blocked. The stop is an exact string match.',
      );
    });

    // ── Invariant e: deeply nested dep-catalog weapons collected ─────────────

    test(
        'e: weapons in deeply nested dep-catalog entries are collected', () {
      // Tests that recursion continues through multiple levels of dep-catalog
      // children. The weapon is two levels deep inside dep-catalog-sourced
      // entries — both must be traversed.

      final deepWpn = _weaponProfile(
        id: 'wpn-deep-001',
        name: 'Deep Fang',
        sourceFileId: _depCatFileId,
      );
      final unitProf = _unitProfile(
        id: 'unit-prof-e',
        sourceFileId: _catFileId,
      );

      final deepGrandchild = _entry(
        id: 'grandchild-dep-001',
        name: 'Weapon Option Subgroup',
        sourceFileId: _depCatFileId,
        profiles: [deepWpn],
        children: const [],
      );
      final depChild = _entry(
        id: 'child-dep-e-001',
        name: 'Weapon Group',
        sourceFileId: _depCatFileId,
        profiles: const [],
        children: [deepGrandchild],
      );

      final unitEntry = _entry(
        id: 'entry-e-001',
        name: 'Test Deep Unit',
        sourceFileId: _catFileId,
        profiles: [unitProf],
        children: [depChild],
      );

      final bundle = _boundBundle(
        entries: [unitEntry, depChild, deepGrandchild],
        allProfiles: [unitProf, deepWpn],
      );

      final index = IndexService().buildIndex(bundle);
      final weaponRefs = _weaponDocIdsFor(index, 'Test Deep Unit');

      print('[TEST-e] weaponDocRefs: $weaponRefs');

      expect(
        weaponRefs,
        contains('weapon:wpn-deep-001'),
        reason: 'Weapon two levels deep in dep-catalog-sourced entries must '
            'still be collected. Traversal must recurse through all non-gst entries.',
      );
    });

    // ── Invariant f: game-system stop blocks full subtree ────────────────────

    test(
        'f: game-system stop blocks the entire subtree below that child', () {
      // A game-system child has its own dep-catalog grandchildren with weapons.
      // Even those grandchildren must be blocked — the stop at the game-system
      // entry boundary prunes the entire subtree below that point.

      final subtreeWpn = _weaponProfile(
        id: 'wpn-subtree-001',
        name: 'Subtree Weapon',
        sourceFileId: _depCatFileId, // inside a gst-rooted subtree
      );
      const unitProf = BoundProfile(
        id: 'unit-prof-f',
        name: 'Test Unit Profile',
        typeId: 'type-unit',
        typeName: 'unit',
        characteristics: [(name: 'M', value: '6"')],
        sourceFileId: _catFileId,
        sourceNode: NodeRef(0),
      );

      // Grandchild is dep-catalog sourced, but its parent is game-system.
      final grandchild = _entry(
        id: 'grandchild-gst-f-001',
        name: 'Inner Relic',
        sourceFileId: _depCatFileId,
        profiles: [subtreeWpn],
        children: const [],
      );
      final gstChild = _entry(
        id: 'child-gst-f-001',
        name: 'Crusade Branch',
        sourceFileId: _gstFileId, // stop here
        profiles: const [],
        children: [grandchild],
      );

      final unitEntry = _entry(
        id: 'entry-f-001',
        name: 'Test Subtree Unit',
        sourceFileId: _catFileId,
        profiles: [unitProf],
        children: [gstChild],
      );

      final bundle = _boundBundle(
        entries: [unitEntry, gstChild, grandchild],
        allProfiles: [unitProf, subtreeWpn],
      );

      final index = IndexService().buildIndex(bundle);
      final weaponRefs = _weaponDocIdsFor(index, 'Test Subtree Unit');

      print('[TEST-f] weaponDocRefs: $weaponRefs');

      expect(
        weaponRefs,
        isNot(contains('weapon:wpn-subtree-001')),
        reason: 'A weapon inside a subtree rooted at a game-system entry must '
            'not be collected, even if the weapon itself is in a dep-catalog '
            'entry. The traversal stop prunes the entire gst-rooted subtree.',
      );
    });
  });
}

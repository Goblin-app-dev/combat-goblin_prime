/// Rule Collection Scope Tests
///
/// PURPOSE
/// -------
/// Permanent regression guards for rule (_collectRuleRefs) inheritance.
/// Locked after the fix adding _findRuleAncestor that allows nested model
/// entries (e.g. "Bladeguard Veteran" inside "Bladeguard Veteran Squad") to
/// inherit rule profiles from their nearest ancestor datasheet entry.
///
/// FOUR INVARIANTS
/// ---------------
///
///   a) POSITIVE INHERITANCE
///      A nested model entry with no ability profiles of its own inherits
///      rule refs from the nearest ancestor entry that has ability profiles.
///      Models Bladeguard Veteran / Eradicator / Carnifex patterns.
///
///   b) NO INHERITANCE FOR STANDALONE UNIT
///      A top-level unit entry (no parent, or parent has its own unit profile)
///      gets only its own rules — ancestor inheritance does not fire.
///
///   c) NO GAME-SYSTEM BOUNDARY CROSSING
///      If the nearest ancestor with ability profiles is sourced from the game
///      system file, inheritance stops and no rules are collected. Game-system
///      entries are campaign-wide structure, not unit rule surfaces.
///
///   d) NO DUPLICATION
///      If an entry already has ability profiles of its own, ancestor
///      inheritance is NOT triggered — the entry's own rules are used as-is
///      with no merging from ancestors.
///
/// APPROACH
/// --------
/// All tests build minimal BoundPackBundle objects in-memory without catalog
/// fixture files. Fast, hermetic, and independent of fixture availability.
/// No full M1→M9 pipeline is run.
///
/// RUNNING
/// -------
///   flutter test test/modules/m9_index/rule_collection_scope_test.dart --reporter expanded

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

// ---------------------------------------------------------------------------
// File ID constants
// ---------------------------------------------------------------------------

const _gstFileId = 'gst-rule-test-0001';
const _catFileId = 'cat-rule-test-0001';

// ---------------------------------------------------------------------------
// Minimal in-memory BoundPackBundle factory
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
    packId: 'test-pack',
    wrappedAt: DateTime(2026, 1, 1),
    gameSystem: _minimalWrappedFile(_gstFileId, SourceFileType.gst),
    primaryCatalog: _minimalWrappedFile(_catFileId, SourceFileType.cat),
    dependencyCatalogs: const [],
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

/// Builds a unit-type BoundProfile.
BoundProfile _unitProfile({required String id, required String sourceFileId}) {
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

/// Builds an ability-type BoundProfile.
BoundProfile _abilityProfile({
  required String id,
  required String name,
  required String sourceFileId,
}) {
  return BoundProfile(
    id: id,
    name: name,
    typeId: 'type-ability',
    typeName: 'Abilities',
    characteristics: const [
      (name: 'Description', value: 'Test rule description.'),
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

/// Assembles a BoundPackBundle from a flat list of top-level entries and
/// all profiles (so M9 can build RuleDocs from them).
BoundPackBundle _boundBundle({
  required List<BoundEntry> entries,
  required List<BoundProfile> allProfiles,
}) {
  final wrappedBundle = _minimalWrappedBundle();
  final linked = _minimalLinkedBundle(wrappedBundle);
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
// Helper: extract rule doc IDs for a named unit from an IndexBundle
// ---------------------------------------------------------------------------

List<String> _ruleDocIdsFor(IndexBundle index, String unitName) {
  final units = index.findUnitsByName(unitName);
  if (units.isEmpty) return [];
  return units.first.ruleDocRefs;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('_collectRuleRefs / _findRuleAncestor scope invariants', () {
    // ── Invariant a: positive inheritance ────────────────────────────────────

    test('a: nested model with no rules inherits from parent datasheet entry',
        () {
      // Models the Bladeguard Veteran pattern:
      //   Parent entry "Bladeguard Veteran Squad" — has unit profile + rule profiles
      //     Child entry "Bladeguard Veteran"      — has unit profile, NO rule profiles
      //
      // Expectation: the child unit inherits rule refs from the parent.

      final oathProfile = _abilityProfile(
        id: 'rule-oath-001',
        name: 'Oath of Moment',
        sourceFileId: _catFileId,
      );
      final vowsProfile = _abilityProfile(
        id: 'rule-vows-001',
        name: 'Templar Vows',
        sourceFileId: _catFileId,
      );
      final parentUnitProf =
          _unitProfile(id: 'unit-prof-parent-a', sourceFileId: _catFileId);
      final childUnitProf =
          _unitProfile(id: 'unit-prof-child-a', sourceFileId: _catFileId);

      // Child has a unit profile but no rule profiles.
      final childEntry = _entry(
        id: 'entry-bgv-model-001',
        name: 'Bladeguard Veteran',
        sourceFileId: _catFileId,
        profiles: [childUnitProf],
        children: const [],
      );

      // Parent has a unit profile AND rule profiles.
      final parentEntry = _entry(
        id: 'entry-bgv-squad-001',
        name: 'Bladeguard Veteran Squad',
        sourceFileId: _catFileId,
        profiles: [parentUnitProf, oathProfile, vowsProfile],
        children: [childEntry],
      );

      // Both entries are in boundPack.entries (the flat top-level list M9
      // iterates). The parent-child relationship is established via
      // parentEntry.children so that parentByChildId maps childEntry → parent.
      final bundle = _boundBundle(
        entries: [parentEntry, childEntry],
        allProfiles: [parentUnitProf, childUnitProf, oathProfile, vowsProfile],
      );

      final index = IndexService().buildIndex(bundle);
      final ruleRefs = _ruleDocIdsFor(index, 'Bladeguard Veteran');

      print('[TEST-a] ruleDocRefs for Bladeguard Veteran: $ruleRefs');

      expect(
        ruleRefs,
        contains('rule:rule-oath-001'),
        reason: 'Nested model entry must inherit Oath of Moment from parent '
            'datasheet entry when the model has no rule profiles of its own.',
      );
      expect(
        ruleRefs,
        contains('rule:rule-vows-001'),
        reason: 'Nested model entry must inherit Templar Vows from parent '
            'datasheet entry when the model has no rule profiles of its own.',
      );
    });

    // ── Invariant b: no inheritance for standalone unit ──────────────────────

    test('b: standalone unit with its own rules is not affected by inheritance',
        () {
      // Models the Captain pattern: top-level entry with its own rule profiles.
      // Ancestor inheritance must not fire — only the entry's own rules appear.

      final tacticalProfile = _abilityProfile(
        id: 'rule-tactical-001',
        name: 'Rites of Battle',
        sourceFileId: _catFileId,
      );
      final captainUnitProf =
          _unitProfile(id: 'unit-prof-captain', sourceFileId: _catFileId);

      final captainEntry = _entry(
        id: 'entry-captain-001',
        name: 'Captain',
        sourceFileId: _catFileId,
        profiles: [captainUnitProf, tacticalProfile],
        children: const [],
      );

      final bundle = _boundBundle(
        entries: [captainEntry],
        allProfiles: [captainUnitProf, tacticalProfile],
      );

      final index = IndexService().buildIndex(bundle);
      final ruleRefs = _ruleDocIdsFor(index, 'Captain');

      print('[TEST-b] ruleDocRefs for Captain: $ruleRefs');

      expect(
        ruleRefs,
        contains('rule:rule-tactical-001'),
        reason: 'Standalone unit with its own rules must collect them normally.',
      );
      expect(
        ruleRefs,
        hasLength(1),
        reason: 'Standalone unit must have exactly its own rules — no spurious '
            'ancestor rules must appear (no parent exists here).',
      );
    });

    // ── Invariant c: no game-system boundary crossing ────────────────────────

    test('c: game-system-sourced ancestor does not contribute rules', () {
      // A nested model entry has no rule profiles of its own. Its parent
      // entry is sourced from the game system file. Inheritance must stop —
      // game-system entries are campaign-wide structure, not unit rule surfaces.
      //
      // Expectation: child unit gets zero rule refs.

      final gstRuleProfile = _abilityProfile(
        id: 'rule-gst-001',
        name: 'Campaign Rule',
        sourceFileId: _gstFileId, // game system
      );
      final gstUnitProf =
          _unitProfile(id: 'unit-prof-gst-parent', sourceFileId: _gstFileId);
      final childUnitProf =
          _unitProfile(id: 'unit-prof-child-c', sourceFileId: _catFileId);

      final childEntry = _entry(
        id: 'entry-child-c-001',
        name: 'Campaign Model',
        sourceFileId: _catFileId,
        profiles: [childUnitProf],
        children: const [],
      );

      // Parent is sourced from the game system.
      final gstParentEntry = _entry(
        id: 'entry-gst-parent-c-001',
        name: 'Campaign Datasheet',
        sourceFileId: _gstFileId,
        profiles: [gstUnitProf, gstRuleProfile],
        children: [childEntry],
      );

      final bundle = _boundBundle(
        entries: [gstParentEntry],
        allProfiles: [gstUnitProf, childUnitProf, gstRuleProfile],
      );

      final index = IndexService().buildIndex(bundle);
      final ruleRefs = _ruleDocIdsFor(index, 'Campaign Model');

      print('[TEST-c] ruleDocRefs for Campaign Model: $ruleRefs');

      expect(
        ruleRefs,
        isNot(contains('rule:rule-gst-001')),
        reason: 'Rules from a game-system-sourced ancestor must never appear '
            'on a unit rule surface. _findRuleAncestor must stop at the '
            'game-system boundary.',
      );
    });

    // ── Invariant d: no duplication ──────────────────────────────────────────

    test('d: entry with its own rules does not also collect ancestor rules', () {
      // An entry has its own rule profile AND its parent also has rule profiles.
      // The entry's own rules must be used as-is; ancestor rules must NOT be
      // merged in. No duplication, no over-collection.

      final entryRuleProfile = _abilityProfile(
        id: 'rule-entry-d-001',
        name: 'Shield of Faith',
        sourceFileId: _catFileId,
      );
      final ancestorRuleProfile = _abilityProfile(
        id: 'rule-ancestor-d-001',
        name: 'Oath of Moment',
        sourceFileId: _catFileId,
      );
      final parentUnitProf =
          _unitProfile(id: 'unit-prof-parent-d', sourceFileId: _catFileId);
      final childUnitProf =
          _unitProfile(id: 'unit-prof-child-d', sourceFileId: _catFileId);

      // Child has its own rule profile.
      final childEntry = _entry(
        id: 'entry-child-d-001',
        name: 'Sister Superior',
        sourceFileId: _catFileId,
        profiles: [childUnitProf, entryRuleProfile],
        children: const [],
      );

      // Parent also has rule profiles.
      final parentEntry = _entry(
        id: 'entry-parent-d-001',
        name: 'Battle Sisters Squad',
        sourceFileId: _catFileId,
        profiles: [parentUnitProf, ancestorRuleProfile],
        children: [childEntry],
      );

      // Both entries in the flat top-level list; parent.children establishes
      // the relationship for parentByChildId.
      final bundle = _boundBundle(
        entries: [parentEntry, childEntry],
        allProfiles: [
          parentUnitProf,
          childUnitProf,
          entryRuleProfile,
          ancestorRuleProfile,
        ],
      );

      final index = IndexService().buildIndex(bundle);
      final ruleRefs = _ruleDocIdsFor(index, 'Sister Superior');

      print('[TEST-d] ruleDocRefs for Sister Superior: $ruleRefs');

      // Entry's own rule must be present.
      expect(
        ruleRefs,
        contains('rule:rule-entry-d-001'),
        reason: "Entry's own rule profile must always be collected.",
      );

      // Ancestor rule must NOT bleed in — entry already had rules.
      expect(
        ruleRefs,
        isNot(contains('rule:rule-ancestor-d-001')),
        reason: 'Ancestor rules must NOT be merged when entry already has its '
            'own ability profiles. Inheritance only fires when the entry has '
            'zero ability profiles.',
      );

      // Exactly one rule ref — no duplication.
      expect(
        ruleRefs,
        hasLength(1),
        reason: 'No duplication: exactly the entry own rule, nothing extra.',
      );
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m6_evaluate/m6_evaluate.dart';

/// Deterministic SelectionSnapshot implementation for E2E testing.
///
/// Supports two modes:
/// 1. Minimal single-root snapshot (for pipeline testing)
/// 2. Empty snapshot (for EMPTY_SNAPSHOT notice testing)
class DeterministicSnapshot implements SelectionSnapshot {
  final List<_SnapshotEntry> _entries;
  final Map<String, _SnapshotEntry> _byId;

  DeterministicSnapshot._(this._entries) : _byId = {} {
    for (final e in _entries) {
      _byId[e.selectionId] = e;
    }
  }

  /// Creates an empty snapshot (orderedSelections returns empty list).
  factory DeterministicSnapshot.empty() => DeterministicSnapshot._([]);

  /// Creates a minimal deterministic snapshot with a single root selection.
  ///
  /// The root entry is chosen deterministically:
  /// - Sort entry IDs ascending
  /// - Take the first entry ID
  factory DeterministicSnapshot.singleRoot(BoundPackBundle bundle) {
    if (bundle.entries.isEmpty) {
      return DeterministicSnapshot.empty();
    }

    // Sort entries by ID for determinism
    final sortedEntries = bundle.entries.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    final firstEntry = sortedEntries.first;

    return DeterministicSnapshot._([
      _SnapshotEntry(
        selectionId: 'sel_root',
        entryId: firstEntry.id,
        parentId: null,
        childIds: const [],
        count: 1,
        isForceRoot: true,
      ),
    ]);
  }

  /// Creates a deterministic roster snapshot with multiple selections.
  ///
  /// Structure:
  /// - 1 force root entry (first UNIT entry with M/T/W-style stats)
  /// - Up to [maxChildren] child selections under the root
  /// - Each child is a distinct UNIT entry (not weapon/upgrade)
  ///
  /// This simulates a realistic roster with actual unit stats.
  factory DeterministicSnapshot.roster(
    BoundPackBundle bundle, {
    int maxChildren = 5,
  }) {
    if (bundle.entries.isEmpty) {
      return DeterministicSnapshot.empty();
    }

    // Sort entries by ID for determinism
    final sortedEntries = bundle.entries.toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    // Helper to check if profile looks like a unit statline (has M, T, or W)
    bool hasUnitStats(BoundEntry entry) {
      for (final profile in entry.profiles) {
        final charNames = profile.characteristics
            .map((c) => c.name.toUpperCase())
            .toSet();
        // Unit profiles typically have M (Move), T (Toughness), W (Wounds)
        if (charNames.contains('M') || charNames.contains('T') || charNames.contains('W')) {
          return true;
        }
      }
      return false;
    }

    // Helper to check if entry looks like a weapon (has Range, S, AP, D)
    bool looksLikeWeapon(BoundEntry entry) {
      for (final profile in entry.profiles) {
        final charNames = profile.characteristics
            .map((c) => c.name.toUpperCase())
            .toSet();
        // Weapon profiles typically have Range, S (Strength), AP, D (Damage)
        if (charNames.contains('RANGE') && charNames.contains('AP')) {
          return true;
        }
      }
      return false;
    }

    // Filter to entries that:
    // 1. Have unit-like stats (M/T/W)
    // 2. Don't look like weapons (Range/AP)
    final unitEntries = sortedEntries.where((e) {
      return hasUnitStats(e) && !looksLikeWeapon(e);
    }).toList();

    // Fall back to entries with any characteristics if no unit-like entries found
    final entriesWithStats = sortedEntries.where((e) {
      return e.profiles.any((p) => p.characteristics.isNotEmpty);
    }).toList();

    // Choose candidates: prefer units, fall back to entries with stats, then all
    final candidates = unitEntries.isNotEmpty
        ? unitEntries
        : entriesWithStats.isNotEmpty
            ? entriesWithStats
            : sortedEntries;

    // First entry is force root
    final rootEntry = candidates.first;
    final childEntries = candidates.skip(1).take(maxChildren).toList();

    // Build child selection IDs
    final childIds = <String>[];
    for (var i = 0; i < childEntries.length; i++) {
      childIds.add('sel_child_$i');
    }

    // Build entries list
    final entries = <_SnapshotEntry>[
      _SnapshotEntry(
        selectionId: 'sel_root',
        entryId: rootEntry.id,
        parentId: null,
        childIds: childIds,
        count: 1,
        isForceRoot: true,
      ),
    ];

    // Add child entries
    for (var i = 0; i < childEntries.length; i++) {
      entries.add(_SnapshotEntry(
        selectionId: 'sel_child_$i',
        entryId: childEntries[i].id,
        parentId: 'sel_root',
        childIds: const [],
        count: 1,
        isForceRoot: false,
      ));
    }

    return DeterministicSnapshot._(entries);
  }

  @override
  List<String> orderedSelections() =>
      _entries.map((e) => e.selectionId).toList();

  @override
  String entryIdFor(String selectionId) => _byId[selectionId]!.entryId;

  @override
  String? parentOf(String selectionId) => _byId[selectionId]!.parentId;

  @override
  List<String> childrenOf(String selectionId) =>
      _byId[selectionId]!.childIds;

  @override
  int countFor(String selectionId) => _byId[selectionId]!.count;

  @override
  bool isForceRoot(String selectionId) => _byId[selectionId]!.isForceRoot;
}

class _SnapshotEntry {
  final String selectionId;
  final String entryId;
  final String? parentId;
  final List<String> childIds;
  final int count;
  final bool isForceRoot;

  const _SnapshotEntry({
    required this.selectionId,
    required this.entryId,
    required this.parentId,
    required this.childIds,
    required this.count,
    required this.isForceRoot,
  });
}

/// Runs the full M1→M6 pipeline and returns all phase outputs.
Future<_PipelineResult> runPipeline() async {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  // Dependency file mapping
  final dependencyFiles = <String, String>{
    'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
    '7481-280e-b55e-7867': 'test/Library - Titans.cat',
    '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
    'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
  };

  // M1 Acquire
  final gameSystemBytes =
      await File('test/Warhammer 40,000.gst').readAsBytes();
  final primaryCatalogBytes =
      await File('test/Imperium - Space Marines.cat').readAsBytes();

  final rawBundle = await AcquireService().buildBundle(
    gameSystemBytes: gameSystemBytes,
    gameSystemExternalFileName: 'Warhammer 40,000.gst',
    primaryCatalogBytes: primaryCatalogBytes,
    primaryCatalogExternalFileName: 'Imperium - Space Marines.cat',
    requestDependencyBytes: (targetId) async {
      final path = dependencyFiles[targetId];
      if (path == null) return null;
      return await File(path).readAsBytes();
    },
    source: testSource,
  );

  // M2 Parse
  final parsedBundle = await ParseService().parseBundle(rawBundle: rawBundle);

  // M3 Wrap
  final wrappedBundle =
      await WrapService().wrapBundle(parsedBundle: parsedBundle);

  // M4 Link
  final linkedBundle =
      await LinkService().linkBundle(wrappedBundle: wrappedBundle);

  // M5 Bind
  final boundBundle =
      await BindService().bindBundle(linkedBundle: linkedBundle);

  return _PipelineResult(
    rawBundle: rawBundle,
    parsedBundle: parsedBundle,
    wrappedBundle: wrappedBundle,
    linkedBundle: linkedBundle,
    boundBundle: boundBundle,
  );
}

class _PipelineResult {
  final RawPackBundle rawBundle;
  final ParsedPackBundle parsedBundle;
  final WrappedPackBundle wrappedBundle;
  final LinkedPackBundle linkedBundle;
  final BoundPackBundle boundBundle;

  _PipelineResult({
    required this.rawBundle,
    required this.parsedBundle,
    required this.wrappedBundle,
    required this.linkedBundle,
    required this.boundBundle,
  });
}

/// Prints the deterministic human-readable pipeline report.
void printPipelineReport(
  BoundPackBundle boundBundle,
  EvaluationReport report,
) {
  print('');
  print('=' * 70);
  print('M1→M6 PIPELINE E2E REPORT');
  print('=' * 70);

  // Section 1: Pipeline summary counts
  print('');
  print('--- PIPELINE SUMMARY ---');
  print('Pack ID: ${boundBundle.packId}');
  print('');
  print('M5 Bind Counts:');
  print('  Entries:      ${boundBundle.entries.length}');
  print('  Profiles:     ${boundBundle.profiles.length}');
  print('  Categories:   ${boundBundle.categories.length}');
  print('  Diagnostics:  ${boundBundle.diagnostics.length}');
  print('');
  print('M6 Evaluate Counts:');
  print('  Total evaluations:  ${report.summary.totalEvaluations}');
  print('  Satisfied:          ${report.summary.satisfiedCount}');
  print('  Violated:           ${report.summary.violatedCount}');
  print('  Not applicable:     ${report.summary.notApplicableCount}');
  print('  Error:              ${report.summary.errorCount}');
  print('  Warnings:           ${report.warnings.length}');
  print('  Notices:            ${report.notices.length}');

  // Section 2: Unit stats proof (first 5 entries sorted by ID)
  print('');
  print('--- UNIT STATS (First 5 Entries by ID) ---');

  final sortedEntries = boundBundle.entries.toList()
    ..sort((a, b) => a.id.compareTo(b.id));

  for (var i = 0; i < sortedEntries.length && i < 5; i++) {
    final entry = sortedEntries[i];
    print(
      '  [${i + 1}] ${_truncate(entry.name, 30)} | '
      'id=${_truncate(entry.id, 20)} | '
      'profiles=${entry.profiles.length} | '
      'constraints=${entry.constraints.length} | '
      'categories=${entry.categories.length}',
    );
  }

  if (sortedEntries.length > 5) {
    print('  ... and ${sortedEntries.length - 5} more entries');
  }

  // Section 3: Warning codes summary (grouped by code, sorted alphabetically)
  print('');
  print('--- WARNING CODES SUMMARY ---');

  final warningCounts = <String, int>{};
  for (final w in report.warnings) {
    warningCounts[w.code] = (warningCounts[w.code] ?? 0) + 1;
  }

  final sortedCodes = warningCounts.keys.toList()..sort();
  final codesToShow = sortedCodes.take(10).toList();

  if (codesToShow.isEmpty) {
    print('  (no warnings)');
  } else {
    for (final code in codesToShow) {
      print('  $code: ${warningCounts[code]}');
    }
    if (sortedCodes.length > 10) {
      print('  ... and ${sortedCodes.length - 10} more warning codes');
    }
  }

  print('');
  print('=' * 70);
  print('');
}

/// Truncates a string to maxLen, adding "..." if truncated.
String _truncate(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  return '${s.substring(0, maxLen - 3)}...';
}

// =============================================================================
// ROSTER-STYLE OUTPUT HELPERS
// =============================================================================

/// Characteristic name alias map for standardized output.
/// Maps common aliases to canonical names.
const _characteristicAliases = <String, String>{
  'move': 'M',
  'movement': 'M',
  'm': 'M',
  'toughness': 'T',
  't': 'T',
  'wounds': 'W',
  'w': 'W',
  'save': 'Sv',
  'sv': 'Sv',
  'armor save': 'Sv',
  'leadership': 'Ld',
  'ld': 'Ld',
  'objective control': 'OC',
  'oc': 'OC',
  'attacks': 'A',
  'a': 'A',
  'strength': 'S',
  's': 'S',
  'ap': 'AP',
  'armor penetration': 'AP',
  'damage': 'D',
  'd': 'D',
  'range': 'Range',
  'ballistic skill': 'BS',
  'bs': 'BS',
  'weapon skill': 'WS',
  'ws': 'WS',
};

/// Normalizes a characteristic name using aliases.
String _normalizeCharacteristicName(String name) {
  final lower = name.toLowerCase().trim();
  return _characteristicAliases[lower] ?? name;
}

/// Keywords for identifying main stat profiles (case-insensitive).
const _mainStatProfileKeywords = ['unit', 'model', 'character'];

/// Keywords for identifying weapon profiles (case-insensitive).
const _weaponProfileKeywords = ['weapon', 'ranged', 'melee'];

/// Canonical stat characteristic names (uppercase for comparison).
const _unitStatKeys = {'M', 'T', 'W'};

/// Helper to get uppercase characteristic names from a profile.
Set<String> _getCharNames(BoundProfile profile) {
  return profile.characteristics.map((c) => c.name.toUpperCase()).toSet();
}

/// Finds the main stat profile for an entry using priority order.
///
/// Priority (deterministic, no semantics):
/// 1. Profiles where typeName == "Unit" (case-insensitive)
/// 2. Profiles where characteristics contain all of M, T, W
/// 3. Profiles where characteristics contain any of M, T, W
/// 4. First profile with any characteristics
/// 5. First profile (even if no characteristics)
///
/// Tie-break: stable sort by (profileId, profileName).
BoundProfile? _findMainStatProfile(BoundEntry entry) {
  if (entry.profiles.isEmpty) return null;

  // Sort profiles deterministically for tie-breaking
  final sortedProfiles = entry.profiles.toList()
    ..sort((a, b) {
      final idCmp = a.id.compareTo(b.id);
      if (idCmp != 0) return idCmp;
      return a.name.compareTo(b.name);
    });

  // Priority 1: typeName == "Unit" (case-insensitive)
  for (final profile in sortedProfiles) {
    final typeLower = (profile.typeName ?? '').toLowerCase();
    if (typeLower == 'unit') {
      return profile;
    }
  }

  // Priority 2: profiles with ALL of M, T, W
  for (final profile in sortedProfiles) {
    final charNames = _getCharNames(profile);
    if (_unitStatKeys.every((k) => charNames.contains(k))) {
      return profile;
    }
  }

  // Priority 3: profiles with ANY of M, T, W
  for (final profile in sortedProfiles) {
    final charNames = _getCharNames(profile);
    if (_unitStatKeys.any((k) => charNames.contains(k))) {
      return profile;
    }
  }

  // Priority 4: first profile with any characteristics
  for (final profile in sortedProfiles) {
    if (profile.characteristics.isNotEmpty) {
      return profile;
    }
  }

  // Priority 5: first profile (even if no characteristics)
  return sortedProfiles.first;
}

/// Gets weapon profiles for an entry.
List<BoundProfile> _getWeaponProfiles(BoundEntry entry) {
  final weapons = <BoundProfile>[];
  for (final profile in entry.profiles) {
    final typeLower = (profile.typeName ?? '').toLowerCase();
    final nameLower = profile.name.toLowerCase();
    final isWeapon = _weaponProfileKeywords.any(
      (kw) => typeLower.contains(kw) || nameLower.contains(kw),
    );
    if (isWeapon) {
      weapons.add(profile);
    }
  }
  // Sort by name for determinism
  weapons.sort((a, b) => a.name.compareTo(b.name));
  return weapons;
}

/// Formats characteristics into a stat line string.
String _formatStatLine(BoundProfile profile) {
  if (profile.characteristics.isEmpty) return '(no stats)';

  final parts = <String>[];
  for (final c in profile.characteristics) {
    final name = _normalizeCharacteristicName(c.name);
    parts.add('$name:${c.value}');
  }
  return parts.join(' | ');
}

/// Prints a single unit card for a selection.
void _printUnitCard({
  required BoundPackBundle bundle,
  required SelectionSnapshot snapshot,
  required String selectionId,
  required int indent,
  required int cardNumber,
}) {
  final prefix = '  ' * indent;
  final entryId = snapshot.entryIdFor(selectionId);
  final entry = bundle.entryById(entryId);

  if (entry == null) {
    print('$prefix[$cardNumber] UNKNOWN ENTRY (selId=$selectionId, entryId=$entryId)');
    return;
  }

  final count = snapshot.countFor(selectionId);
  final countSuffix = count > 1 ? ' x$count' : '';
  final forceRootMarker = snapshot.isForceRoot(selectionId) ? ' [ROOT]' : '';

  // Print entry name with IDs for debugging
  print('$prefix[$cardNumber] ${entry.name}$countSuffix$forceRootMarker');
  print('$prefix    (selId=$selectionId, entryId=${_truncate(entryId, 24)})');

  // Debug: show profile counts
  final profileCount = entry.profiles.length;
  final profilesWithChars = entry.profiles.where((p) => p.characteristics.isNotEmpty).length;
  print('$prefix    Profiles: $profileCount total, $profilesWithChars with characteristics');

  // Debug: show first 3 profiles
  for (var i = 0; i < entry.profiles.length && i < 3; i++) {
    final p = entry.profiles[i];
    print('$prefix      [$i] type="${p.typeName ?? '(none)'}" name="${p.name}" chars=${p.characteristics.length}');
  }
  if (entry.profiles.length > 3) {
    print('$prefix      ... and ${entry.profiles.length - 3} more profiles');
  }

  // Main stat profile (first with characteristics)
  final mainProfile = _findMainStatProfile(entry);
  if (mainProfile != null && mainProfile.characteristics.isNotEmpty) {
    print('$prefix    Stats: ${_formatStatLine(mainProfile)}');
  } else if (mainProfile != null) {
    print('$prefix    Stats: (profile exists but no characteristics)');
  } else {
    print('$prefix    Stats: (no profiles)');
  }

  // Weapon profiles
  final weapons = _getWeaponProfiles(entry);
  if (weapons.isNotEmpty) {
    print('$prefix    Weapons:');
    for (final weapon in weapons.take(5)) {
      print('$prefix      - ${weapon.name}: ${_formatStatLine(weapon)}');
    }
    if (weapons.length > 5) {
      print('$prefix      ... and ${weapons.length - 5} more weapons');
    }
  }

  // Child selections (recursive)
  final childIds = snapshot.childrenOf(selectionId);
  if (childIds.isNotEmpty) {
    var childNumber = 1;
    for (final childId in childIds) {
      _printUnitCard(
        bundle: bundle,
        snapshot: snapshot,
        selectionId: childId,
        indent: indent + 1,
        cardNumber: childNumber++,
      );
    }
  }
}

/// Prints the full roster section showing unit cards with stats.
void _printRosterSection({
  required BoundPackBundle bundle,
  required SelectionSnapshot snapshot,
}) {
  print('');
  print('=' * 70);
  print('ROSTER-STYLE OUTPUT');
  print('=' * 70);

  // Bundle-level summary
  final totalEntries = bundle.entries.length;
  final entriesWithProfiles = bundle.entries.where((e) => e.profiles.isNotEmpty).length;
  final entriesWithStats = bundle.entries.where((e) =>
      e.profiles.any((p) => p.characteristics.isNotEmpty)).length;
  final totalProfiles = bundle.profiles.length;

  print('');
  print('--- BUNDLE SUMMARY ---');
  print('Total entries: $totalEntries');
  print('Entries with profiles: $entriesWithProfiles');
  print('Entries with characteristics: $entriesWithStats');
  print('Total profiles in bundle: $totalProfiles');

  final selections = snapshot.orderedSelections();
  if (selections.isEmpty) {
    print('(empty roster - no selections)');
    print('=' * 70);
    return;
  }

  // Find root selections (no parent)
  final rootSelections = <String>[];
  for (final selId in selections) {
    if (snapshot.parentOf(selId) == null) {
      rootSelections.add(selId);
    }
  }

  print('');
  print('--- SNAPSHOT ---');
  print('Total selections: ${selections.length}');
  print('Root selections: ${rootSelections.length}');
  print('');

  // Print each root and its tree
  var cardNumber = 1;
  for (final rootId in rootSelections) {
    _printUnitCard(
      bundle: bundle,
      snapshot: snapshot,
      selectionId: rootId,
      indent: 0,
      cardNumber: cardNumber++,
    );
    print('');
  }

  print('=' * 70);
}

void main() {
  late _PipelineResult pipelineResult;

  setUpAll(() async {
    // Clean storage before test
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Run the pipeline once for all tests
    pipelineResult = await runPipeline();
  });

  tearDownAll(() async {
    // Clean storage after test
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('M1→M6 Pipeline E2E', () {
    test('pipeline does not throw (smoke test)', () async {
      // This test verifies that the entire M1→M6 pipeline completes
      // without throwing any failures under normal fixture conditions.
      //
      // The pipeline was already run in setUpAll; if we reach here,
      // the pipeline completed successfully.

      expect(pipelineResult.rawBundle, isNotNull);
      expect(pipelineResult.parsedBundle, isNotNull);
      expect(pipelineResult.wrappedBundle, isNotNull);
      expect(pipelineResult.linkedBundle, isNotNull);
      expect(pipelineResult.boundBundle, isNotNull);

      print('[E2E] Pipeline completed without throwing');
    });

    test('M5 produces non-empty structural output', () {
      // Assert at least one of these is non-empty (minimal structural proof)
      final hasEntries = pipelineResult.boundBundle.entries.isNotEmpty;
      final hasProfiles = pipelineResult.boundBundle.profiles.isNotEmpty;
      final hasCategories = pipelineResult.boundBundle.categories.isNotEmpty;

      expect(
        hasEntries || hasProfiles || hasCategories,
        isTrue,
        reason: 'M5 should produce at least one entry, profile, or category',
      );

      print('[E2E] M5 structural proof: '
          'entries=${pipelineResult.boundBundle.entries.length}, '
          'profiles=${pipelineResult.boundBundle.profiles.length}, '
          'categories=${pipelineResult.boundBundle.categories.length}');
    });

    test('M6 determinism: identical report for same input', () {
      final evaluateService = EvaluateService();
      final snapshot =
          DeterministicSnapshot.singleRoot(pipelineResult.boundBundle);

      // Run evaluation twice
      final (report1, _) = evaluateService.evaluateConstraints(
        boundBundle: pipelineResult.boundBundle,
        snapshot: snapshot,
      );

      final (report2, _) = evaluateService.evaluateConstraints(
        boundBundle: pipelineResult.boundBundle,
        snapshot: snapshot,
      );

      // Compare deterministic fields only (not telemetry)
      expect(report1.packId, report2.packId);
      expect(report1.evaluatedAt, report2.evaluatedAt);
      expect(report1.summary, report2.summary);
      expect(
        report1.constraintEvaluations.length,
        report2.constraintEvaluations.length,
      );
      expect(report1.warnings.length, report2.warnings.length);
      expect(report1.notices.length, report2.notices.length);

      // Verify individual evaluations match
      for (var i = 0; i < report1.constraintEvaluations.length; i++) {
        expect(
          report1.constraintEvaluations[i],
          report2.constraintEvaluations[i],
          reason: 'Evaluation at index $i should be identical',
        );
      }

      // Verify warnings match
      for (var i = 0; i < report1.warnings.length; i++) {
        expect(
          report1.warnings[i].code,
          report2.warnings[i].code,
          reason: 'Warning at index $i should have same code',
        );
      }

      print('[E2E] Determinism verified: reports are identical');
    });

    test('M6 empty snapshot returns EMPTY_SNAPSHOT notice', () {
      final evaluateService = EvaluateService();
      final emptySnapshot = DeterministicSnapshot.empty();

      final (report, _) = evaluateService.evaluateConstraints(
        boundBundle: pipelineResult.boundBundle,
        snapshot: emptySnapshot,
      );

      // Should have exactly one EMPTY_SNAPSHOT notice
      expect(report.notices.length, 1);
      expect(report.notices.first.code, EvaluationNotice.codeEmptySnapshot);

      // Should have zero evaluations
      expect(report.constraintEvaluations.isEmpty, isTrue);
      expect(report.summary.totalEvaluations, 0);

      // hasViolations should be false
      expect(report.summary.hasViolations, isFalse);

      print('[E2E] EMPTY_SNAPSHOT notice verified');
    });

    test('pipeline produces human-readable report', () {
      final evaluateService = EvaluateService();
      final snapshot =
          DeterministicSnapshot.singleRoot(pipelineResult.boundBundle);

      final (report, _) = evaluateService.evaluateConstraints(
        boundBundle: pipelineResult.boundBundle,
        snapshot: snapshot,
      );

      // Print the deterministic report
      printPipelineReport(pipelineResult.boundBundle, report);

      // Verify we can produce the report without error
      expect(pipelineResult.boundBundle.packId, isNotEmpty);
      expect(report.packId, pipelineResult.boundBundle.packId);

      print('[E2E] Human-readable report generated successfully');
    });

    test('evaluatedAt derived from boundAt (determinism contract)', () {
      final evaluateService = EvaluateService();
      final snapshot =
          DeterministicSnapshot.singleRoot(pipelineResult.boundBundle);

      final (report, _) = evaluateService.evaluateConstraints(
        boundBundle: pipelineResult.boundBundle,
        snapshot: snapshot,
      );

      // Critical assertion: evaluatedAt must equal boundBundle.boundAt
      expect(
        report.evaluatedAt,
        pipelineResult.boundBundle.boundAt,
        reason: 'evaluatedAt must be derived from boundBundle.boundAt',
      );

      print('[E2E] evaluatedAt determinism verified: '
          '${report.evaluatedAt} == ${pipelineResult.boundBundle.boundAt}');
    });

    test('roster-style output with unit cards and stats', () {
      // Create a roster snapshot with multiple selections
      final snapshot = DeterministicSnapshot.roster(
        pipelineResult.boundBundle,
        maxChildren: 5,
      );

      // Print the roster-style output
      _printRosterSection(
        bundle: pipelineResult.boundBundle,
        snapshot: snapshot,
      );

      // Verify the snapshot structure
      final selections = snapshot.orderedSelections();
      expect(selections.isNotEmpty, isTrue, reason: 'Should have selections');

      // Verify we have at least one root
      final roots = selections.where((s) => snapshot.parentOf(s) == null);
      expect(roots.isNotEmpty, isTrue, reason: 'Should have at least one root');

      // Verify all selections have valid entries
      for (final selId in selections) {
        final entryId = snapshot.entryIdFor(selId);
        final entry = pipelineResult.boundBundle.entryById(entryId);
        expect(entry, isNotNull, reason: 'Entry $entryId should exist');
      }

      // Regression guard: at least one unit card should have typeName="Unit" with M/T/W
      var foundUnitProfile = false;
      for (final selId in selections) {
        final entryId = snapshot.entryIdFor(selId);
        final entry = pipelineResult.boundBundle.entryById(entryId);
        if (entry == null) continue;

        final mainProfile = _findMainStatProfile(entry);
        if (mainProfile == null) continue;

        final typeLower = (mainProfile.typeName ?? '').toLowerCase();
        final charNames = _getCharNames(mainProfile);
        final hasUnitStats = charNames.contains('M') &&
            charNames.contains('T') &&
            charNames.contains('W');

        if (typeLower == 'unit' && hasUnitStats) {
          foundUnitProfile = true;
          print('[E2E] Unit profile found: ${entry.name} -> ${mainProfile.name}');
          print('[E2E]   typeName: ${mainProfile.typeName}');
          print('[E2E]   stats: ${mainProfile.characteristics.map((c) => '${c.name}:${c.value}').join(' | ')}');
          break;
        }
      }

      expect(
        foundUnitProfile,
        isTrue,
        reason: 'At least one selection should have a Unit profile with M/T/W stats',
      );

      print('[E2E] Roster-style output test passed');
    });

    test('roster output determinism: same output for same input', () {
      // Create two identical snapshots
      final snapshot1 = DeterministicSnapshot.roster(
        pipelineResult.boundBundle,
        maxChildren: 3,
      );
      final snapshot2 = DeterministicSnapshot.roster(
        pipelineResult.boundBundle,
        maxChildren: 3,
      );

      // Verify identical structure
      final selections1 = snapshot1.orderedSelections();
      final selections2 = snapshot2.orderedSelections();

      expect(selections1.length, selections2.length);
      for (var i = 0; i < selections1.length; i++) {
        expect(selections1[i], selections2[i]);
        expect(
          snapshot1.entryIdFor(selections1[i]),
          snapshot2.entryIdFor(selections2[i]),
        );
        expect(
          snapshot1.parentOf(selections1[i]),
          snapshot2.parentOf(selections2[i]),
        );
        expect(
          snapshot1.countFor(selections1[i]),
          snapshot2.countFor(selections2[i]),
        );
        expect(
          snapshot1.isForceRoot(selections1[i]),
          snapshot2.isForceRoot(selections2[i]),
        );
      }

      print('[E2E] Roster determinism verified: identical snapshots');
    });
  });
}

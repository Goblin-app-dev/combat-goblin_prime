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
  });
}

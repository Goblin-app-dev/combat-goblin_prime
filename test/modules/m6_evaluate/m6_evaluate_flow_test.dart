import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m6_evaluate/m6_evaluate.dart';

/// Mock implementation of SelectionSnapshot for testing.
class MockSelectionSnapshot implements SelectionSnapshot {
  final List<_MockSelection> _selections;
  final Map<String, _MockSelection> _byId = {};

  MockSelectionSnapshot(this._selections) {
    for (final s in _selections) {
      _byId[s.selectionId] = s;
    }
  }

  @override
  List<String> orderedSelections() => _selections.map((s) => s.selectionId).toList();

  @override
  String entryIdFor(String selectionId) => _byId[selectionId]!.entryId;

  @override
  String? parentOf(String selectionId) => _byId[selectionId]!.parentId;

  @override
  List<String> childrenOf(String selectionId) => _byId[selectionId]!.childIds;

  @override
  int countFor(String selectionId) => _byId[selectionId]!.count;

  @override
  bool isForceRoot(String selectionId) => _byId[selectionId]!.isForceRoot;

  /// Creates a snapshot with selections based on bound entries.
  static MockSelectionSnapshot fromBoundBundle(
    BoundPackBundle bundle, {
    int maxSelections = 10,
  }) {
    final selections = <_MockSelection>[];
    var selectionIndex = 0;

    // Create a force root selection
    if (bundle.entries.isNotEmpty) {
      final forceEntry = bundle.entries.first;
      final forceSelectionId = 'sel-$selectionIndex';
      selectionIndex++;

      final childIds = <String>[];

      // Add some child selections
      for (var i = 1; i < bundle.entries.length && i < maxSelections; i++) {
        final entry = bundle.entries[i];
        final childSelectionId = 'sel-$selectionIndex';
        selectionIndex++;

        selections.add(_MockSelection(
          selectionId: childSelectionId,
          entryId: entry.id,
          parentId: forceSelectionId,
          childIds: const [],
          count: 1,
          isForceRoot: false,
        ));
        childIds.add(childSelectionId);
      }

      // Add the force root
      selections.insert(
        0,
        _MockSelection(
          selectionId: forceSelectionId,
          entryId: forceEntry.id,
          parentId: null,
          childIds: childIds,
          count: 1,
          isForceRoot: true,
        ),
      );
    }

    return MockSelectionSnapshot(selections);
  }
}

class _MockSelection {
  final String selectionId;
  final String entryId;
  final String? parentId;
  final List<String> childIds;
  final int count;
  final bool isForceRoot;

  _MockSelection({
    required this.selectionId,
    required this.entryId,
    required this.parentId,
    required this.childIds,
    required this.count,
    required this.isForceRoot,
  });
}

void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late BoundPackBundle boundBundle;

  setUpAll(() async {
    // Clean storage
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Acquire, parse, wrap, link, bind bundle once for all tests
    final gameSystemBytes =
        await File('test/Warhammer 40,000.gst').readAsBytes();
    final primaryCatalogBytes =
        await File('test/Imperium - Space Marines.cat').readAsBytes();

    final dependencyFiles = <String, String>{
      'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
      '7481-280e-b55e-7867': 'test/Library - Titans.cat',
      '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
      'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
    };

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

    final parsedBundle = await ParseService().parseBundle(rawBundle: rawBundle);
    final wrappedBundle =
        await WrapService().wrapBundle(parsedBundle: parsedBundle);
    final linkedBundle =
        await LinkService().linkBundle(wrappedBundle: wrappedBundle);
    boundBundle = await BindService().bindBundle(linkedBundle: linkedBundle);
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('M6 Evaluate: flow harness (fixtures)', () {
    test('evaluateConstraints: produces EvaluationReport from BoundPackBundle',
        () {
      final evaluateService = EvaluateService();
      final snapshot = MockSelectionSnapshot.fromBoundBundle(boundBundle);

      final (report, telemetry) = evaluateService.evaluateConstraints(
        boundBundle: boundBundle,
        snapshot: snapshot,
      );

      print('[M6 TEST] M6 Evaluate succeeded');
      print('[M6 TEST] Report packId: ${report.packId}');
      print('[M6 TEST] Evaluated at: ${report.evaluatedAt}');

      // packId must match
      expect(report.packId, boundBundle.packId);

      // evaluatedAt must be derived from boundBundle.boundAt
      expect(report.evaluatedAt, boundBundle.boundAt);

      // Report summary
      print('[M6 TEST] Total evaluations: ${report.summary.totalEvaluations}');
      print('[M6 TEST] Satisfied: ${report.summary.satisfiedCount}');
      print('[M6 TEST] Violated: ${report.summary.violatedCount}');
      print('[M6 TEST] Not applicable: ${report.summary.notApplicableCount}');
      print('[M6 TEST] Error: ${report.summary.errorCount}');
      print('[M6 TEST] Has violations: ${report.summary.hasViolations}');

      // Warnings
      print('[M6 TEST] Warnings: ${report.warnings.length}');
      for (final w in report.warnings.take(5)) {
        print('[M6 TEST]   ${w.code}: ${w.message}');
      }
      if (report.warnings.length > 5) {
        print('[M6 TEST]   ... and ${report.warnings.length - 5} more');
      }

      // Notices
      print('[M6 TEST] Notices: ${report.notices.length}');
      for (final n in report.notices) {
        print('[M6 TEST]   ${n.code}: ${n.message}');
      }

      // Telemetry
      if (telemetry != null) {
        print(
            '[M6 TEST] Evaluation duration: ${telemetry.evaluationDuration.inMilliseconds}ms');
      }

      // boundBundle reference preserved
      expect(report.boundBundle, same(boundBundle));

      print('[M6 TEST] All flow validations passed');
    });

    test('evaluateConstraints: empty snapshot returns EMPTY_SNAPSHOT notice',
        () {
      final evaluateService = EvaluateService();
      final emptySnapshot = MockSelectionSnapshot([]);

      final (report, _) = evaluateService.evaluateConstraints(
        boundBundle: boundBundle,
        snapshot: emptySnapshot,
      );

      print('[M6 TEST] Empty snapshot test');

      // Should have EMPTY_SNAPSHOT notice
      expect(report.notices.length, 1);
      expect(report.notices.first.code, EvaluationNotice.codeEmptySnapshot);
      print('[M6 TEST] Got EMPTY_SNAPSHOT notice: ${report.notices.first.message}');

      // Should have zero evaluations
      expect(report.constraintEvaluations.isEmpty, isTrue);
      expect(report.summary.totalEvaluations, 0);
      expect(report.summary.hasViolations, isFalse);

      print('[M6 TEST] Empty snapshot validation passed');
    });

    test('evaluateConstraints: deterministic output for same input', () {
      final evaluateService = EvaluateService();
      final snapshot = MockSelectionSnapshot.fromBoundBundle(boundBundle);

      final (report1, _) = evaluateService.evaluateConstraints(
        boundBundle: boundBundle,
        snapshot: snapshot,
      );

      final (report2, _) = evaluateService.evaluateConstraints(
        boundBundle: boundBundle,
        snapshot: snapshot,
      );

      print('[M6 TEST] Determinism test');

      // Reports must be identical
      expect(report1.packId, report2.packId);
      expect(report1.evaluatedAt, report2.evaluatedAt);
      expect(report1.summary, report2.summary);
      expect(
          report1.constraintEvaluations.length,
          report2.constraintEvaluations.length);
      expect(report1.warnings.length, report2.warnings.length);
      expect(report1.notices.length, report2.notices.length);

      // Check individual evaluations match
      for (var i = 0; i < report1.constraintEvaluations.length; i++) {
        expect(
            report1.constraintEvaluations[i], report2.constraintEvaluations[i]);
      }

      print('[M6 TEST] Determinism validation passed');
    });
  });
}

/// Rule Query Integration Tests — Phase 12 (Layer A)
///
/// Tests the full coordinator pipeline against real indexed catalog data.
/// These tests are diagnostic — they assert route correctness and output
/// format, not exact rule lists (which change across catalog versions).
///
/// Key probes from real data (for reference):
///   Carnifex:          rules=0   (but "carnifex" query → 4 variants → disambig)
///   Hive Tyrant:       rules=8   ("hive tyrant" → 2 variants → disambig)
///   Winged Hive Tyrant: rules=7  (unique name → single result)
///   Gargoyles:         rules=0   (unique canonical key)
///
/// RUNNING:
///   flutter test test/voice/rule_query_integration_test.dart --reporter expanded
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/voice/understanding/voice_assistant_coordinator.dart';
import 'package:combat_goblin_prime/voice/voice_search_facade.dart';

// ---------------------------------------------------------------------------
// Fixture builder
// ---------------------------------------------------------------------------

Future<IndexBundle?> _buildIndex({
  required String primaryPath,
  Map<String, String> dependencyPaths = const {},
}) async {
  if (!File(primaryPath).existsSync()) return null;

  const source = SourceLocator(
    sourceKey: 'rule_query_integration',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  final gsBytes = await File('test/Warhammer 40,000.gst').readAsBytes();
  final primaryBytes = await File(primaryPath).readAsBytes();

  final raw = await AcquireService().buildBundle(
    gameSystemBytes: gsBytes,
    gameSystemExternalFileName: 'Warhammer 40,000.gst',
    primaryCatalogBytes: primaryBytes,
    primaryCatalogExternalFileName: primaryPath.split('/').last,
    requestDependencyBytes: (id) async {
      final path = dependencyPaths[id];
      if (path == null || !File(path).existsSync()) return null;
      return File(path).readAsBytes();
    },
    source: source,
  );

  final parsed = await ParseService().parseBundle(rawBundle: raw);
  final wrapped = await WrapService().wrapBundle(parsedBundle: parsed);
  final linked = await LinkService().linkBundle(wrappedBundle: wrapped);
  final bound = await BindService().bindBundle(linkedBundle: linked);
  return IndexService().buildIndex(bound);
}

VoiceAssistantCoordinator _coord() =>
    VoiceAssistantCoordinator(searchFacade: VoiceSearchFacade());

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ===== Tyranids ==========================================================
  group('Rule query integration — Tyranids', () {
    late IndexBundle? idx;

    setUpAll(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) await dir.delete(recursive: true);

      idx = await _buildIndex(
        primaryPath: 'test/Xenos - Tyranids.cat',
        dependencyPaths: {
          '581a-46b9-5b86-44b7': 'test/Unaligned Forces.cat',
          '374d-45f0-5832-001e': 'test/Library - Tyranids.cat',
        },
      );

      if (idx == null) {
        print('[rule-query] Tyranid fixtures absent — group skipped');
        return;
      }

      // Log key units for diagnostic reference.
      for (final name in ['carnifex', 'hive tyrant', 'gargoyles']) {
        final units = idx!.findUnitsContaining(name);
        print('[rule-query] "$name" → ${units.length} units:');
        for (final u in units) {
          print('  ${u.docId} "${u.name}" rules=${u.ruleDocRefs.length}');
        }
      }
    });

    tearDownAll(() async {
      final dir = Directory('appDataRoot');
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    // A. Rule query routes to rule- path (not generic search fallback).
    test('A — "rules for carnifex" routes to rule- path, not generic search', () async {
      if (idx == null) { markTestSkipped('fixture absent'); return; }

      final plan = await _coord().handleTranscript(
        transcript: 'rules for carnifex',
        slotBundles: {'slot_0': idx!},
        contextHints: const [],
      );
      print('[rule-query] carnifex: ${plan.debugSummary}');

      // Must enter rule path — not generic search (which would be single:/no-results:/disambiguation:)
      expect(plan.debugSummary, startsWith('rule-'));
    });

    // B. "what rules does" pattern also routes correctly.
    test('B — "what rules does hive tyrant have" routes to rule- path', () async {
      if (idx == null) { markTestSkipped('fixture absent'); return; }

      final plan = await _coord().handleTranscript(
        transcript: 'what rules does hive tyrant have',
        slotBundles: {'slot_0': idx!},
        contextHints: const [],
      );
      print('[rule-query] hive tyrant: ${plan.debugSummary}');

      expect(plan.debugSummary, startsWith('rule-'));
    });

    // C. Full disambiguation → selection → rule answer flow.
    //    "hive tyrant" → 2 variants → user selects "hive tyrant" → rule answer.
    test('C — disambiguation + name selection → rule answer (not "Selected X.")', () async {
      if (idx == null) { markTestSkipped('fixture absent'); return; }

      final coord = _coord();
      final bundles = {'slot_0': idx!};

      // Step 1: trigger rule disambiguation.
      final disambig = await coord.handleTranscript(
        transcript: 'rules for hive tyrant',
        slotBundles: bundles,
        contextHints: const [],
      );
      print('[rule-query] step1: ${disambig.debugSummary}');
      expect(disambig.debugSummary, startsWith('rule-'));

      // If it was disambiguation (multiple variants), select one by name.
      if (disambig.debugSummary.startsWith('rule-disambiguation')) {
        final selectionName = disambig.entities.first.displayName;
        final answer = await coord.handleTranscript(
          transcript: selectionName.toLowerCase(),
          slotBundles: bundles,
          contextHints: const [],
        );
        print('[rule-query] step2 ("$selectionName"): ${answer.debugSummary}');
        print('[rule-query] answer: ${answer.primaryText}');

        // Must be a rule answer, NOT "Selected X."
        expect(answer.debugSummary, startsWith('rule-'));
        expect(answer.primaryText, isNot(startsWith('Selected')));
        expect(answer.primaryText, endsWith('.'));
        // Must contain unit name.
        expect(answer.primaryText, contains(selectionName));
      } else {
        // Single result: direct rule answer.
        expect(disambig.primaryText, contains('Hive Tyrant'));
        expect(disambig.primaryText, endsWith('.'));
      }
    });

    // D. Zero-rules case via 2-step: disambig carnifex → select "Carnifex" → no-rules text.
    test('D — Carnifex (rules=0): after disambiguation, selection returns no-rules text', () async {
      if (idx == null) { markTestSkipped('fixture absent'); return; }

      // Verify "Carnifex" exists in index and has 0 rules.
      final carnifexDocs = idx!.findUnitsByName('carnifex');
      if (carnifexDocs.isEmpty) { markTestSkipped('Carnifex not in index'); return; }
      final carnifexDoc = carnifexDocs.first;
      print('[rule-query] Carnifex rules in index: ${carnifexDoc.ruleDocRefs.length}');

      final coord = _coord();
      final bundles = {'slot_0': idx!};

      // Step 1.
      final step1 = await coord.handleTranscript(
        transcript: 'rules for carnifex',
        slotBundles: bundles,
        contextHints: const [],
      );
      expect(step1.debugSummary, startsWith('rule-'));

      late String answer;
      if (step1.debugSummary.startsWith('rule-disambiguation')) {
        // Step 2: select the base "Carnifex" entity.
        final carnifexEntity = step1.entities
            .where((e) => e.displayName.toLowerCase() == 'carnifex')
            .firstOrNull;
        if (carnifexEntity == null) {
          markTestSkipped('No exact "Carnifex" entity in disambiguation list');
          return;
        }
        final step2 = await coord.handleTranscript(
          transcript: 'carnifex',
          slotBundles: bundles,
          contextHints: const [],
        );
        print('[rule-query] Carnifex selection: ${step2.debugSummary}');
        print('[rule-query] Carnifex answer: ${step2.primaryText}');
        answer = step2.primaryText;
      } else {
        answer = step1.primaryText;
      }

      // Carnifex has 0 rules: should return the honest no-rules text.
      if (carnifexDoc.ruleDocRefs.isEmpty) {
        expect(answer, contains("couldn't find any surfaced rules"));
        expect(answer, contains('Carnifex'));
      } else {
        // If the catalog has added rules since probe, just check format.
        expect(answer, contains('Carnifex'));
        expect(answer, endsWith('.'));
      }
    });

    // E. Gargoyles — zero-rules unit, unique canonical key (no disambiguation).
    test('E — Gargoyles (rules=0): unique name → direct rule answer', () async {
      if (idx == null) { markTestSkipped('fixture absent'); return; }

      final gargoylesDocs = idx!.findUnitsByName('gargoyles');
      if (gargoylesDocs.isEmpty) { markTestSkipped('Gargoyles not in index'); return; }

      final plan = await _coord().handleTranscript(
        transcript: 'rules for gargoyles',
        slotBundles: {'slot_0': idx!},
        contextHints: const [],
      );
      print('[rule-query] Gargoyles: ${plan.debugSummary}');
      print('[rule-query] Gargoyles answer: ${plan.primaryText}');

      expect(plan.debugSummary, startsWith('rule-'));

      if (plan.debugSummary == 'rule-answer:0:gargoyles') {
        // Index reports 0 rules → honest text.
        expect(plan.primaryText, contains("couldn't find any surfaced rules"));
      } else if (plan.debugSummary.startsWith('rule-answer:')) {
        // Has rules → correct format.
        expect(plan.primaryText, contains('Gargoyles'));
        expect(plan.primaryText, contains(' has '));
        expect(plan.primaryText, endsWith('.'));
      }
      // Disambiguation also accepted (if multiple gargoyles variants exist).
    });

    // F. No-results case.
    test('F — Unknown unit → rule-no-results, not generic search fallback', () async {
      if (idx == null) { markTestSkipped('fixture absent'); return; }

      final plan = await _coord().handleTranscript(
        transcript: 'rules for xyzzy unit that does not exist',
        slotBundles: {'slot_0': idx!},
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('rule-no-results:'));
      expect(plan.entities, isEmpty);
    });

    // G. "abilities for" pattern routes correctly.
    test('G — "abilities for" pattern routes to rule- path', () async {
      if (idx == null) { markTestSkipped('fixture absent'); return; }

      final plan = await _coord().handleTranscript(
        transcript: 'abilities for hive tyrant',
        slotBundles: {'slot_0': idx!},
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('rule-'));
    });

    // H. Attribute query is not intercepted by rule detection.
    //    With multiple carnifex variants the attr handler triggers disambiguation
    //    (summary = "disambiguation:N"), NOT a rule- prefix. Either way, the
    //    rule detector must not have fired.
    test('H — "what is the toughness of carnifex" not intercepted by rule detector', () async {
      if (idx == null) { markTestSkipped('fixture absent'); return; }

      final plan = await _coord().handleTranscript(
        transcript: 'what is the toughness of carnifex',
        slotBundles: {'slot_0': idx!},
        contextHints: const [],
      );
      print('[rule-query] toughness routing: ${plan.debugSummary}');
      // Rule detector must NOT have fired (would be rule-*).
      expect(plan.debugSummary, isNot(startsWith('rule-')));
      // Must be inside the attribute or search path.
      expect(
        plan.debugSummary,
        anyOf(startsWith('attr-'), startsWith('disambiguation:'), startsWith('single:')),
      );
    });
  });
}

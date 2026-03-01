import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/voice/models/disambiguation_command.dart';
import 'package:combat_goblin_prime/voice/models/spoken_entity.dart';
import 'package:combat_goblin_prime/voice/models/spoken_response_plan.dart';
import 'package:combat_goblin_prime/voice/models/spoken_variant.dart';
import 'package:combat_goblin_prime/voice/models/voice_intent.dart';
import 'package:combat_goblin_prime/voice/models/voice_search_response.dart';
import 'package:combat_goblin_prime/voice/understanding/domain_canonicalizer.dart';
import 'package:combat_goblin_prime/voice/understanding/voice_assistant_coordinator.dart';
import 'package:combat_goblin_prime/voice/understanding/voice_intent_classifier.dart';
import 'package:combat_goblin_prime/voice/voice_search_facade.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Minimal fake IndexBundle map — passed to coordinator; ignored by _FakeSearchFacade.
const _noopBundles = <String, IndexBundle>{};

/// Creates a minimal [SpokenVariant] fixture.
SpokenVariant _variant(String name, String key, String slotId) => SpokenVariant(
      sourceSlotId: slotId,
      docType: SearchDocType.unit,
      docId: '${key}_id',
      canonicalKey: key,
      displayName: name,
      matchReasons: const [MatchReason.canonicalKeyMatch],
      tieBreakKey: '$key\x00${key}_id',
    );

/// Creates a minimal single-variant [SpokenEntity] fixture.
SpokenEntity _entity(String name, String key, String slotId) => SpokenEntity(
      slotId: slotId,
      groupKey: key,
      displayName: name,
      variants: [_variant(name, key, slotId)],
    );

/// A [VoiceSearchFacade] that returns a fixed list of [SpokenEntity]s,
/// ignoring slotBundles so tests do not need real [IndexBundle] instances.
class _FakeSearchFacade extends VoiceSearchFacade {
  final List<SpokenEntity> Function(String query) onSearch;

  _FakeSearchFacade(this.onSearch);

  @override
  VoiceSearchResponse searchText(
    Map<String, IndexBundle> slotBundles,
    String query, {
    int limit = 50,
  }) {
    final entities = onSearch(query);
    return VoiceSearchResponse(
      entities: List.unmodifiable(entities),
      diagnostics: const [],
      spokenSummary: '${entities.length} results',
    );
  }
}

/// Creates a coordinator with a fixed fake search result.
VoiceAssistantCoordinator _coordWith(List<SpokenEntity> entities) {
  return VoiceAssistantCoordinator(
    searchFacade: _FakeSearchFacade((_) => entities),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // VoiceIntentClassifier
  // =========================================================================
  group('1. VoiceIntentClassifier', () {
    const classifier = VoiceIntentClassifier();

    test('1.1 "next" → DisambiguationCommandIntent(next)', () {
      final intent = classifier.classify('next');
      expect(intent, isA<DisambiguationCommandIntent>());
      expect((intent as DisambiguationCommandIntent).command,
          DisambiguationCommand.next);
    });

    test('1.2 "previous" → DisambiguationCommandIntent(previous)', () {
      final intent = classifier.classify('previous');
      expect((intent as DisambiguationCommandIntent).command,
          DisambiguationCommand.previous);
    });

    test('1.3 "select" → DisambiguationCommandIntent(select)', () {
      final intent = classifier.classify('select');
      expect((intent as DisambiguationCommandIntent).command,
          DisambiguationCommand.select);
    });

    test('1.4 "cancel" → DisambiguationCommandIntent(cancel)', () {
      final intent = classifier.classify('cancel');
      expect((intent as DisambiguationCommandIntent).command,
          DisambiguationCommand.cancel);
    });

    test('1.5 Alias "back" → previous', () {
      final intent = classifier.classify('back');
      expect((intent as DisambiguationCommandIntent).command,
          DisambiguationCommand.previous);
    });

    test('1.6 Alias "choose" → select', () {
      final intent = classifier.classify('choose');
      expect((intent as DisambiguationCommandIntent).command,
          DisambiguationCommand.select);
    });

    test('1.7 Alias "stop" → cancel', () {
      final intent = classifier.classify('stop');
      expect((intent as DisambiguationCommandIntent).command,
          DisambiguationCommand.cancel);
    });

    test('1.8 "what are its abilities" → AssistantQuestionIntent', () {
      final intent = classifier.classify('what are its abilities');
      expect(intent, isA<AssistantQuestionIntent>());
    });

    test('1.9 "show me the stats" → AssistantQuestionIntent', () {
      final intent = classifier.classify('show me the stats');
      expect(intent, isA<AssistantQuestionIntent>());
    });

    test('1.10 "abilities" (standalone prefix) → AssistantQuestionIntent', () {
      final intent = classifier.classify('abilities of this unit');
      expect(intent, isA<AssistantQuestionIntent>());
    });

    test('1.11 Arbitrary phrase → SearchIntent', () {
      final intent = classifier.classify('Space Marines');
      expect(intent, isA<SearchIntent>());
      expect((intent as SearchIntent).queryText, 'Space Marines');
    });

    test('1.12 Empty string → UnknownIntent', () {
      final intent = classifier.classify('');
      expect(intent, isA<UnknownIntent>());
    });

    test('1.13 Whitespace-only → UnknownIntent', () {
      final intent = classifier.classify('   ');
      expect(intent, isA<UnknownIntent>());
    });

    test('1.14 Commands are case-insensitive (trimmed lowercase)', () {
      expect(classifier.classify('NEXT'), isA<DisambiguationCommandIntent>());
      expect(classifier.classify('  Cancel  '), isA<DisambiguationCommandIntent>());
    });
  });

  // =========================================================================
  // DomainCanonicalizer
  // =========================================================================
  group('2. DomainCanonicalizer', () {
    const canon = DomainCanonicalizer();

    test('2.1 Exact match in hints returns hint verbatim (preserves casing)', () {
      final result = canon.canonicalizeQuery(
        'Tyranids',
        contextHints: const ['Tyranids', 'Space Marines'],
      );
      expect(result, 'Tyranids');
    });

    test('2.2 No hints → normalized transcript returned', () {
      final result =
          canon.canonicalizeQuery('Space, Marines!', contextHints: const []);
      expect(result, 'space marines');
    });

    test('2.3 No match (score < 0.75) → normalized transcript', () {
      // 'xyz' has no similarity to 'Tyranids' or 'Space Marines'
      final result = canon.canonicalizeQuery(
        'xyz',
        contextHints: const ['Tyranids', 'Space Marines'],
      );
      expect(result, 'xyz');
    });

    test('2.4 Fuzzy match — minor typo in input', () {
      // 'tyranidz' is close enough to 'Tyranids'
      final result = canon.canonicalizeQuery(
        'tyranidz',
        contextHints: const ['Tyranids', 'Space Marines'],
      );
      // Similarity between 'tyranidz' and 'tyranids' is 7/8 = 0.875 ≥ 0.75
      expect(result, 'Tyranids');
    });

    test('2.5 Deterministic — same inputs always produce same output', () {
      const hints = ['Tyranids', 'Space Marines', 'Necrons'];
      const raw = 'space marins';
      final r1 = canon.canonicalizeQuery(raw, contextHints: hints);
      final r2 = canon.canonicalizeQuery(raw, contextHints: hints);
      expect(r1, r2);
    });

    test('2.6 parseCommand delegates correctly', () {
      expect(canon.parseCommand('next'), DisambiguationCommand.next);
      expect(canon.parseCommand('back'), DisambiguationCommand.previous);
      expect(canon.parseCommand('unknown phrase'), isNull);
    });

    test('2.7 Empty raw → empty string returned', () {
      final result = canon.canonicalizeQuery('', contextHints: const ['hint']);
      expect(result, isEmpty);
    });
  });

  // =========================================================================
  // VoiceAssistantCoordinator — core flows
  // =========================================================================
  group('3. VoiceAssistantCoordinator — search flows', () {
    test('3.1 Zero results → no-results plan, no session', () async {
      final coord = _coordWith([]);
      final plan = await coord.handleTranscript(
        transcript: 'unknown unit',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.entities, isEmpty);
      expect(plan.selectedIndex, isNull);
      expect(plan.followUps, isEmpty);
      expect(plan.debugSummary, startsWith('no-results:'));
    });

    test('3.2 Single result → confirms entity, no session', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'intercessor',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.displayName, 'Intercessor');
      expect(plan.selectedIndex, 0);
      expect(plan.followUps, isEmpty);
      expect(plan.primaryText, contains('Intercessor'));
      expect(plan.debugSummary, startsWith('single:'));
    });

    test('3.3 Multiple results → disambiguation plan, selectedIndex=0', () async {
      final e1 = _entity('Intercessor', 'intercessor', 'slot_0');
      final e2 = _entity('Intercessor Squad', 'intercessor_squad', 'slot_0');
      final coord = _coordWith([e1, e2]);
      final plan = await coord.handleTranscript(
        transcript: 'intercessor',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.entities, hasLength(2));
      expect(plan.selectedIndex, 0);
      expect(plan.followUps, containsAll(['next', 'select', 'cancel']));
      expect(plan.debugSummary, 'disambiguation:2');
    });

    test('3.4 Empty transcript → unknown plan', () async {
      final coord = _coordWith([]);
      final plan = await coord.handleTranscript(
        transcript: '',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.entities, isEmpty);
      expect(plan.debugSummary, 'unknown-empty');
    });

    test('3.5 Assistant question with 1 result → confirmation plan', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what are the abilities of this unit',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('assistant-single:'));
      expect(plan.primaryText, contains('Phase 12E'));
    });

    test('3.6 Deterministic: same transcript + same result → same plan', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord1 = _coordWith([entity]);
      final coord2 = _coordWith([entity]);
      final plan1 = await coord1.handleTranscript(
        transcript: 'intercessor',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      final plan2 = await coord2.handleTranscript(
        transcript: 'intercessor',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan1.primaryText, plan2.primaryText);
      expect(plan1.debugSummary, plan2.debugSummary);
      expect(plan1.selectedIndex, plan2.selectedIndex);
    });
  });

  // =========================================================================
  // VoiceAssistantCoordinator — disambiguation session
  // =========================================================================
  group('4. VoiceAssistantCoordinator — disambiguation', () {
    List<SpokenEntity> _twoEntities() => [
          _entity('Intercessor', 'intercessor', 'slot_0'),
          _entity('Intercessor Squad', 'intercessor_squad', 'slot_0'),
        ];

    Future<VoiceAssistantCoordinator> _coordWithSession() async {
      final coord = _coordWith(_twoEntities());
      await coord.handleTranscript(
        transcript: 'intercessor',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      return coord;
    }

    test('4.1 "next" advances selectedIndex', () async {
      final coord = await _coordWithSession();
      final plan = await coord.handleTranscript(
        transcript: 'next',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.selectedIndex, 1);
    });

    test('4.2 "previous" retreats selectedIndex', () async {
      final coord = await _coordWithSession();
      // Advance first
      await coord.handleTranscript(
          transcript: 'next', slotBundles: _noopBundles, contextHints: const []);
      final plan = await coord.handleTranscript(
        transcript: 'previous',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.selectedIndex, 0);
    });

    test('4.3 Clamp at first: "previous" at index 0 stays at 0', () async {
      final coord = await _coordWithSession();
      final plan = await coord.handleTranscript(
        transcript: 'previous',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.selectedIndex, 0);
    });

    test('4.4 Clamp at last: "next" past end stays at last index', () async {
      final coord = await _coordWithSession();
      // Advance twice for 2-entity list (last index is 1)
      await coord.handleTranscript(
          transcript: 'next', slotBundles: _noopBundles, contextHints: const []);
      final plan = await coord.handleTranscript(
        transcript: 'next',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.selectedIndex, 1); // Clamped — still last
    });

    test('4.5 "select" finalizes entity, session cleared', () async {
      final coord = await _coordWithSession();
      // Advance to entity 1
      await coord.handleTranscript(
          transcript: 'next', slotBundles: _noopBundles, contextHints: const []);
      final plan = await coord.handleTranscript(
        transcript: 'select',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.selectedIndex, isNull); // Session cleared
      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.displayName, 'Intercessor Squad');
      expect(plan.primaryText, contains('Intercessor Squad'));
      expect(plan.debugSummary, startsWith('selected:'));
      // Subsequent transcript starts fresh (new search, not command)
      final followUp = await coord.handleTranscript(
        transcript: 'next', // No active session → search for "next"
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // The fake always returns two entities regardless of query
      expect(followUp.debugSummary, startsWith('disambiguation:'));
    });

    test('4.6 "cancel" clears session', () async {
      final coord = await _coordWithSession();
      final plan = await coord.handleTranscript(
        transcript: 'cancel',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.primaryText, 'Cancelled.');
      expect(plan.entities, isEmpty);
      expect(plan.debugSummary, 'cancelled');
    });

    test('4.7 Command with no active session → treated as search', () async {
      final entity = _entity('Next Unit', 'next_unit', 'slot_0');
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((q) => q == 'next' ? [entity] : []),
      );
      final plan = await coord.handleTranscript(
        transcript: 'next',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // No session → treated as search for "next"
      expect(plan.debugSummary, startsWith('single:'));
      expect(plan.entities.first.displayName, 'Next Unit');
    });
  });

  // =========================================================================
  // SpokenResponsePlan invariants
  // =========================================================================
  group('5. SpokenResponsePlan invariants', () {
    test('5.1 debugSummary never contains timestamp-like content', () async {
      final e1 = _entity('A', 'a', 'slot_0');
      final e2 = _entity('B', 'b', 'slot_0');
      final coord = _coordWith([e1, e2]);

      final plans = <SpokenResponsePlan>[];
      // Disambiguation
      plans.add(await coord.handleTranscript(
          transcript: 'test',
          slotBundles: _noopBundles,
          contextHints: const []));
      // Next
      plans.add(await coord.handleTranscript(
          transcript: 'next',
          slotBundles: _noopBundles,
          contextHints: const []));
      // Select
      plans.add(await coord.handleTranscript(
          transcript: 'select',
          slotBundles: _noopBundles,
          contextHints: const []));

      for (final plan in plans) {
        // debugSummary must not contain any colons followed by digits that look
        // like timestamps (HH:MM:SS or epoch milliseconds).
        expect(
          plan.debugSummary,
          isNot(matches(RegExp(r'\d{2}:\d{2}:\d{2}'))),
          reason: 'debugSummary "${plan.debugSummary}" looks like a timestamp',
        );
        expect(
          plan.debugSummary,
          isNot(matches(RegExp(r'\d{13}'))), // 13-digit epoch ms
          reason: 'debugSummary contains epoch ms',
        );
      }
    });

    test('5.2 No cross-slot merging — same key in two slots stays separate', () async {
      // Two entities with the same display name from different slots
      final e0 = _entity('Intercessor', 'intercessor', 'slot_0');
      final e1 = _entity('Intercessor', 'intercessor', 'slot_1');
      final coord = _coordWith([e0, e1]); // Facade returns both
      final plan = await coord.handleTranscript(
        transcript: 'intercessor',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // Both entities are present — coordinator does not merge them
      expect(plan.entities, hasLength(2));
      expect(plan.entities[0].slotId, 'slot_0');
      expect(plan.entities[1].slotId, 'slot_1');
    });
  });
}

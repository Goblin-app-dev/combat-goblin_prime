import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
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
      // followUps now contains the entity display names for voice-native selection.
      expect(plan.followUps, containsAll(['intercessor', 'intercessor squad']));
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

    test('3.5 Assistant question with unrecognized attribute falls back to search plan', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what are the abilities of this unit',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // No recognized attribute → _handleAttributeQuestion falls back to _runSearch.
      // Fake returns 1 entity → single: plan.
      expect(plan.debugSummary, startsWith('single:'));
      expect(plan.primaryText, isNot(contains('Phase 12E')));
      expect(plan.entities, hasLength(1));
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

    test('4.5 Saying entity name in disambiguation selects it', () async {
      final coord = await _coordWithSession();
      final plan = await coord.handleTranscript(
        transcript: 'intercessor squad',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.selectedIndex, isNull); // Session cleared on selection
      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.displayName, 'Intercessor Squad');
      expect(plan.primaryText, contains('Intercessor Squad'));
      expect(plan.debugSummary, startsWith('selected:'));
      // Subsequent transcript starts a fresh search (no active session).
      final followUp = await coord.handleTranscript(
        transcript: 'next',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // Fake always returns two entities → fresh disambiguation.
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
      expect(plan.sessionCleared, isTrue);
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

  // =========================================================================
  // Pure attribute helpers
  // =========================================================================
  group('6. Pure attribute helpers — extractAttributeValues + formatAttributeAnswer', () {
    const nodeRef = NodeRef(0);

    WeaponDoc makeWeapon(
      String name,
      String docId,
      List<IndexedCharacteristic> chars,
    ) =>
        WeaponDoc(
          docId: docId,
          canonicalKey: name.toLowerCase(),
          profileId: docId,
          name: name,
          characteristics: chars,
          keywordTokens: const [],
          ruleDocRefs: const [],
          sourceFileId: 'test',
          sourceNode: nodeRef,
        );

    IndexedCharacteristic char(String name, String value) =>
        IndexedCharacteristic(name: name, typeId: name.toLowerCase(), valueText: value);

    test('6.1 extractAttributeValues: returns only BS lines', () {
      final weapons = [
        makeWeapon('Bolt Rifle', 'weapon:br', [
          char('BS', '3+'),
          char('Range', '24"'),
          char('S', '4'),
        ]),
      ];
      final lines = extractAttributeValues('BS', weapons);
      expect(lines, [('Bolt Rifle', '3+')]);
    });

    test('6.2 extractAttributeValues: stable-ordered across two weapons (pre-sorted input)', () {
      // Caller is responsible for sorting; we pass pre-sorted (Bolt Pistol < Bolt Rifle).
      final weapons = [
        makeWeapon('Bolt Pistol', 'weapon:bp', [char('BS', '3+')]),
        makeWeapon('Bolt Rifle', 'weapon:br', [char('BS', '3+')]),
      ];
      final lines = extractAttributeValues('BS', weapons);
      expect(lines, [('Bolt Pistol', '3+'), ('Bolt Rifle', '3+')]);
    });

    test('6.3 extractAttributeValues: skips weapons without the attribute', () {
      final weapons = [
        makeWeapon('Bolt Rifle', 'weapon:br', [char('BS', '3+')]),
        makeWeapon('Power Sword', 'weapon:ps', [char('WS', '3+'), char('S', '5')]),
      ];
      final lines = extractAttributeValues('BS', weapons);
      expect(lines, hasLength(1));
      expect(lines.first.$1, 'Bolt Rifle');
    });

    test('6.4 extractAttributeValues: empty list when no weapon has the attribute', () {
      final weapons = [
        makeWeapon('Power Sword', 'weapon:ps', [char('WS', '3+')]),
        makeWeapon('Chainsword', 'weapon:cs', [char('WS', '4+')]),
      ];
      expect(extractAttributeValues('BS', weapons), isEmpty);
    });

    test('6.5 formatAttributeAnswer: correct format string', () {
      final text = formatAttributeAnswer(
        'Intercessors',
        'BS',
        [('Bolt Pistol', '3+'), ('Bolt Rifle', '3+')],
      );
      expect(text, 'Intercessors BS — Bolt Pistol: 3+, Bolt Rifle: 3+');
    });

    test('6.6 formatAttributeAnswer: single weapon', () {
      final text = formatAttributeAnswer('Scout', 'BS', [('Sniper Rifle', '3+')]);
      expect(text, 'Scout BS — Sniper Rifle: 3+');
    });

    test('6.7 Deterministic: same inputs → same output', () {
      final lines = [('Bolt Rifle', '3+'), ('Bolt Pistol', '3+')];
      expect(
        formatAttributeAnswer('Unit A', 'BS', lines),
        formatAttributeAnswer('Unit A', 'BS', lines),
      );
    });
  });

  // =========================================================================
  // Coordinator — attribute question routing
  // =========================================================================
  group('7. Coordinator — attribute question routing', () {
    test('7.1 BS question with 1 result → non-placeholder plan (no "Phase 12E")', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the BS of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.primaryText, isNot(contains('Phase 12E')));
      // slotBundles is empty → bundle lookup fails gracefully
      expect(plan.debugSummary, startsWith('attr-'));
      expect(plan.entities, hasLength(1));
    });

    test('7.2 BS question, no results → no-results plan', () async {
      final coord = _coordWith([]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the BS of Unknown Unit',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.entities, isEmpty);
      expect(plan.debugSummary, startsWith('no-results:'));
    });

    test('7.3 BS question, multiple results → disambiguation plan', () async {
      final e1 = _entity('Intercessor', 'intercessor', 'slot_0');
      final e2 = _entity('Intercessor Squad', 'intercessor_squad', 'slot_0');
      final coord = _coordWith([e1, e2]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the BS of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('disambiguation:'));
      // followUps now carries entity names for voice-native selection.
      expect(plan.followUps, containsAll(['intercessor', 'intercessor squad']));
    });

    test('7.4 Unrecognized attribute → falls back to plain search plan', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what are the abilities of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // No attribute recognized → _runSearch → single: plan.
      expect(plan.debugSummary, startsWith('single:'));
      expect(plan.entities, hasLength(1));
    });

    test('7.5 "ballistic skill" synonym recognized same as "bs"', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the ballistic skill of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // Recognized synonym → routes through _handleAttributeQuestion → attr- prefix
      expect(plan.debugSummary, startsWith('attr-'));
      expect(plan.primaryText, isNot(contains('Phase 12E')));
    });

    test('7.6 "ballistic" synonym recognized', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'show me the ballistic of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('7.7 Deterministic: same transcript + same fake → same plan', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord1 = _coordWith([entity]);
      final coord2 = _coordWith([entity]);
      final plan1 = await coord1.handleTranscript(
        transcript: 'what is the BS of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      final plan2 = await coord2.handleTranscript(
        transcript: 'what is the BS of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan1.primaryText, plan2.primaryText);
      expect(plan1.debugSummary, plan2.debugSummary);
    });
  });

  // =========================================================================
  // Unit stat synonym routing
  // =========================================================================
  group('8. Unit stat synonym routing', () {
    Future<SpokenResponsePlan> attrPlan(String transcript) async {
      final entity = _entity('Carnifex', 'carnifex', 'slot_0');
      final coord = _coordWith([entity]);
      return coord.handleTranscript(
        transcript: transcript,
        slotBundles: _noopBundles,
        contextHints: const [],
      );
    }

    test('8.1 "toughness" synonym routes through attr handler', () async {
      final plan = await attrPlan('what is the toughness of Carnifex');
      expect(plan.debugSummary, startsWith('attr-'));
      expect(plan.primaryText, isNot(contains('Phase 12E')));
    });

    test('8.2 "movement" synonym routes through attr handler', () async {
      final plan = await attrPlan('what is the movement of Carnifex');
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('8.3 "wounds" synonym routes through attr handler', () async {
      final plan = await attrPlan('what are the wounds of Carnifex');
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('8.4 "save" synonym routes through attr handler', () async {
      final plan = await attrPlan('what is the save of Carnifex');
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('8.5 "leadership" synonym routes through attr handler', () async {
      final plan = await attrPlan('what is the leadership of Carnifex');
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('8.6 "objective control" synonym routes through attr handler', () async {
      final plan = await attrPlan('what is the objective control of Carnifex');
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('8.7 "weapon skill" synonym routes through attr handler', () async {
      final plan = await attrPlan('what is the weapon skill of Carnifex');
      expect(plan.debugSummary, startsWith('attr-'));
    });
  });

  // =========================================================================
  // Disambiguation prompt includes entity names
  // =========================================================================
  group('9. Disambiguation prompt includes entity names', () {
    test('9.1 Two matches: prompt contains both names', () async {
      final e1 = _entity('Alpha Squad', 'alpha_squad', 'slot_0');
      final e2 = _entity('Alpha Guard', 'alpha_guard', 'slot_0');
      final coord = _coordWith([e1, e2]);
      final plan = await coord.handleTranscript(
        transcript: 'alpha',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, 'disambiguation:2');
      expect(plan.primaryText, contains('Alpha Squad'));
      expect(plan.primaryText, contains('Alpha Guard'));
    });

    test('9.2 Three matches: prompt contains all three names', () async {
      final e1 = _entity('Alpha Squad', 'alpha_squad', 'slot_0');
      final e2 = _entity('Alpha Guard', 'alpha_guard', 'slot_0');
      final e3 = _entity('Alpha Warrior', 'alpha_warrior', 'slot_0');
      final coord = _coordWith([e1, e2, e3]);
      final plan = await coord.handleTranscript(
        transcript: 'alpha',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, 'disambiguation:3');
      expect(plan.primaryText, contains('Alpha Squad'));
      expect(plan.primaryText, contains('Alpha Guard'));
      expect(plan.primaryText, contains('Alpha Warrior'));
    });

    test('9.3 Four matches: first three names shown, fourth omitted', () async {
      final e1 = _entity('Alpha Squad', 'alpha_squad', 'slot_0');
      final e2 = _entity('Alpha Guard', 'alpha_guard', 'slot_0');
      final e3 = _entity('Alpha Warrior', 'alpha_warrior', 'slot_0');
      final e4 = _entity('Alpha Ancient', 'alpha_ancient', 'slot_0');
      final coord = _coordWith([e1, e2, e3, e4]);
      final plan = await coord.handleTranscript(
        transcript: 'alpha',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, 'disambiguation:4');
      expect(plan.primaryText, contains('Alpha Squad'));
      expect(plan.primaryText, contains('Alpha Guard'));
      expect(plan.primaryText, contains('Alpha Warrior'));
      expect(plan.primaryText, isNot(contains('Alpha Ancient')));
      expect(plan.primaryText, contains('4'));
    });

    test('9.4 Prompt ends with "Which one?" — no navigation instructions', () async {
      final e1 = _entity('Alpha Squad', 'alpha_squad', 'slot_0');
      final e2 = _entity('Beta Guard', 'beta_guard', 'slot_0');
      final coord = _coordWith([e1, e2]);
      final plan = await coord.handleTranscript(
        transcript: 'test',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.primaryText, contains('Which one?'));
      expect(plan.primaryText, isNot(contains('"next"')));
      expect(plan.primaryText, isNot(contains('"select"')));
    });
  });

  // =========================================================================
  // sessionCleared field behavior
  // =========================================================================
  group('10. sessionCleared field behavior', () {
    test('10.1 Cancel plan has sessionCleared = true', () async {
      final e1 = _entity('A', 'a', 'slot_0');
      final e2 = _entity('B', 'b', 'slot_0');
      final coord = _coordWith([e1, e2]);
      await coord.handleTranscript(
        transcript: 'test',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      final plan = await coord.handleTranscript(
        transcript: 'cancel',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.sessionCleared, isTrue);
    });

    test('10.2 No-results plan has sessionCleared = false', () async {
      final coord = _coordWith([]);
      final plan = await coord.handleTranscript(
        transcript: 'some unknown unit',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.entities, isEmpty);
      expect(plan.sessionCleared, isFalse);
    });

    test('10.3 Disambiguation plan has sessionCleared = false', () async {
      final e1 = _entity('A', 'a', 'slot_0');
      final e2 = _entity('B', 'b', 'slot_0');
      final coord = _coordWith([e1, e2]);
      final plan = await coord.handleTranscript(
        transcript: 'test',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('disambiguation:'));
      expect(plan.sessionCleared, isFalse);
    });

    test('10.4 Unknown/empty transcript has sessionCleared = true', () async {
      final coord = _coordWith([]);
      final plan = await coord.handleTranscript(
        transcript: '',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, 'unknown-empty');
      expect(plan.sessionCleared, isTrue);
    });

    test('10.5 Single-result plan has sessionCleared = false', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'intercessor',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('single:'));
      expect(plan.sessionCleared, isFalse);
    });
  });

  // =========================================================================
  // Name-match disambiguation (voice-native selection)
  // =========================================================================
  group('11. Name-match disambiguation', () {
    // Three-entity disambiguation for "captain" — used by several tests below.
    Future<VoiceAssistantCoordinator> captainSession() async {
      final entities = [
        _entity('Captain', 'captain', 'slot_0'),
        _entity('Captain with Jump Pack', 'captain_jump', 'slot_0'),
        _entity('Captain in Terminator Armour', 'captain_term', 'slot_0'),
      ];
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => entities),
      );
      await coord.handleTranscript(
        transcript: 'captain',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      return coord;
    }

    // A. Direct selection by exact name.
    test('11.1 A — exact name match selects the correct entity', () async {
      final coord = await captainSession();
      final plan = await coord.handleTranscript(
        transcript: 'captain with jump pack',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('selected:'));
      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.displayName, 'Captain with Jump Pack');
      expect(plan.selectedIndex, isNull);
    });

    // B. Case-insensitive match.
    test('11.2 B — match ignores uppercase', () async {
      final coord = await captainSession();
      final plan = await coord.handleTranscript(
        transcript: 'CAPTAIN WITH JUMP PACK',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('selected:'));
      expect(plan.entities.first.displayName, 'Captain with Jump Pack');
    });

    test('11.3 B — match ignores mixed case', () async {
      final coord = await captainSession();
      final plan = await coord.handleTranscript(
        transcript: 'Captain With Jump Pack',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('selected:'));
      expect(plan.entities.first.displayName, 'Captain with Jump Pack');
    });

    // C. Containment match: leading filler stripped before exact compare.
    test('11.4 C — "the X" strips filler and matches X', () async {
      final coord = await captainSession();
      final plan = await coord.handleTranscript(
        transcript: 'the captain',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('selected:'));
      expect(plan.entities.first.displayName, 'Captain');
    });

    // D. Unrecognized input: session clears, transcript treated as new search.
    test('11.5 D — unrecognized input clears session and falls through to search', () async {
      final coord = await captainSession();
      final plan = await coord.handleTranscript(
        transcript: 'something else entirely',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // Fake returns 3 entities for any query → fresh disambiguation.
      expect(plan.debugSummary, startsWith('disambiguation:'));
      // Session is fresh (not the same object as before).
      expect(plan.sessionCleared, isFalse);
    });

    // E. Cancel still returns to idle.
    test('11.6 E — "cancel" during name-match disambiguation returns to idle', () async {
      final coord = await captainSession();
      final plan = await coord.handleTranscript(
        transcript: 'cancel',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.primaryText, 'Cancelled.');
      expect(plan.entities, isEmpty);
      expect(plan.sessionCleared, isTrue);
    });
  });

  // =========================================================================
  // Rule-list query path (Layer A)
  // =========================================================================
  group('12. Rule-list query path', () {
    // Helper: coord that returns one entity for any query.
    VoiceAssistantCoordinator _ruleCoord(List<SpokenEntity> entities) =>
        VoiceAssistantCoordinator(
          searchFacade: _FakeSearchFacade((_) => entities),
        );

    // -------------------------------------------------------------------------
    // A. Direct rule query — all 6 bounded patterns route to rule- path.
    // With _noopBundles the bundle lookup fails → rule-no-bundle: debug prefix,
    // which proves the coordinator entered _buildRuleListAnswer (rule path).
    // -------------------------------------------------------------------------

    Future<SpokenResponsePlan> _ruleQuery(String transcript) async {
      final entity = _entity('Carnifex', 'carnifex', 'slot_0');
      return _ruleCoord([entity]).handleTranscript(
        transcript: transcript,
        slotBundles: _noopBundles,
        contextHints: const [],
      );
    }

    test('12.1 "what rules does carnifex have" → rule path', () async {
      final plan = await _ruleQuery('what rules does carnifex have');
      expect(plan.debugSummary, startsWith('rule-'));
      expect(plan.entities, hasLength(1));
    });

    test('12.2 "rules for carnifex" → rule path', () async {
      final plan = await _ruleQuery('rules for carnifex');
      expect(plan.debugSummary, startsWith('rule-'));
    });

    test('12.3 "rules of carnifex" → rule path', () async {
      final plan = await _ruleQuery('rules of carnifex');
      expect(plan.debugSummary, startsWith('rule-'));
    });

    test('12.4 "abilities for carnifex" → rule path', () async {
      final plan = await _ruleQuery('abilities for carnifex');
      expect(plan.debugSummary, startsWith('rule-'));
    });

    test('12.5 "abilities of carnifex" → rule path', () async {
      final plan = await _ruleQuery('abilities of carnifex');
      expect(plan.debugSummary, startsWith('rule-'));
    });

    test('12.6 "what abilities does carnifex have" → rule path', () async {
      final plan = await _ruleQuery('what abilities does carnifex have');
      expect(plan.debugSummary, startsWith('rule-'));
    });

    // -------------------------------------------------------------------------
    // B. Ambiguous rule query: disambiguation triggered, then name selection
    //    routes back to the rule path (not "Selected X.").
    // -------------------------------------------------------------------------

    test('12.7 "rules for captain" with multiple matches → rule-disambiguation', () async {
      final entities = [
        _entity('Captain', 'captain', 'slot_0'),
        _entity('Captain with Jump Pack', 'captain_jump', 'slot_0'),
      ];
      final coord = _ruleCoord(entities);
      final plan = await coord.handleTranscript(
        transcript: 'rules for captain',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, 'rule-disambiguation:2');
      expect(plan.primaryText, contains('Which one?'));
    });

    test('12.8 After rule disambiguation, name selection → rule answer path', () async {
      final entities = [
        _entity('Captain', 'captain', 'slot_0'),
        _entity('Captain with Jump Pack', 'captain_jump', 'slot_0'),
      ];
      final coord = _ruleCoord(entities);
      // Trigger disambiguation.
      await coord.handleTranscript(
        transcript: 'rules for captain',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // Select by name — should route to rule path, not "Selected X."
      final plan = await coord.handleTranscript(
        transcript: 'captain with jump pack',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // rule-no-bundle: proves _buildRuleListAnswer was reached (rule path).
      expect(plan.debugSummary, startsWith('rule-'));
      expect(plan.debugSummary, isNot(startsWith('selected:')));
      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.displayName, 'Captain with Jump Pack');
    });

    // -------------------------------------------------------------------------
    // C. No results for a rule query.
    // -------------------------------------------------------------------------

    test('12.9 Rule query with no entity match → rule-no-results', () async {
      final coord = _ruleCoord([]);
      final plan = await coord.handleTranscript(
        transcript: 'rules for unknown xyzzy unit',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('rule-no-results:'));
      expect(plan.entities, isEmpty);
    });

    // -------------------------------------------------------------------------
    // D. formatRuleListAnswer pure-function tests (Layer A formatting).
    // -------------------------------------------------------------------------

    test('12.10 formatRuleListAnswer — zero rules → honest no-rules text', () {
      final text = formatRuleListAnswer('Carnifex', const []);
      expect(text, contains("couldn't find any surfaced rules"));
      expect(text, contains('Carnifex'));
    });

    test('12.11 formatRuleListAnswer — one rule', () {
      const nodeRef = NodeRef(0);
      final rule = RuleDoc(
        docId: 'rule:synapse',
        canonicalKey: 'synapse',
        ruleId: 'synapse',
        name: 'Synapse',
        description: '',
        sourceFileId: 'test',
        sourceNode: nodeRef,
      );
      expect(formatRuleListAnswer('Carnifex', [rule]), 'Carnifex has Synapse.');
    });

    test('12.12 formatRuleListAnswer — two rules', () {
      const nodeRef = NodeRef(0);
      RuleDoc r(String name) => RuleDoc(
            docId: 'rule:${name.toLowerCase()}',
            canonicalKey: name.toLowerCase(),
            ruleId: name.toLowerCase(),
            name: name,
            description: '',
            sourceFileId: 'test',
            sourceNode: nodeRef,
          );
      final text = formatRuleListAnswer('Carnifex', [r('Synapse'), r('Deadly Demise')]);
      expect(text, 'Carnifex has Synapse and Deadly Demise.');
    });

    test('12.13 formatRuleListAnswer — three rules (Oxford comma)', () {
      const nodeRef = NodeRef(0);
      RuleDoc r(String name) => RuleDoc(
            docId: 'rule:${name.toLowerCase().replaceAll(' ', '_')}',
            canonicalKey: name.toLowerCase(),
            ruleId: name.toLowerCase(),
            name: name,
            description: '',
            sourceFileId: 'test',
            sourceNode: nodeRef,
          );
      final text = formatRuleListAnswer(
          'Hive Tyrant', [r('Synapse'), r('Shadow in the Warp'), r('Deadly Demise')]);
      expect(text, 'Hive Tyrant has Synapse, Shadow in the Warp, and Deadly Demise.');
    });

    // -------------------------------------------------------------------------
    // E. No regression — existing paths unaffected.
    // -------------------------------------------------------------------------

    test('12.14 No regression: attr query still routes to attr- path', () async {
      final entity = _entity('Carnifex', 'carnifex', 'slot_0');
      final coord = _ruleCoord([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the toughness of carnifex',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('12.15 No regression: "what are the abilities of X" not a rule query → search path', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _ruleCoord([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what are the abilities of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // No rule pattern matched → falls through attribute handler → unrecognized attr → search.
      expect(plan.debugSummary, startsWith('single:'));
    });

    test('12.16 No regression: cancel during rule disambiguation → Cancelled', () async {
      final entities = [
        _entity('Captain', 'captain', 'slot_0'),
        _entity('Captain with Jump Pack', 'captain_jump', 'slot_0'),
      ];
      final coord = _ruleCoord(entities);
      await coord.handleTranscript(
        transcript: 'rules for captain',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      final plan = await coord.handleTranscript(
        transcript: 'cancel',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.primaryText, 'Cancelled.');
      expect(plan.sessionCleared, isTrue);
    });
  });
}

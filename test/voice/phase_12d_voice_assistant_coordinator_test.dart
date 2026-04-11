import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
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
// Minimal IndexBundle builder for coordinator integration tests
// ---------------------------------------------------------------------------
//
// Mirrors the hermetic approach from weapon_collection_scope_test.dart:
// build a minimal BoundPackBundle in-memory, run IndexService, get a real
// IndexBundle whose unitByDocId and weaponByDocId lookups work correctly.
//
// File-ID constants are local to this scope.

const _iTestGstFileId = 'coord-gst-0001';
const _iTestCatFileId = 'coord-cat-0001';

WrappedFile _iWrappedFile(String fileId, SourceFileType type) {
  return WrappedFile(
    fileId: fileId,
    fileType: type,
    nodes: [
      WrappedNode(
        ref: const NodeRef(0),
        tagName: 'catalogue',
        attributes: const {},
        parent: null,
        children: const [],
        depth: 0,
        fileId: fileId,
        fileType: type,
      ),
    ],
    idIndex: const {},
  );
}

WrappedPackBundle _iWrappedBundle() {
  return WrappedPackBundle(
    packId: 'coord-test-pack',
    wrappedAt: DateTime(2026, 1, 1),
    gameSystem: _iWrappedFile(_iTestGstFileId, SourceFileType.gst),
    primaryCatalog: _iWrappedFile(_iTestCatFileId, SourceFileType.cat),
    dependencyCatalogs: const [],
  );
}

LinkedPackBundle _iLinkedBundle(WrappedPackBundle wrapped) {
  return LinkedPackBundle(
    packId: wrapped.packId,
    linkedAt: DateTime(2026, 1, 1),
    symbolTable: SymbolTable.fromWrappedBundle(wrapped),
    resolvedRefs: const [],
    diagnostics: const [],
    wrappedBundle: wrapped,
  );
}

/// Builds a minimal BoundProfile for a unit datasheet (typeName == 'unit').
BoundProfile _iUnitProfile(String id) {
  return BoundProfile(
    id: id,
    name: 'Unit Profile',
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
    sourceFileId: _iTestCatFileId,
    sourceNode: const NodeRef(0),
  );
}

/// Builds a minimal ranged-weapon BoundProfile whose characteristics include BS.
BoundProfile _iRangedWeaponProfile(String id, String name, String bsValue) {
  return BoundProfile(
    id: id,
    name: name,
    typeId: 'type-wpn',
    typeName: 'Ranged Weapons',
    characteristics: [
      (name: 'Range', value: '24"'),
      (name: 'BS', value: bsValue),
      (name: 'S', value: '4'),
      (name: 'AP', value: '0'),
      (name: 'D', value: '1'),
    ],
    sourceFileId: _iTestCatFileId,
    sourceNode: const NodeRef(0),
  );
}

BoundEntry _iEntry({
  required String id,
  required String name,
  required List<BoundProfile> profiles,
}) {
  return BoundEntry(
    id: id,
    name: name,
    isGroup: false,
    isHidden: false,
    children: const [],
    profiles: profiles,
    categories: const [],
    costs: const [],
    constraints: const [],
    sourceFileId: _iTestCatFileId,
    sourceNode: const NodeRef(0),
  );
}

/// Builds a real IndexBundle containing one unit and one ranged weapon with BS.
///
/// UnitDoc.docId   = 'unit:{unitEntryId}'
/// WeaponDoc.docId = 'weapon:{weaponProfileId}'
IndexBundle _buildCoordTestBundle({
  required String unitEntryId,
  required String unitName,
  required String weaponProfileId,
  required String weaponName,
  required String bsValue,
}) {
  final unitProf = _iUnitProfile('unit-prof-$unitEntryId');
  final wpnProf = _iRangedWeaponProfile(weaponProfileId, weaponName, bsValue);

  final entry = _iEntry(
    id: unitEntryId,
    name: unitName,
    profiles: [unitProf, wpnProf],
  );

  final wrapped = _iWrappedBundle();
  final linked = _iLinkedBundle(wrapped);
  final bound = BoundPackBundle(
    packId: 'coord-test-pack',
    boundAt: DateTime(2026, 1, 1),
    entries: [entry],
    profiles: [unitProf, wpnProf],
    categories: const [],
    diagnostics: const [],
    linkedBundle: linked,
  );

  return IndexService().buildIndex(bound);
}

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
      // Both groupKeys are general-substring matches for "intercessor"
      // (score 1 each), so neither is auto-selected and disambiguation fires.
      final e1 = _entity('Assault Intercessors', 'assault intercessors', 'slot_0');
      final e2 = _entity('Heavy Intercessors', 'heavy intercessors', 'slot_0');
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
    // Both groupKeys are general-substring matches for the transcript
    // "intercessor" (score 1 each) so neither is auto-selected by the
    // canonical-quality filter.  This keeps both entities in play for
    // disambiguation-flow testing.
    List<SpokenEntity> _twoEntities() => [
          _entity('Assault Intercessors', 'assault intercessors', 'slot_0'),
          _entity('Heavy Intercessors', 'heavy intercessors', 'slot_0'),
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
      expect(plan.entities.first.displayName, 'Heavy Intercessors');
      expect(plan.primaryText, contains('Heavy Intercessors'));
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
      // Both groupKeys score 1 (general substring) for the resolved entity
      // query so neither is auto-selected and disambiguation is triggered.
      final e1 = _entity('Assault Intercessors', 'assault intercessors', 'slot_0');
      final e2 = _entity('Heavy Intercessors', 'heavy intercessors', 'slot_0');
      final coord = _coordWith([e1, e2]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the BS of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('disambiguation:'));
      expect(plan.followUps, containsAll(['next', 'select', 'cancel']));
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
  // Coordinator — integration with real IndexBundle
  //
  // These tests replace _noopBundles with a real IndexBundle so that
  // _handleAttributeQuestion() actually exercises the full data path:
  //   SpokenEntity.variant.sourceSlotId → slotBundles[slotId]
  //   → IndexBundle.unitByDocId(variant.docId)
  //   → UnitDoc.weaponDocRefs
  //   → IndexBundle.weaponByDocId(ref)
  //   → WeaponDoc.characteristics['BS']
  //
  // This exposes whether the coordinator correctly reads weapon-backed
  // attribute data and whether any clarification behavior is still missing.
  // =========================================================================
  group('8. Coordinator — integration with real IndexBundle', () {
    // Synthetic IDs — chosen so docId format is predictable:
    //   UnitDoc.docId   = 'unit:intercessor-001'
    //   WeaponDoc.docId = 'weapon:bolt-rifle-001'
    const unitEntryId = 'intercessor-001';
    const weaponProfileId = 'bolt-rifle-001';
    const weaponName = 'Bolt Rifle';
    const bsValue = '3+';

    late IndexBundle testBundle;

    setUp(() {
      testBundle = _buildCoordTestBundle(
        unitEntryId: unitEntryId,
        unitName: 'Intercessor',
        weaponProfileId: weaponProfileId,
        weaponName: weaponName,
        bsValue: bsValue,
      );
    });

    // Helper: build a coordinator whose fake returns a SpokenEntity whose
    // variant docId and sourceSlotId match the real IndexBundle.
    VoiceAssistantCoordinator _coordWithBundle(IndexBundle bundle) {
      final entity = SpokenEntity(
        slotId: 'slot_0',
        groupKey: 'intercessor',
        displayName: 'Intercessor',
        variants: [
          SpokenVariant(
            sourceSlotId: 'slot_0',
            docType: SearchDocType.unit,
            docId: 'unit:$unitEntryId',
            canonicalKey: 'intercessor',
            displayName: 'Intercessor',
            matchReasons: const [MatchReason.canonicalKeyMatch],
            tieBreakKey: 'intercessor\x00unit:$unitEntryId',
          ),
        ],
      );
      return VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [entity]),
      );
    }

    test('8.1 BS question with real IndexBundle → attr-answer plan with weapon data', () async {
      // This test proves the coordinator consumes real weapon-backed attribute
      // data via the weaponDocRefs → weaponByDocId path.
      final coord = _coordWithBundle(testBundle);
      final plan = await coord.handleTranscript(
        transcript: 'what is the BS of Intercessors',
        slotBundles: {'slot_0': testBundle},
        contextHints: const [],
      );

      // Must resolve to an attr-answer plan — not attr-no-bundle, attr-no-unit-doc,
      // or attr-empty. Any of those would indicate a data-path failure.
      expect(
        plan.debugSummary,
        startsWith('attr-answer:bs:'),
        reason: 'Coordinator must reach the attr-answer branch via '
            'weaponDocRefs → weaponByDocId → characteristics[BS]. '
            'Got: "${plan.debugSummary}"',
      );
      expect(plan.entities, hasLength(1));
      // Phase 12E-2: natural-language format — no raw codes, value is spoken.
      // Single weapon → "Bolt Rifle ballistic skill is 3 plus."
      expect(plan.primaryText, contains('ballistic skill'));
      expect(plan.primaryText, contains(weaponName));
      expect(plan.primaryText, contains('3 plus')); // "3+" → "3 plus"
    });

    test('8.2 Real bundle — no clarification needed for single unambiguous result', () async {
      // Confirms the coordinator does NOT enter a disambiguation loop when
      // the search returns exactly one result backed by real weapon data.
      // If the coordinator silently needed clarification but did not ask,
      // the plan would stall in a disambiguation: branch — this test exposes that.
      final coord = _coordWithBundle(testBundle);
      final plan = await coord.handleTranscript(
        transcript: 'what is the BS of Intercessors',
        slotBundles: {'slot_0': testBundle},
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        isNot(startsWith('disambiguation:')),
        reason: 'Single-result attr question must not open a disambiguation session',
      );
      expect(plan.followUps, isEmpty,
          reason: 'No follow-up prompts expected for a resolved attribute answer');
    });

    test('8.3 Deterministic: two identical coordinator instances produce identical plans', () async {
      final coord1 = _coordWithBundle(testBundle);
      final coord2 = _coordWithBundle(testBundle);
      final plan1 = await coord1.handleTranscript(
        transcript: 'what is the BS of Intercessors',
        slotBundles: {'slot_0': testBundle},
        contextHints: const [],
      );
      final plan2 = await coord2.handleTranscript(
        transcript: 'what is the BS of Intercessors',
        slotBundles: {'slot_0': testBundle},
        contextHints: const [],
      );
      expect(plan1.primaryText, plan2.primaryText);
      expect(plan1.debugSummary, plan2.debugSummary);
    });
  });

  // =========================================================================
  // Phase 12E-1 — attribute synonym expansion + movement query routing
  // =========================================================================
  group('9. Phase 12E-1 — synonym expansion + movement routing', () {
    // ── Movement query classification ──────────────────────────────────────

    test('9.1 "movement of X" → AssistantQuestionIntent, routes attr-', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'movement of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      // Would be "single:" (SearchIntent path) if "movement " prefix were absent.
      expect(plan.debugSummary, startsWith('attr-'),
          reason: '"movement of X" must be classified as AssistantQuestionIntent '
              'and routed through _handleAttributeQuestion');
    });

    test('9.2 "move of X" → AssistantQuestionIntent, routes attr-', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'move of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('attr-'),
          reason: '"move of X" must route through _handleAttributeQuestion');
    });

    test('9.3 "how far do X move" → entity extracted, attr- routing', () async {
      // Verifies verb-at-end extraction. If extraction fails, canonical is empty
      // and debugSummary would be "empty-canonical" — that is the failure mode.
      final entity = _entity('Intercessors', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'how far do Intercessors move',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, isNot('empty-canonical'),
          reason: 'Entity must be extracted from verb-at-end pattern');
      expect(plan.debugSummary, startsWith('attr-'));
      expect(plan.entities, hasLength(1));
    });

    test('9.4 "how far does X move" → entity extracted correctly', () async {
      final entity = _entity('Intercessors', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'how far does the Intercessor move',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, isNot('empty-canonical'));
      expect(plan.debugSummary, startsWith('attr-'));
    });

    // ── Expanded synonym coverage ───────────────────────────────────────────

    test('9.5 "weapon skill" synonym → attr- routing', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the weapon skill of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('9.6 "toughness" synonym → attr- routing', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: "what's the toughness of Intercessors",
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('9.7 "wounds" synonym → attr- routing', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what are the wounds of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('9.8 "leadership" synonym → attr- routing', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the leadership of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('9.9 "save" synonym → attr- routing', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the save of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('attr-'));
    });

    test('9.10 "objective control" synonym → attr- routing', () async {
      final entity = _entity('Intercessor', 'intercessor', 'slot_0');
      final coord = _coordWith([entity]);
      final plan = await coord.handleTranscript(
        transcript: 'what is the objective control of Intercessors',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(plan.debugSummary, startsWith('attr-'));
    });

    // ── Determinism ────────────────────────────────────────────────────────

    test('9.11 Deterministic: "how far do X move" same plan on two instances',
        () async {
      final entity = _entity('Intercessors', 'intercessor', 'slot_0');
      final coord1 = _coordWith([entity]);
      final coord2 = _coordWith([entity]);
      final p1 = await coord1.handleTranscript(
        transcript: 'how far do Intercessors move',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      final p2 = await coord2.handleTranscript(
        transcript: 'how far do Intercessors move',
        slotBundles: _noopBundles,
        contextHints: const [],
      );
      expect(p1.primaryText, p2.primaryText);
      expect(p1.debugSummary, p2.debugSummary);
    });
  });

  // =========================================================================
  // Phase 12E-2 — Spoken Answer Assembly
  // =========================================================================
  //
  // Five answer types:
  //   A — Unit-level stat (T, M, SV, W, LD, OC) from UnitDoc.characteristics
  //   B — Weapon-level stat (BS, WS) from WeaponDoc.characteristics
  //   C — Rule list from UnitDoc.ruleDocRefs → RuleDoc.name
  //   D — Ability search across bundles via IndexBundle.unitsByKeyword
  //   E — No-match for unknown entity

  // ---------------------------------------------------------------------------
  // 10.A  Unit-level stat answers — helpers
  // ---------------------------------------------------------------------------
  //
  // Reuses _buildCoordTestBundle (unit with M='6"', T='4', SV='3+', etc.)
  // and a coordinator whose fake facade returns the matching entity.

  group('10. Phase 12E-2 — spoken answer assembly', () {
    // Shared setup reused by tests A1, A2, B.
    const _unitEntryId12e2 = 'intercessor-12e2';
    const _weaponProfileId12e2 = 'bolt-rifle-12e2';
    const _unitName12e2 = 'Intercessor';
    const _weaponName12e2 = 'Bolt Rifle';
    const _bs12e2 = '3+';

    late IndexBundle _bundle12e2;

    setUp(() {
      _bundle12e2 = _buildCoordTestBundle(
        unitEntryId: _unitEntryId12e2,
        unitName: _unitName12e2,
        weaponProfileId: _weaponProfileId12e2,
        weaponName: _weaponName12e2,
        bsValue: _bs12e2,
      );
    });

    // Builds a coordinator whose fake returns an entity with docId matching
    // [unitEntryId] in [bundle], wired to slot_0.
    VoiceAssistantCoordinator _coordFor(
        String unitEntryId, String groupKey, String displayName) {
      final entity = SpokenEntity(
        slotId: 'slot_0',
        groupKey: groupKey,
        displayName: displayName,
        variants: [
          SpokenVariant(
            sourceSlotId: 'slot_0',
            docType: SearchDocType.unit,
            docId: 'unit:$unitEntryId',
            canonicalKey: groupKey,
            displayName: displayName,
            matchReasons: const [MatchReason.canonicalKeyMatch],
            tieBreakKey: '$groupKey\x00unit:$unitEntryId',
          ),
        ],
      );
      return VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [entity]),
      );
    }

    // ── A: Unit-level stat answers ──────────────────────────────────────────

    test('10.A1 Toughness stat → "Intercessor toughness is 4."', () async {
      // UnitDoc has T='4' (from _iUnitProfile). The coordinator must read
      // UnitDoc.characteristics directly — NOT look in weapons.
      final coord = _coordFor(_unitEntryId12e2, 'intercessor', _unitName12e2);
      final plan = await coord.handleTranscript(
        transcript: 'what is the toughness of Intercessors',
        slotBundles: {'slot_0': _bundle12e2},
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        startsWith('attr-answer:t:'),
        reason: 'Toughness must reach attr-answer branch via UnitDoc.characteristics',
      );
      expect(plan.primaryText, contains('toughness'));
      expect(plan.primaryText, contains('4'));
      expect(plan.primaryText, isNot(contains('T')), // no raw code
          reason: 'Spoken answer must not expose the raw BattleScribe code "T"');
    });

    test('10.A2 Movement stat → spoken value "6 inches" (not raw \'6"\')', () async {
      // UnitDoc has M='6"'. The coordinator must format the inch symbol as
      // "inches" for TTS-friendliness.
      final coord = _coordFor(_unitEntryId12e2, 'intercessor', _unitName12e2);
      final plan = await coord.handleTranscript(
        transcript: 'what is the movement of Intercessors',
        slotBundles: {'slot_0': _bundle12e2},
        contextHints: const [],
      );

      expect(plan.debugSummary, startsWith('attr-answer:m:'));
      expect(plan.primaryText, contains('movement'));
      expect(plan.primaryText, contains('6 inches'),
          reason: '6" must be spoken as "6 inches"');
      expect(plan.primaryText, isNot(contains('"')),
          reason: 'Raw inch symbol must not appear in spoken answer');
    });

    // ── B: Weapon-level stat answer ─────────────────────────────────────────

    test('10.B Weapon BS → "Bolt Rifle ballistic skill is 3 plus."', () async {
      // Verifies natural-language format for weapon stat: spoken attr name and
      // spoken value ("3 plus" not "3+"). Single weapon → single-sentence format.
      final coord = _coordFor(_unitEntryId12e2, 'intercessor', _unitName12e2);
      final plan = await coord.handleTranscript(
        transcript: 'what is the ballistic skill of Intercessors',
        slotBundles: {'slot_0': _bundle12e2},
        contextHints: const [],
      );

      expect(plan.debugSummary, startsWith('attr-answer:bs:'));
      expect(plan.primaryText, contains('ballistic skill'));
      expect(plan.primaryText, contains(_weaponName12e2));
      expect(plan.primaryText, contains('3 plus'),
          reason: '"3+" must be spoken as "3 plus"');
      expect(plan.primaryText, isNot(contains('BS')),
          reason: 'Raw attribute code must not appear in spoken answer');
    });

    // ── C: Rule list answer ─────────────────────────────────────────────────

    test('10.C Rule list → "Carnifex has Synapse and Deadly Demise."', () async {
      // Builds a unit with two ability profiles. The coordinator must read
      // UnitDoc.ruleDocRefs → RuleDoc.name and format as a natural list.
      const entryId = 'carnifex-c001';
      const unitName = 'Carnifex';

      final abilityProfs = [
        BoundProfile(
          id: 'ability-synapse-c001',
          name: 'Synapse',
          typeId: 'type-ability',
          typeName: 'ability',
          characteristics: const [(name: 'description', value: 'A synapse creature.')],
          sourceFileId: _iTestCatFileId,
          sourceNode: const NodeRef(0),
        ),
        BoundProfile(
          id: 'ability-dd-c001',
          name: 'Deadly Demise',
          typeId: 'type-ability',
          typeName: 'ability',
          characteristics: const [(name: 'description', value: 'Roll a D6.')],
          sourceFileId: _iTestCatFileId,
          sourceNode: const NodeRef(0),
        ),
      ];

      final unitProf = _iUnitProfile('unit-prof-$entryId');
      final entry = BoundEntry(
        id: entryId,
        name: unitName,
        isGroup: false,
        isHidden: false,
        children: const [],
        profiles: [unitProf, ...abilityProfs],
        categories: const [],
        costs: const [],
        constraints: const [],
        sourceFileId: _iTestCatFileId,
        sourceNode: const NodeRef(0),
      );
      final wrapped = _iWrappedBundle();
      final linked = _iLinkedBundle(wrapped);
      final bound = BoundPackBundle(
        packId: 'coord-test-pack',
        boundAt: DateTime(2026, 1, 1),
        entries: [entry],
        profiles: [unitProf, ...abilityProfs],
        categories: const [],
        diagnostics: const [],
        linkedBundle: linked,
      );
      final testBundle = IndexService().buildIndex(bound);

      final entity = SpokenEntity(
        slotId: 'slot_0',
        groupKey: 'carnifex',
        displayName: unitName,
        variants: [
          SpokenVariant(
            sourceSlotId: 'slot_0',
            docType: SearchDocType.unit,
            docId: 'unit:$entryId',
            canonicalKey: 'carnifex',
            displayName: unitName,
            matchReasons: const [MatchReason.canonicalKeyMatch],
            tieBreakKey: 'carnifex\x00unit:$entryId',
          ),
        ],
      );
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [entity]),
      );

      final plan = await coord.handleTranscript(
        transcript: 'rules for Carnifex',
        slotBundles: {'slot_0': testBundle},
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        startsWith('rules-answer:'),
        reason: 'Rule list query must reach rules-answer branch',
      );
      expect(plan.primaryText, contains(unitName));
      expect(plan.primaryText, contains('Synapse'));
      expect(plan.primaryText, contains('Deadly Demise'));
    });

    // ── D: Ability search answer ────────────────────────────────────────────

    test('10.D Ability search → "N units have Synapse, including Carnifex."',
        () async {
      // Builds a unit whose keyword tokens include "synapse" (via categories).
      // The coordinator must use IndexBundle.unitsByKeyword — NOT the facade.
      const entryId = 'carnifex-d001';
      const unitName = 'Carnifex';

      final unitProf = _iUnitProfile('unit-prof-$entryId');
      final synapseCategory = BoundCategory(
        id: 'cat-synapse-d001',
        name: 'Synapse',
        isPrimary: false,
        sourceFileId: _iTestCatFileId,
        sourceNode: const NodeRef(0),
      );
      final entry = BoundEntry(
        id: entryId,
        name: unitName,
        isGroup: false,
        isHidden: false,
        children: const [],
        profiles: [unitProf],
        categories: [synapseCategory],
        costs: const [],
        constraints: const [],
        sourceFileId: _iTestCatFileId,
        sourceNode: const NodeRef(0),
      );
      final wrapped = _iWrappedBundle();
      final linked = _iLinkedBundle(wrapped);
      final bound = BoundPackBundle(
        packId: 'coord-test-pack',
        boundAt: DateTime(2026, 1, 1),
        entries: [entry],
        profiles: [unitProf],
        categories: const [],
        diagnostics: const [],
        linkedBundle: linked,
      );
      final testBundle = IndexService().buildIndex(bound);

      // Facade returns nothing — ability search bypasses facade entirely.
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => []),
      );

      final plan = await coord.handleTranscript(
        transcript: 'which units have synapse',
        slotBundles: {'slot_0': testBundle},
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        startsWith('ability-search:synapse:'),
        reason: 'Ability search must use unitsByKeyword, not searchFacade',
      );
      expect(plan.primaryText, contains('Synapse'),
          reason: 'Ability name must be capitalised in the spoken answer');
      expect(plan.primaryText, contains(unitName),
          reason: 'Matched unit name must appear in the spoken answer');
    });

    // ── E: No-match answer ──────────────────────────────────────────────────

    test('10.E No-match → natural-language "couldn\'t find" message', () async {
      // Facade returns nothing — simulates a unit name not in the loaded data.
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => []),
      );

      final plan = await coord.handleTranscript(
        transcript: "what is the toughness of Xyzzy Unit 9999",
        slotBundles: _noopBundles,
        contextHints: const [],
      );

      expect(plan.entities, isEmpty);
      expect(plan.debugSummary, startsWith('no-results:'));
      expect(
        plan.primaryText,
        contains("couldn't find"),
        reason: 'No-match spoken answer must be natural language, not a code string',
      );
    });
  });

  // =========================================================================
  // Phase 12E-3 — Clarification Dialogue
  // =========================================================================
  //
  // Three ambiguity classes:
  //   A — Weapon-dependent stat ambiguity: multiple weapons → ask "Which weapon?"
  //   B — Multi-entity ambiguity: multiple strong candidates → "Which X? A, B, or C."
  //   C — Too-broad ability search: count > threshold → adds narrowing suggestion
  //   D — No-regression: direct-answer paths are unaffected

  group('11. Phase 12E-3 — clarification dialogue', () {
    // Builds an IndexBundle with one unit that has TWO ranged weapons.
    // Used for weapon-clarification tests (A1, A2).
    //
    // UnitDoc.docId   = 'unit:intercessor-wc001'
    // WeaponDoc.docIds = 'weapon:bp-wc001', 'weapon:br-wc001'
    const _wcUnitEntryId = 'intercessor-wc001';
    const _wcUnitName = 'Intercessor';

    late IndexBundle _wcBundle;

    setUp(() {
      // Bolt Pistol: BS 4+, Bolt Rifle: BS 3+  (deliberately different so
      // both appear in attrLines when the coordinator queries BS)
      final unitProf = _iUnitProfile('unit-prof-$_wcUnitEntryId');
      final boltPistol = _iRangedWeaponProfile('bp-wc001', 'Bolt Pistol', '4+');
      final boltRifle = _iRangedWeaponProfile('br-wc001', 'Bolt Rifle', '3+');

      final entry = _iEntry(
        id: _wcUnitEntryId,
        name: _wcUnitName,
        profiles: [unitProf, boltPistol, boltRifle],
      );
      final wrapped = _iWrappedBundle();
      final linked = _iLinkedBundle(wrapped);
      final bound = BoundPackBundle(
        packId: 'coord-test-pack',
        boundAt: DateTime(2026, 1, 1),
        entries: [entry],
        profiles: [unitProf, boltPistol, boltRifle],
        categories: const [],
        diagnostics: const [],
        linkedBundle: linked,
      );
      _wcBundle = IndexService().buildIndex(bound);
    });

    /// Returns a coordinator whose fake facade returns a single entity that
    /// maps to [unitEntryId] in slot_0.
    VoiceAssistantCoordinator _coordForWc(
        String unitEntryId, String groupKey, String displayName) {
      final entity = SpokenEntity(
        slotId: 'slot_0',
        groupKey: groupKey,
        displayName: displayName,
        variants: [
          SpokenVariant(
            sourceSlotId: 'slot_0',
            docType: SearchDocType.unit,
            docId: 'unit:$unitEntryId',
            canonicalKey: groupKey,
            displayName: displayName,
            matchReasons: const [MatchReason.canonicalKeyMatch],
            tieBreakKey: '$groupKey\x00unit:$unitEntryId',
          ),
        ],
      );
      return VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [entity]),
      );
    }

    // ── A: Weapon-dependent stat clarification ──────────────────────────────

    test(
        '11.A1 Multiple weapons with BS → "Which weapon?" clarification, '
        'no direct answer', () async {
      // Both Bolt Pistol (BS 4+) and Bolt Rifle (BS 3+) have a BS value.
      // The coordinator must ask which weapon rather than guessing one.
      final coord = _coordForWc(_wcUnitEntryId, 'intercessor', _wcUnitName);

      final plan = await coord.handleTranscript(
        transcript: 'what is the ballistic skill of Intercessors',
        slotBundles: {'slot_0': _wcBundle},
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        startsWith('weapon-clarify:'),
        reason: 'Multiple weapons with the attribute must trigger weapon clarification',
      );
      expect(plan.primaryText, contains('Which weapon'),
          reason: 'Clarification prompt must ask which weapon');
      expect(plan.primaryText, isNot(anyOf(contains('3 plus'), contains('4 plus'))),
          reason: 'Must not guess a weapon stat value before clarification');
      // Options must be listed (≤ 3 weapons in test setup)
      expect(plan.primaryText, contains('Bolt Pistol'),
          reason: 'Short weapon list must be included in clarification prompt');
      expect(plan.primaryText, contains('Bolt Rifle'),
          reason: 'Short weapon list must be included in clarification prompt');
    });

    test(
        '11.A2 Weapon clarification resolved — saying "bolt rifle" answers directly',
        () async {
      final coord = _coordForWc(_wcUnitEntryId, 'intercessor', _wcUnitName);
      final slotBundles = {'slot_0': _wcBundle};

      // Round 1: triggers clarification
      await coord.handleTranscript(
        transcript: 'what is the ballistic skill of Intercessors',
        slotBundles: slotBundles,
        contextHints: const [],
      );

      // Round 2: user names the specific weapon
      final plan = await coord.handleTranscript(
        transcript: 'bolt rifle',
        slotBundles: slotBundles,
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        startsWith('attr-answer:bs:'),
        reason: 'Weapon name response must resolve to attr-answer',
      );
      expect(plan.primaryText, contains('Bolt Rifle'));
      expect(plan.primaryText, contains('3 plus'),
          reason: 'Bolt Rifle BS is 3+, spoken as "3 plus"');
      expect(plan.primaryText, isNot(contains('4 plus')),
          reason: 'Must not conflate Bolt Pistol value');
    });

    // ── B: Multi-entity clarification ───────────────────────────────────────

    test(
        '11.B1 ≤ 3 entities → "Which Captain? A, B, or C." (names listed inline)',
        () async {
      // All three groupKeys start with "captain " → score 2 each → tie → all kept.
      final e1 = _entity(
          'Captain in Phobos Armour', 'captain in phobos armour', 'slot_0');
      final e2 = _entity(
          'Captain with Jump Pack', 'captain with jump pack', 'slot_0');
      final e3 = _entity('Captain in Terminator Armour',
          'captain in terminator armour', 'slot_0');
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [e1, e2, e3]),
      );

      final plan = await coord.handleTranscript(
        transcript: 'captain',
        slotBundles: _noopBundles,
        contextHints: const [],
      );

      expect(plan.debugSummary, startsWith('disambiguation:3'));
      expect(plan.followUps, containsAll(['next', 'select', 'cancel']));

      // Prompt must name the options, not just announce a count.
      expect(plan.primaryText, contains('Which'),
          reason: 'Prompt must start with "Which"');
      expect(plan.primaryText, contains('Captain in Phobos Armour'),
          reason: 'All 3 names must appear in prompt');
      expect(plan.primaryText, contains('Captain with Jump Pack'));
      expect(plan.primaryText, contains('Captain in Terminator Armour'));
    });

    test(
        '11.B2 > 3 entities → count + browse prompt (names NOT all listed)',
        () async {
      // Five entities: all start with "captain " → score 2 each → tie → all kept.
      final entities = [
        _entity('Captain Alpha', 'captain alpha', 'slot_0'),
        _entity('Captain Beta', 'captain beta', 'slot_0'),
        _entity('Captain Gamma', 'captain gamma', 'slot_0'),
        _entity('Captain Delta', 'captain delta', 'slot_0'),
        _entity('Captain Epsilon', 'captain epsilon', 'slot_0'),
      ];
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => entities),
      );

      final plan = await coord.handleTranscript(
        transcript: 'captain',
        slotBundles: _noopBundles,
        contextHints: const [],
      );

      expect(plan.debugSummary, startsWith('disambiguation:5'));
      // Must mention the count.
      expect(plan.primaryText, contains('5'),
          reason: 'Count must appear in prompt when there are too many to list');
      // Must NOT try to list all 5 names.
      expect(
        plan.primaryText,
        isNot(allOf(
            contains('Captain Alpha'),
            contains('Captain Beta'),
            contains('Captain Gamma'),
            contains('Captain Delta'),
            contains('Captain Epsilon'))),
        reason: 'Prompt must not dump all entity names when count exceeds limit',
      );
    });

    // ── C: Too-broad ability search ─────────────────────────────────────────

    test(
        '11.C1 > 10 units with keyword → narrowing suggestion appended',
        () async {
      // Build 11 units each with the "Infantry" keyword category.
      // 11 > _kAbilitySearchWideThreshold (10), so narrowing text must appear.
      const totalUnits = 11;
      final entries = <BoundEntry>[];
      final profiles = <BoundProfile>[];

      for (var i = 1; i <= totalUnits; i++) {
        final prof = _iUnitProfile('prof-infantry-$i');
        final infantryCat = BoundCategory(
          id: 'cat-infantry-$i',
          name: 'Infantry',
          isPrimary: false,
          sourceFileId: _iTestCatFileId,
          sourceNode: const NodeRef(0),
        );
        entries.add(BoundEntry(
          id: 'unit-infantry-$i',
          name: 'Unit $i',
          isGroup: false,
          isHidden: false,
          children: const [],
          profiles: [prof],
          categories: [infantryCat],
          costs: const [],
          constraints: const [],
          sourceFileId: _iTestCatFileId,
          sourceNode: const NodeRef(0),
        ));
        profiles.add(prof);
      }

      final wrapped = _iWrappedBundle();
      final linked = _iLinkedBundle(wrapped);
      final bound = BoundPackBundle(
        packId: 'coord-test-pack',
        boundAt: DateTime(2026, 1, 1),
        entries: entries,
        profiles: profiles,
        categories: const [],
        diagnostics: const [],
        linkedBundle: linked,
      );
      final testBundle = IndexService().buildIndex(bound);

      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => []),
      );

      final plan = await coord.handleTranscript(
        transcript: 'which units have infantry',
        slotBundles: {'slot_0': testBundle},
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        'ability-search:infantry:$totalUnits',
        reason: 'debugSummary must include exact count',
      );
      expect(plan.primaryText, contains('$totalUnits'),
          reason: 'Total count must appear in spoken answer');
      expect(
        plan.primaryText,
        anyOf(
          contains('narrow'),
          contains('specific'),
          contains('unit name'),
        ),
        reason:
            'Wide result set must include a narrowing suggestion in the spoken answer',
      );
    });

    // ── D: No-regression ────────────────────────────────────────────────────

    test(
        '11.D1 Single-weapon unit — weapon stat answered directly, '
        'no weapon-clarify triggered', () async {
      // Uses the same single-weapon bundle as group 8/10.B.
      // Verifies weapon clarification is not triggered for a unit with only
      // one weapon carrying the requested attribute.
      const entryId = 'intercessor-d001';
      final testBundle = _buildCoordTestBundle(
        unitEntryId: entryId,
        unitName: 'Intercessor',
        weaponProfileId: 'br-d001',
        weaponName: 'Bolt Rifle',
        bsValue: '3+',
      );
      final entity = SpokenEntity(
        slotId: 'slot_0',
        groupKey: 'intercessor',
        displayName: 'Intercessor',
        variants: [
          SpokenVariant(
            sourceSlotId: 'slot_0',
            docType: SearchDocType.unit,
            docId: 'unit:$entryId',
            canonicalKey: 'intercessor',
            displayName: 'Intercessor',
            matchReasons: const [MatchReason.canonicalKeyMatch],
            tieBreakKey: 'intercessor\x00unit:$entryId',
          ),
        ],
      );
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [entity]),
      );

      final plan = await coord.handleTranscript(
        transcript: 'what is the ballistic skill of Intercessors',
        slotBundles: {'slot_0': testBundle},
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        isNot(startsWith('weapon-clarify:')),
        reason: 'Single-weapon unit must not trigger weapon clarification',
      );
      expect(plan.debugSummary, startsWith('attr-answer:bs:'));
      expect(plan.primaryText, contains('3 plus'));
    });

    test(
        '11.D2 Single entity matched for rules — answers directly, '
        'no disambiguation triggered', () async {
      // A query that yields one entity must go straight to rules-answer,
      // not open a disambiguation session.
      final entity = _entity('Carnifex', 'carnifex', 'slot_0');
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [entity]),
      );

      final plan = await coord.handleTranscript(
        transcript: 'rules for Carnifex',
        slotBundles: _noopBundles,
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        isNot(startsWith('disambiguation:')),
        reason: 'Single-entity result must not open a disambiguation session',
      );
      // With no real bundle, path is rules-no-bundle — still not disambiguation.
      expect(
        plan.debugSummary,
        anyOf(startsWith('rules-'), startsWith('rules-no-bundle')),
      );
    });
  });

  // =========================================================================
  // Phase 12E-4 — Query-Shape Expansion
  // =========================================================================
  //
  // A — Movement queries: multi-word entity names, spoken answer confirmed.
  // B — Weapon-stat plural: "what are the X values for Y weapons" returns all
  //     weapon stats in compact form without triggering weapon clarification.
  // C — Rule query phrasing: "what rules/abilities does X have" routes to
  //     the rule-list answer, same surface as "rules for X".
  // D — No-regression: existing direct-answer paths unaffected.

  group('12. Phase 12E-4 — query-shape expansion', () {
    // ---------------------------------------------------------------------------
    // Shared: two-weapon bundle (Bolt Pistol BS 4+, Bolt Rifle BS 3+)
    // ---------------------------------------------------------------------------
    //
    // Reuses the same in-memory construction pattern as group 11.
    // UnitDoc.docId = 'unit:intercessor-12e4'
    // WeaponDoc docIds: 'weapon:bp-12e4', 'weapon:br-12e4'

    const _e4UnitEntryId = 'intercessor-12e4';
    const _e4UnitName = 'Intercessor';
    late IndexBundle _e4Bundle;

    setUp(() {
      final unitProf = _iUnitProfile('unit-prof-$_e4UnitEntryId');
      final boltPistol = _iRangedWeaponProfile('bp-12e4', 'Bolt Pistol', '4+');
      final boltRifle = _iRangedWeaponProfile('br-12e4', 'Bolt Rifle', '3+');
      final entry = _iEntry(
        id: _e4UnitEntryId,
        name: _e4UnitName,
        profiles: [unitProf, boltPistol, boltRifle],
      );
      final wrapped = _iWrappedBundle();
      final linked = _iLinkedBundle(wrapped);
      final bound = BoundPackBundle(
        packId: 'coord-test-pack',
        boundAt: DateTime(2026, 1, 1),
        entries: [entry],
        profiles: [unitProf, boltPistol, boltRifle],
        categories: const [],
        diagnostics: const [],
        linkedBundle: linked,
      );
      _e4Bundle = IndexService().buildIndex(bound);
    });

    /// Returns a coordinator whose fake facade returns [entity] for any query,
    /// wired to [unitEntryId] in slot_0.
    VoiceAssistantCoordinator _coordFor12e4(
        String unitEntryId, String groupKey, String displayName) {
      final entity = SpokenEntity(
        slotId: 'slot_0',
        groupKey: groupKey,
        displayName: displayName,
        variants: [
          SpokenVariant(
            sourceSlotId: 'slot_0',
            docType: SearchDocType.unit,
            docId: 'unit:$unitEntryId',
            canonicalKey: groupKey,
            displayName: displayName,
            matchReasons: const [MatchReason.canonicalKeyMatch],
            tieBreakKey: '$groupKey\x00unit:$unitEntryId',
          ),
        ],
      );
      return VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [entity]),
      );
    }

    // ── A: Movement queries ──────────────────────────────────────────────────

    test(
        '12.A1 "how far do jump pack intercessors move" → '
        'M stat answered with spoken inch value', () async {
      // Builds a real bundle with M='6"' for a multi-word entity name.
      // Verifies that _extractEntityName handles the verb-at-end pattern
      // correctly for multi-word unit names AND that _formatStatValue converts
      // '6"' → '6 inches' in the spoken answer.
      const entryId = 'jpi-12e4';
      final jpiBundle = _buildCoordTestBundle(
        unitEntryId: entryId,
        unitName: 'Jump Pack Intercessor',
        weaponProfileId: 'jpi-wpn-12e4',
        weaponName: 'Bolt Pistol',
        bsValue: '4+',
      );
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [
              SpokenEntity(
                slotId: 'slot_0',
                groupKey: 'jump pack intercessor',
                displayName: 'Jump Pack Intercessor',
                variants: [
                  SpokenVariant(
                    sourceSlotId: 'slot_0',
                    docType: SearchDocType.unit,
                    docId: 'unit:$entryId',
                    canonicalKey: 'jump pack intercessor',
                    displayName: 'Jump Pack Intercessor',
                    matchReasons: const [MatchReason.canonicalKeyMatch],
                    tieBreakKey:
                        'jump pack intercessor\x00unit:$entryId',
                  ),
                ],
              )
            ]),
      );

      final plan = await coord.handleTranscript(
        transcript: 'how far do Jump Pack Intercessors move',
        slotBundles: {'slot_0': jpiBundle},
        contextHints: const [],
      );

      expect(plan.debugSummary, startsWith('attr-answer:m:'),
          reason: 'Movement query must reach attr-answer via M characteristic');
      expect(plan.primaryText, contains('6 inches'),
          reason: '6" must be formatted as "6 inches" for voice');
      expect(plan.primaryText, isNot(contains('"')),
          reason: 'Raw inch symbol must not appear in spoken answer');
    });

    test('12.A2 "movement of carnifex" → routes to M attribute branch',
        () async {
      // No real bundle — verifies routing only (attr-no-bundle is correct output
      // when the bundle is absent; what matters is that the attr- branch was reached).
      final entity = _entity('Carnifex', 'carnifex', 'slot_0');
      final coord = _coordWith([entity]);

      final plan = await coord.handleTranscript(
        transcript: 'movement of Carnifex',
        slotBundles: _noopBundles,
        contextHints: const [],
      );

      expect(plan.debugSummary, startsWith('attr-'),
          reason: '"movement of X" must route through _handleAttributeQuestion');
    });

    // ── B: Weapon-stat plural queries ────────────────────────────────────────

    test(
        '12.B1 "what are the bs values for intercessor weapons" → '
        'compact all-weapon summary, no weapon clarification triggered', () async {
      // Unit has two weapons with BS: Bolt Pistol (4+) and Bolt Rifle (3+).
      // The plural phrasing means the user wants all values — the coordinator
      // must NOT trigger weapon clarification and must list both.
      final coord = _coordFor12e4(_e4UnitEntryId, 'intercessor', _e4UnitName);

      final plan = await coord.handleTranscript(
        transcript: 'what are the bs values for intercessor weapons',
        slotBundles: {'slot_0': _e4Bundle},
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        isNot(startsWith('weapon-clarify:')),
        reason: 'Plural weapon-stat query must not trigger weapon clarification',
      );
      expect(
        plan.debugSummary,
        startsWith('attr-answer:bs:'),
        reason: 'Must reach attr-answer branch for BS',
      );
      // Both weapon names and values must appear in the spoken answer.
      expect(plan.primaryText, contains('Bolt Pistol'),
          reason: 'Bolt Pistol must be included in multi-weapon summary');
      expect(plan.primaryText, contains('Bolt Rifle'),
          reason: 'Bolt Rifle must be included in multi-weapon summary');
      expect(plan.primaryText, contains('3 plus'),
          reason: 'Bolt Rifle BS 3+ must be spoken as "3 plus"');
      expect(plan.primaryText, contains('4 plus'),
          reason: 'Bolt Pistol BS 4+ must be spoken as "4 plus"');
    });

    test(
        '12.B2 "what are the ballistic skill values for intercessor weapons" → '
        'synonym "ballistic skill" resolved to BS, same result', () async {
      // Verifies that the multi-word synonym "ballistic skill" is recognised
      // in the plural phrasing, not just the short form "bs".
      final coord = _coordFor12e4(_e4UnitEntryId, 'intercessor', _e4UnitName);

      final plan = await coord.handleTranscript(
        transcript:
            'what are the ballistic skill values for intercessor weapons',
        slotBundles: {'slot_0': _e4Bundle},
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        startsWith('attr-answer:bs:'),
        reason: '"ballistic skill" must resolve to BS, same as "bs"',
      );
      expect(
        plan.debugSummary,
        isNot(startsWith('weapon-clarify:')),
        reason: 'Plural phrasing must not trigger weapon clarification',
      );
      expect(plan.primaryText, contains('Bolt Pistol'));
      expect(plan.primaryText, contains('Bolt Rifle'));
    });

    // ── C: Rule query phrasing ────────────────────────────────────────────────

    test(
        '12.C1 "what rules does carnifex have" → routes to rule-list branch',
        () async {
      // Before 12E-4, this phrasing fell through to generic search.
      // Now it must route to _handleRuleListQuestion (rules- debugSummary prefix).
      final entity = _entity('Carnifex', 'carnifex', 'slot_0');
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [entity]),
      );

      final plan = await coord.handleTranscript(
        transcript: 'what rules does Carnifex have',
        slotBundles: _noopBundles,
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        anyOf(startsWith('rules-'), startsWith('no-results:')),
        reason: '"what rules does X have" must route to rule-list handler, '
            'not fall back to generic search',
      );
      expect(
        plan.debugSummary,
        isNot(startsWith('single:')),
        reason: 'Must not reach generic search single-result path',
      );
    });

    test(
        '12.C2 "what abilities does carnifex have" → routes to rule-list branch',
        () async {
      // "abilities" maps to the same rule surface as "rules".
      // Before 12E-4, this fell through to generic entity search.
      final entity = _entity('Carnifex', 'carnifex', 'slot_0');
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [entity]),
      );

      final plan = await coord.handleTranscript(
        transcript: 'what abilities does Carnifex have',
        slotBundles: _noopBundles,
        contextHints: const [],
      );

      expect(
        plan.debugSummary,
        anyOf(startsWith('rules-'), startsWith('no-results:')),
        reason: '"what abilities does X have" must route to rule-list handler',
      );
      expect(
        plan.debugSummary,
        isNot(startsWith('single:')),
        reason: 'Must not reach generic search single-result path',
      );
    });

    // ── D: No-regression ─────────────────────────────────────────────────────

    test(
        '12.D1 "what is the bs of intercessors" still answered directly '
        '(single-weapon path unaffected)', () async {
      // The two-weapon bundle from this group's setUp would trigger clarification.
      // Use a single-weapon bundle to confirm the direct-answer path is intact.
      const entryId = 'intercessor-d-12e4';
      final singleWpnBundle = _buildCoordTestBundle(
        unitEntryId: entryId,
        unitName: 'Intercessor',
        weaponProfileId: 'br-d-12e4',
        weaponName: 'Bolt Rifle',
        bsValue: '3+',
      );
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => [
              SpokenEntity(
                slotId: 'slot_0',
                groupKey: 'intercessor',
                displayName: 'Intercessor',
                variants: [
                  SpokenVariant(
                    sourceSlotId: 'slot_0',
                    docType: SearchDocType.unit,
                    docId: 'unit:$entryId',
                    canonicalKey: 'intercessor',
                    displayName: 'Intercessor',
                    matchReasons: const [MatchReason.canonicalKeyMatch],
                    tieBreakKey: 'intercessor\x00unit:$entryId',
                  ),
                ],
              )
            ]),
      );

      final plan = await coord.handleTranscript(
        transcript: 'what is the bs of Intercessors',
        slotBundles: {'slot_0': singleWpnBundle},
        contextHints: const [],
      );

      expect(plan.debugSummary, startsWith('attr-answer:bs:'));
      expect(plan.primaryText, contains('3 plus'));
      expect(
        plan.debugSummary,
        isNot(startsWith('weapon-clarify:')),
        reason: 'Single-weapon unit must never trigger weapon clarification',
      );
    });

    test(
        '12.D2 "which units have synapse" still routes to ability-search '
        '(not confused with new rule-query phrasings)', () async {
      // Confirms that the "which units have" ability-search path is unaffected
      // by the new "what rules/abilities does X have" rule-list detection.
      final coord = VoiceAssistantCoordinator(
        searchFacade: _FakeSearchFacade((_) => []),
      );

      final plan = await coord.handleTranscript(
        transcript: 'which units have synapse',
        slotBundles: _noopBundles,
        contextHints: const [],
      );

      // Both 'ability-search:' (with results) and 'ability-search-empty:' (no
      // results, because _noopBundles is empty) confirm the handler was reached.
      expect(
        plan.debugSummary,
        startsWith('ability-search'),
        reason: '"which units have X" must still route to ability-search handler',
      );
    });
  });
}

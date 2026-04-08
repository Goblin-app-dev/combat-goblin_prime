/// Tests for the name resolution pipeline and entity selection refinement.
///
/// Covers:
///  - CanonicalNameResolver alias lookup (faction aliases, reordered names)
///  - Singular/plural rules and their guards
///  - CanonicalNameResolver wired into VoiceAssistantCoordinator
///  - Post-search canonical-quality filter (_filterByCanonicalQuality)
///
/// Run with:
///   flutter test test/voice/name_resolution_test.dart
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';
import 'package:combat_goblin_prime/voice/models/spoken_entity.dart';
import 'package:combat_goblin_prime/voice/models/spoken_variant.dart';
import 'package:combat_goblin_prime/voice/models/voice_search_response.dart';
import 'package:combat_goblin_prime/voice/understanding/canonical_name_resolver.dart';
import 'package:combat_goblin_prime/voice/understanding/voice_assistant_coordinator.dart';
import 'package:combat_goblin_prime/voice/voice_search_facade.dart';

// ---------------------------------------------------------------------------
// Helpers shared across groups
// ---------------------------------------------------------------------------

const _resolver = CanonicalNameResolver();

/// Builds a minimal [SpokenEntity] whose [groupKey] is [canonicalKey].
SpokenEntity _entity(String canonicalKey) {
  final variant = SpokenVariant(
    sourceSlotId: 'slot_0',
    docType: SearchDocType.unit,
    docId: 'unit:$canonicalKey',
    canonicalKey: canonicalKey,
    displayName: canonicalKey,
    matchReasons: const [MatchReason.canonicalKeyMatch],
    tieBreakKey: '$canonicalKey\x00unit:$canonicalKey',
  );
  return SpokenEntity(
    slotId: 'slot_0',
    groupKey: canonicalKey,
    displayName: canonicalKey,
    variants: [variant],
  );
}

/// Fake facade: records every query string passed to [searchText] and returns
/// a fixed set of entities regardless of slotBundles content.
class _RecordingFacade extends VoiceSearchFacade {
  final List<SpokenEntity> _entities;
  final List<String> queriesSeen = [];

  _RecordingFacade(this._entities);

  @override
  VoiceSearchResponse searchText(
    Map<String, IndexBundle> slotBundles,
    String query, {
    int limit = 50,
  }) {
    queriesSeen.add(query);
    return VoiceSearchResponse(
      entities: List.unmodifiable(_entities),
      diagnostics: const [],
      spokenSummary: '',
    );
  }
}

/// Coordinator wired to [facade].
VoiceAssistantCoordinator _coordWith(_RecordingFacade facade) =>
    VoiceAssistantCoordinator(searchFacade: facade);

// ---------------------------------------------------------------------------
// 1. CanonicalNameResolver — faction aliases
// ---------------------------------------------------------------------------

void main() {
  group('1. CanonicalNameResolver — faction aliases', () {
    test('1.1 "chaos daemons" → "legiones daemonica"', () {
      expect(_resolver.resolve('chaos daemons'), 'legiones daemonica');
    });

    test('1.2 Mixed-case "Chaos Daemons" normalises and maps correctly', () {
      expect(_resolver.resolve('Chaos Daemons'), 'legiones daemonica');
    });

    test('1.3 "chaos daemon" (singular) → "legiones daemonica"', () {
      expect(_resolver.resolve('chaos daemon'), 'legiones daemonica');
    });

    test('1.4 "daemons of chaos" → "legiones daemonica"', () {
      expect(_resolver.resolve('daemons of chaos'), 'legiones daemonica');
    });

    test('1.5 "daemons" shorthand → "legiones daemonica"', () {
      expect(_resolver.resolve('daemons'), 'legiones daemonica');
    });

    test('1.6 "daemon" shorthand → "legiones daemonica" via exact alias', () {
      expect(_resolver.resolve('daemon'), 'legiones daemonica');
    });
  });

  // ---------------------------------------------------------------------------
  // 2. CanonicalNameResolver — reordered unit name aliases
  // ---------------------------------------------------------------------------

  group('2. CanonicalNameResolver — reordered unit name aliases', () {
    // In the BSData wh40k-10e SM catalog the colloquial "Jump Pack Intercessors"
    // maps to the unit entry "Assault Intercessors with Jump Packs".

    test('2.1 "jump pack intercessors" → "assault intercessors with jump pack"',
        () {
      expect(
        _resolver.resolve('jump pack intercessors'),
        'assault intercessors with jump pack',
      );
    });

    test('2.2 Mixed-case "Jump Pack Intercessors" → '
        '"assault intercessors with jump pack"', () {
      expect(
        _resolver.resolve('Jump Pack Intercessors'),
        'assault intercessors with jump pack',
      );
    });

    test('2.3 "jump pack intercessor" (singular) → '
        '"assault intercessors with jump pack"', () {
      expect(
        _resolver.resolve('jump pack intercessor'),
        'assault intercessors with jump pack',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 3. CanonicalNameResolver — singular/plural stripping rules
  // ---------------------------------------------------------------------------

  group('3. CanonicalNameResolver — singular/plural stripping', () {
    test('3.1 "intercessors" plural → strips to "intercessor"', () {
      // Ensures M10 substring match finds "intercessor squad", etc.
      expect(_resolver.resolve('intercessors'), 'intercessor');
    });

    test('3.2 "carnifex" (no trailing s) → passes through unchanged', () {
      // Common singular unit name — no stripping or alias needed.
      expect(_resolver.resolve('carnifex'), 'carnifex');
    });

    test('3.3 "boss" → NOT stripped (ends in "ss")', () {
      expect(_resolver.resolve('boss'), 'boss');
    });

    test('3.4 "nexus" → NOT stripped (ends in "us")', () {
      expect(_resolver.resolve('nexus'), 'nexus');
    });

    test('3.5 "abilities" → NOT stripped (ends in "ies")', () {
      expect(_resolver.resolve('abilities'), 'abilities');
    });

    test('3.6 "nobs" → NOT stripped (stem "nob" is only 3 chars)', () {
      // Stripping guard: stripped stem must be >= 4 chars.
      expect(_resolver.resolve('nobs'), 'nobs');
    });

    test('3.7 Empty string → empty string', () {
      expect(_resolver.resolve(''), '');
    });

    test('3.8 Whitespace-only → empty string', () {
      expect(_resolver.resolve('   '), '');
    });

    test('3.9 Passthrough for unknown multi-word term', () {
      expect(_resolver.resolve('morvenn vahl'), 'morvenn vahl');
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Coordinator — CanonicalNameResolver wired into search pipeline
  // ---------------------------------------------------------------------------
  //
  // These tests verify the query that reaches the search engine after both
  // DomainCanonicalizer (STT correction) and CanonicalNameResolver (BSData
  // mapping) have been applied.
  //
  // The fake facade records the query without guarding on slotBundles content,
  // so empty slotBundles still trigger a recorded search call.

  group('4. Coordinator — resolver applied before search', () {
    test('4.1 "chaos daemons" → search receives "legiones daemonica"',
        () async {
      final facade = _RecordingFacade([]);
      await _coordWith(facade).handleTranscript(
        transcript: 'chaos daemons',
        slotBundles: const {},
        contextHints: const [],
      );
      expect(facade.queriesSeen, contains('legiones daemonica'));
    });

    test('4.2 "jump pack intercessors" → search receives '
        '"assault intercessors with jump pack"', () async {
      final facade = _RecordingFacade([]);
      await _coordWith(facade).handleTranscript(
        transcript: 'jump pack intercessors',
        slotBundles: const {},
        contextHints: const [],
      );
      expect(facade.queriesSeen, contains('assault intercessors with jump pack'));
    });

    test('4.3 "intercessors" → search receives plural-stripped "intercessor"',
        () async {
      final facade = _RecordingFacade([]);
      await _coordWith(facade).handleTranscript(
        transcript: 'intercessors',
        slotBundles: const {},
        contextHints: const [],
      );
      expect(facade.queriesSeen, contains('intercessor'));
    });

    test('4.4 Unaliased term passes through normalized', () async {
      final facade = _RecordingFacade([]);
      await _coordWith(facade).handleTranscript(
        transcript: 'carnifex',
        slotBundles: const {},
        contextHints: const [],
      );
      expect(facade.queriesSeen, contains('carnifex'));
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Coordinator — entity selection (canonical-quality filter)
  // ---------------------------------------------------------------------------
  //
  // _filterByCanonicalQuality is private; tested through coordinator behavior.
  //
  // Score tiers (deterministic, applied to entity.groupKey vs query):
  //   4 — exact match
  //   3 — singular/plural match (groupKey == query+'s' or vice-versa)
  //   2 — word-boundary prefix/suffix
  //   1 — general substring (all M10 hits; returned unchanged if all tie here)

  group('5. Entity selection — canonical-quality filter', () {
    test(
        '5.1 "intercessor" → base "intercessors" (score 3) preferred over '
        '"assault intercessors" (score 1)', () async {
      // This is the primary V1 blocker case.
      final assault = _entity('assault intercessors');
      final base = _entity('intercessors');
      final facade = _RecordingFacade([assault, base]);
      final coord = _coordWith(facade);

      final plan = await coord.handleTranscript(
        transcript: 'intercessor',
        slotBundles: const {},
        contextHints: const [],
      );

      // Query after resolver: "intercessor" (no alias, no strip — already singular).
      // Score for "intercessors": 'intercessors' == 'intercessor'+'s' → 3.
      // Score for "assault intercessors": general substring → 1.
      // Filter keeps only score-3 entities → ["intercessors"].
      // 1 entity → coordinator auto-selects.
      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.groupKey, 'intercessors');
    });

    test(
        '5.2 "intercessors" input → plural-strips to "intercessor" → '
        'same quality filter applies', () async {
      final assault = _entity('assault intercessors');
      final base = _entity('intercessors');
      final facade = _RecordingFacade([assault, base]);
      final coord = _coordWith(facade);

      final plan = await coord.handleTranscript(
        transcript: 'intercessors',
        slotBundles: const {},
        contextHints: const [],
      );

      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.groupKey, 'intercessors');
    });

    test('5.3 Exact match (score 4) beats plural match (score 3)', () async {
      // If the index stores exactly the query string, it wins over a plural form.
      final exact = _entity('carnifex');
      final plural = _entity('carnifexes'); // unlikely but tests the tier
      final facade = _RecordingFacade([exact, plural]);
      final coord = _coordWith(facade);

      final plan = await coord.handleTranscript(
        transcript: 'carnifex',
        slotBundles: const {},
        contextHints: const [],
      );

      // "carnifex" == "carnifex" → score 4.
      // "carnifexes" == "carnifex"+'s' → score 3.
      // Filter keeps only score-4.
      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.groupKey, 'carnifex');
    });

    test('5.4 "assault intercessors" query selects assault, not base unit',
        () async {
      // Verify the filter does not always prefer the shorter name —
      // it prefers the closest canonical match to the actual query.
      final assault = _entity('assault intercessors');
      final base = _entity('intercessors');
      final facade = _RecordingFacade([assault, base]);
      final coord = _coordWith(facade);

      final plan = await coord.handleTranscript(
        // "assault intercessors" → plural strip → "assault intercessor"
        transcript: 'assault intercessors',
        slotBundles: const {},
        contextHints: const [],
      );

      // Query: "assault intercessor" (after strip).
      // "assault intercessors" == "assault intercessor"+'s' → score 3.
      // "intercessors": none of the score-3+ checks match "assault intercessor"
      //   → score 1.
      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.groupKey, 'assault intercessors');
    });

    test(
        '5.5 All-score-1 tie → full list returned for normal disambiguation',
        () async {
      // When no entity scores above 1, the filter must not discard anything.
      // Discarding all score-1 entities would cause false "no results" responses.
      final e1 = _entity('assault intercessors');
      final e2 = _entity('heavy intercessors');
      final facade = _RecordingFacade([e1, e2]);
      final coord = _coordWith(facade);

      // Query "veteran" matches neither entity name at score > 1.
      // (In practice M10 would not return these; but the fake does, so we
      // can test the filter's tie behaviour directly.)
      final plan = await coord.handleTranscript(
        transcript: 'veteran',
        slotBundles: const {},
        contextHints: const [],
      );

      expect(plan.entities, hasLength(2),
          reason: 'all-score-1 tie must be kept for disambiguation, '
              'not silently dropped');
    });

    test(
        '5.6 Word-boundary prefix (score 2) beats general substring (score 1)',
        () async {
      // "intercessor squad" starts with "intercessor " (word boundary after
      // query) — score 2. "assault intercessors" is a general substring —
      // score 1.
      final squad = _entity('intercessor squad');
      final assault = _entity('assault intercessors');
      final facade = _RecordingFacade([squad, assault]);
      final coord = _coordWith(facade);

      final plan = await coord.handleTranscript(
        transcript: 'intercessor',
        slotBundles: const {},
        contextHints: const [],
      );

      // "intercessor squad".startsWith("intercessor ") → true → score 2.
      // "assault intercessors" → score 1.
      // Filter keeps only score-2 entity.
      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.groupKey, 'intercessor squad');
    });
  });
}

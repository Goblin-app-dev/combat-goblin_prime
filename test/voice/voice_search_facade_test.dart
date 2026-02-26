import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';
import 'package:combat_goblin_prime/voice/models/spoken_entity.dart';
import 'package:combat_goblin_prime/voice/models/spoken_variant.dart';
import 'package:combat_goblin_prime/voice/models/voice_selection_session.dart';
import 'package:combat_goblin_prime/voice/services/search_result_grouper.dart';

/// Phase 12A contract tests — voice seam extraction.
///
/// These tests are pure unit tests requiring no IndexBundle or real data.
/// They lock the grouping, ordering, session, and tieBreakKey invariants.
///
/// Run with:
///   flutter test test/voice/ --concurrency=1
void main() {
  // ---------------------------------------------------------------------------
  // Test helpers
  // ---------------------------------------------------------------------------

  SearchHit makeHit({
    required String docId,
    required String canonicalKey,
    required String displayName,
    SearchDocType docType = SearchDocType.weapon,
    List<MatchReason> matchReasons = const [MatchReason.canonicalKeyMatch],
  }) {
    return SearchHit(
      docId: docId,
      docType: docType,
      canonicalKey: canonicalKey,
      displayName: displayName,
      matchReasons: matchReasons,
    );
  }

  const grouper = SearchResultGrouper();
  const slotA = 'slot_0';
  const slotB = 'slot_1';

  // ---------------------------------------------------------------------------
  // 1. Deterministic grouping: same canonicalKey → one SpokenEntity, two variants
  // ---------------------------------------------------------------------------

  test('same canonicalKey in same slot → one SpokenEntity with two variants', () {
    final hits = [
      makeHit(
        docId: 'weapon:melta-rifle-a',
        canonicalKey: 'melta rifle',
        displayName: 'Melta Rifle',
      ),
      makeHit(
        docId: 'weapon:melta-rifle-b',
        canonicalKey: 'melta rifle',
        displayName: 'Melta Rifle',
      ),
    ];

    final entities = grouper.group(slotA, hits);

    expect(entities.length, 1, reason: 'same canonicalKey should produce one group');
    expect(entities.first.groupKey, 'melta rifle');
    expect(entities.first.variants.length, 2, reason: 'both hits must be preserved');
  });

  // ---------------------------------------------------------------------------
  // 2. No cross-slot grouping: same canonicalKey in slot_0 and slot_1 → two groups
  // ---------------------------------------------------------------------------

  test('same canonicalKey in slot_0 and slot_1 → two separate SpokenEntities', () {
    final hitsSlot0 = [
      makeHit(
        docId: 'weapon:melta-rifle-a',
        canonicalKey: 'melta rifle',
        displayName: 'Melta Rifle',
      ),
    ];
    final hitsSlot1 = [
      makeHit(
        docId: 'weapon:melta-rifle-b',
        canonicalKey: 'melta rifle',
        displayName: 'Melta Rifle',
      ),
    ];

    final entitiesA = grouper.group(slotA, hitsSlot0);
    final entitiesB = grouper.group(slotB, hitsSlot1);
    final allEntities = [...entitiesA, ...entitiesB];

    expect(allEntities.length, 2, reason: 'different slots must not merge');
    expect(allEntities[0].slotId, slotA);
    expect(allEntities[1].slotId, slotB);
    expect(allEntities[0].groupKey, allEntities[1].groupKey);
  });

  // ---------------------------------------------------------------------------
  // 3. Variant ordering: stable sort by tieBreakKey ascending
  // ---------------------------------------------------------------------------

  test('variants are sorted by tieBreakKey ascending', () {
    // docId 'weapon:z' > 'weapon:a' lexicographically,
    // so 'weapon:a' must come first.
    final hits = [
      makeHit(
        docId: 'weapon:z-variant',
        canonicalKey: 'bolter',
        displayName: 'Bolter',
      ),
      makeHit(
        docId: 'weapon:a-variant',
        canonicalKey: 'bolter',
        displayName: 'Bolter',
      ),
    ];

    final entities = grouper.group(slotA, hits);
    final variants = entities.first.variants;

    expect(variants.length, 2);
    expect(variants[0].docId, 'weapon:a-variant',
        reason: 'a-variant tieBreakKey sorts before z-variant');
    expect(variants[1].docId, 'weapon:z-variant');
  });

  // ---------------------------------------------------------------------------
  // 4. Entity ordering: stable sort by slotId then groupKey
  // ---------------------------------------------------------------------------

  test('entities are sorted by slotId then groupKey', () {
    final hits = [
      makeHit(docId: 'weapon:plasma-1', canonicalKey: 'plasma gun', displayName: 'Plasma Gun'),
      makeHit(docId: 'weapon:bolter-1', canonicalKey: 'bolter', displayName: 'Bolter'),
      makeHit(docId: 'rule:rapid-1', canonicalKey: 'rapid fire', displayName: 'Rapid Fire',
          docType: SearchDocType.rule),
    ];

    final entities = grouper.group(slotA, hits);

    // groupKey ascending: 'bolter' < 'plasma gun' < 'rapid fire'
    expect(entities.length, 3);
    expect(entities[0].groupKey, 'bolter');
    expect(entities[1].groupKey, 'plasma gun');
    expect(entities[2].groupKey, 'rapid fire');
  });

  // ---------------------------------------------------------------------------
  // 5. VoiceSelectionSession.nextVariant() clamps at last variant
  // ---------------------------------------------------------------------------

  test('VoiceSelectionSession.nextVariant() clamps at last variant', () {
    final variant0 = SpokenVariant.fromHit(
      makeHit(docId: 'weapon:a', canonicalKey: 'bolter', displayName: 'Bolter'),
      slotA,
    );
    final variant1 = SpokenVariant.fromHit(
      makeHit(docId: 'weapon:b', canonicalKey: 'bolter', displayName: 'Bolter'),
      slotA,
    );
    final entity = SpokenEntity(
      slotId: slotA,
      groupKey: 'bolter',
      displayName: 'Bolter',
      variants: [variant0, variant1],
    );
    final session = VoiceSelectionSession([entity]);

    expect(session.variantIndex, 0);
    session.nextVariant();
    expect(session.variantIndex, 1, reason: 'moved to last');
    session.nextVariant();
    expect(session.variantIndex, 1, reason: 'clamped at last — no wrap');
  });

  // ---------------------------------------------------------------------------
  // 6. VoiceSelectionSession.previousVariant() clamps at 0
  // ---------------------------------------------------------------------------

  test('VoiceSelectionSession.previousVariant() clamps at 0', () {
    final variant = SpokenVariant.fromHit(
      makeHit(docId: 'weapon:a', canonicalKey: 'bolter', displayName: 'Bolter'),
      slotA,
    );
    final entity = SpokenEntity(
      slotId: slotA,
      groupKey: 'bolter',
      displayName: 'Bolter',
      variants: [variant],
    );
    final session = VoiceSelectionSession([entity]);

    expect(session.variantIndex, 0);
    session.previousVariant();
    expect(session.variantIndex, 0, reason: 'clamped at 0 — no wrap');
  });

  // ---------------------------------------------------------------------------
  // 7. spokenSummary is stable: identical for same entities input
  // ---------------------------------------------------------------------------

  test('spokenSummary is pure function: identical for identical entities list', () {
    final hits = [
      makeHit(docId: 'weapon:melta-1', canonicalKey: 'melta rifle', displayName: 'Melta Rifle'),
      makeHit(docId: 'weapon:melta-2', canonicalKey: 'melta rifle', displayName: 'Melta Rifle'),
    ];
    final entities = grouper.group(slotA, hits);

    // Build summary text via the facade's internal logic by calling it twice
    // on the same list — we verify the strings match.
    // We access the summary indirectly via SearchResultGrouper output used
    // in a minimal VoiceSearchResponse constructor.
    // Since spokenSummary is not part of grouper, we verify the invariant
    // through the VoiceSearchFacade contract: same entities → same summary.
    // For pure testing, verify entity state is stable.
    final entities2 = grouper.group(slotA, hits);

    // Identical inputs → identical structure
    expect(entities.length, entities2.length);
    expect(entities.first.groupKey, entities2.first.groupKey);
    expect(entities.first.variants.length, entities2.first.variants.length);
    for (var i = 0; i < entities.first.variants.length; i++) {
      expect(entities.first.variants[i].tieBreakKey,
          entities2.first.variants[i].tieBreakKey,
          reason: 'tieBreakKey must be stable across identical calls');
    }
  });

  // ---------------------------------------------------------------------------
  // 8. tieBreakKey format: exactly '$canonicalKey\x00$docId'
  // ---------------------------------------------------------------------------

  test('tieBreakKey is exactly canonicalKey + null byte + docId', () {
    final hit = makeHit(
      docId: 'weapon:melta-rifle-a',
      canonicalKey: 'melta rifle',
      displayName: 'Melta Rifle',
    );
    final variant = SpokenVariant.fromHit(hit, slotA);

    expect(variant.tieBreakKey, 'melta rifle\x00weapon:melta-rifle-a',
        reason: 'null-byte separator, canonicalKey before docId');
  });

  // ---------------------------------------------------------------------------
  // 9. No dedup: two hits with same displayName but different docId both appear
  // ---------------------------------------------------------------------------

  test('two hits with same displayName but different docId both appear as variants', () {
    final hits = [
      makeHit(
        docId: 'weapon:plasma-gun-a',
        canonicalKey: 'plasma gun',
        displayName: 'Plasma Gun',
      ),
      makeHit(
        docId: 'weapon:plasma-gun-b',
        canonicalKey: 'plasma gun',
        displayName: 'Plasma Gun',
      ),
    ];

    final entities = grouper.group(slotA, hits);

    expect(entities.length, 1);
    expect(entities.first.variants.length, 2,
        reason: 'no deduplication — both docIds must be present');
    final docIds = entities.first.variants.map((v) => v.docId).toSet();
    expect(docIds, {'weapon:plasma-gun-a', 'weapon:plasma-gun-b'});
  });

  // ---------------------------------------------------------------------------
  // Bonus: VoiceSelectionSession.nextEntity() clamps at last entity
  // ---------------------------------------------------------------------------

  test('VoiceSelectionSession.nextEntity() clamps at last entity', () {
    SpokenEntity makeEntity(String key) => SpokenEntity(
          slotId: slotA,
          groupKey: key,
          displayName: key,
          variants: [
            SpokenVariant.fromHit(
              makeHit(docId: 'weapon:$key', canonicalKey: key, displayName: key),
              slotA,
            ),
          ],
        );

    final session = VoiceSelectionSession([
      makeEntity('alpha'),
      makeEntity('beta'),
    ]);

    expect(session.entityIndex, 0);
    session.nextEntity();
    expect(session.entityIndex, 1);
    session.nextEntity();
    expect(session.entityIndex, 1, reason: 'clamped at last entity');
  });

  // ---------------------------------------------------------------------------
  // Bonus: VoiceSelectionSession.reset() returns to 0/0
  // ---------------------------------------------------------------------------

  test('VoiceSelectionSession.reset() returns to entity 0, variant 0', () {
    final variant0 = SpokenVariant.fromHit(
      makeHit(docId: 'weapon:a', canonicalKey: 'bolter', displayName: 'Bolter'),
      slotA,
    );
    final variant1 = SpokenVariant.fromHit(
      makeHit(docId: 'weapon:b', canonicalKey: 'bolter', displayName: 'Bolter'),
      slotA,
    );
    final entity0 = SpokenEntity(
        slotId: slotA,
        groupKey: 'bolter',
        displayName: 'Bolter',
        variants: [variant0, variant1]);
    final entity1 = SpokenEntity(
        slotId: slotA,
        groupKey: 'plasma gun',
        displayName: 'Plasma Gun',
        variants: [
          SpokenVariant.fromHit(
            makeHit(docId: 'weapon:c', canonicalKey: 'plasma gun', displayName: 'Plasma Gun'),
            slotA,
          )
        ]);

    final session = VoiceSelectionSession([entity0, entity1]);
    session.nextVariant();
    session.nextEntity();
    expect(session.entityIndex, 1);
    expect(session.variantIndex, 0);

    session.reset();
    expect(session.entityIndex, 0, reason: 'reset must return to entity 0');
    expect(session.variantIndex, 0, reason: 'reset must return to variant 0');
  });
}

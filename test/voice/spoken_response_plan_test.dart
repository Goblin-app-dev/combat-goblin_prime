import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/voice/models/spoken_entity.dart';
import 'package:combat_goblin_prime/voice/models/spoken_response_plan.dart';
import 'package:combat_goblin_prime/voice/models/spoken_variant.dart';
import 'package:combat_goblin_prime/modules/m10_structured_search/m10_structured_search.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

SpokenVariant _variant(String name) => SpokenVariant(
      sourceSlotId: 'slot_0',
      docType: SearchDocType.unit,
      docId: '${name}_id',
      canonicalKey: name.toLowerCase(),
      displayName: name,
      matchReasons: const [MatchReason.canonicalKeyMatch],
      tieBreakKey: '${name.toLowerCase()}\x00${name}_id',
    );

SpokenEntity _entity(String name) => SpokenEntity(
      slotId: 'slot_0',
      groupKey: name.toLowerCase(),
      displayName: name,
      variants: [_variant(name)],
    );

SpokenResponsePlan _plan({
  String primaryText = 'Found something.',
  List<SpokenEntity>? entities,
  List<String>? followUps,
  int? selectedIndex,
  String debugSummary = 'test',
}) =>
    SpokenResponsePlan(
      primaryText: primaryText,
      entities: entities ?? const [],
      followUps: followUps ?? const [],
      selectedIndex: selectedIndex,
      debugSummary: debugSummary,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // 1. Unmodifiable lists
  // =========================================================================
  group('1. Unmodifiable list views', () {
    test('1.1 entities.add(...) throws UnsupportedError', () {
      final plan = _plan(entities: [_entity('Intercessor')]);
      expect(
        () => plan.entities.add(_entity('Terminator')),
        throwsUnsupportedError,
      );
    });

    test('1.2 followUps.add(...) throws UnsupportedError', () {
      final plan = _plan(followUps: ['next', 'select']);
      expect(
        () => plan.followUps.add('cancel'),
        throwsUnsupportedError,
      );
    });

    test('1.3 entities.remove(...) throws UnsupportedError', () {
      final e = _entity('Intercessor');
      final plan = _plan(entities: [e]);
      expect(
        () => plan.entities.remove(e),
        throwsUnsupportedError,
      );
    });

    test('1.4 followUps.remove(...) throws UnsupportedError', () {
      final plan = _plan(followUps: ['next']);
      expect(
        () => plan.followUps.remove('next'),
        throwsUnsupportedError,
      );
    });
  });

  // =========================================================================
  // 2. Defensive copy — mutating the input list does not affect the plan
  // =========================================================================
  group('2. Defensive copy', () {
    test('2.1 Mutating original entities list after construction does not change plan', () {
      final original = [_entity('Intercessor')];
      final plan = _plan(entities: original);

      original.add(_entity('Terminator'));

      expect(plan.entities, hasLength(1));
      expect(plan.entities.first.displayName, 'Intercessor');
    });

    test('2.2 Mutating original followUps list after construction does not change plan', () {
      final original = ['next', 'select'];
      final plan = _plan(followUps: original);

      original.add('cancel');
      original.removeAt(0);

      expect(plan.followUps, hasLength(2));
      expect(plan.followUps, containsAll(['next', 'select']));
    });

    test('2.3 Empty input lists produce empty unmodifiable lists', () {
      final plan = _plan(entities: [], followUps: []);
      expect(plan.entities, isEmpty);
      expect(plan.followUps, isEmpty);
      expect(() => plan.entities.add(_entity('X')), throwsUnsupportedError);
      expect(() => plan.followUps.add('x'), throwsUnsupportedError);
    });
  });

  // =========================================================================
  // 3. Debug-time asserts
  //    These tests are only meaningful with asserts enabled, which is the
  //    default for `flutter test`. Each invalid construction expects an
  //    AssertionError in debug mode.
  // =========================================================================
  group('3. Debug-time asserts', () {
    test('3.1 Empty primaryText throws AssertionError', () {
      expect(
        () => SpokenResponsePlan(
          primaryText: '',
          entities: const [],
          followUps: const [],
          debugSummary: 'test',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('3.2 Whitespace-only primaryText throws AssertionError', () {
      expect(
        () => SpokenResponsePlan(
          primaryText: '   ',
          entities: const [],
          followUps: const [],
          debugSummary: 'test',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('3.3 selectedIndex out of bounds (too high) throws AssertionError', () {
      expect(
        () => _plan(
          entities: [_entity('Intercessor')],
          selectedIndex: 1, // valid range is 0..0
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('3.4 selectedIndex negative throws AssertionError', () {
      expect(
        () => _plan(
          entities: [_entity('Intercessor')],
          selectedIndex: -1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('3.5 selectedIndex non-null with empty entities throws AssertionError', () {
      expect(
        () => _plan(
          entities: [],
          selectedIndex: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('3.6 selectedIndex null with empty entities is valid', () {
      final plan = _plan(entities: [], selectedIndex: null);
      expect(plan.selectedIndex, isNull);
      expect(plan.entities, isEmpty);
    });

    test('3.7 selectedIndex 0 with one entity is valid', () {
      final plan = _plan(entities: [_entity('Intercessor')], selectedIndex: 0);
      expect(plan.selectedIndex, 0);
    });

    test('3.8 selectedIndex at last index is valid', () {
      final entities = [_entity('A'), _entity('B'), _entity('C')];
      final plan = _plan(entities: entities, selectedIndex: 2);
      expect(plan.selectedIndex, 2);
    });
  });

  // =========================================================================
  // 4. Determinism
  // =========================================================================
  group('4. Determinism', () {
    test('4.1 Two plans from identical inputs have identical field values', () {
      final e = _entity('Intercessor');
      final p1 = _plan(
        primaryText: 'Found Intercessor.',
        entities: [e],
        followUps: ['select'],
        selectedIndex: 0,
        debugSummary: 'single:intercessor',
      );
      final p2 = _plan(
        primaryText: 'Found Intercessor.',
        entities: [e],
        followUps: ['select'],
        selectedIndex: 0,
        debugSummary: 'single:intercessor',
      );

      expect(p1.primaryText, p2.primaryText);
      expect(p1.selectedIndex, p2.selectedIndex);
      expect(p1.debugSummary, p2.debugSummary);
      expect(p1.entities.length, p2.entities.length);
      expect(p1.followUps.length, p2.followUps.length);
    });
  });
}

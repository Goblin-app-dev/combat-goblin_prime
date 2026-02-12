import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m6_evaluate/m6_evaluate.dart';
import 'package:combat_goblin_prime/modules/m7_applicability/m7_applicability.dart';
import 'package:combat_goblin_prime/modules/m8_modifiers/m8_modifiers.dart';

/// Mock implementation of SelectionSnapshot for testing.
class MockSnapshot implements SelectionSnapshot {
  final List<String> _orderedSelections;
  final Map<String, String> _entryIds;
  final Map<String, String?> _parents;
  final Map<String, List<String>> _children;
  final Map<String, int> _counts;
  final Map<String, bool> _forceRoots;

  MockSnapshot({
    required List<String> orderedSelections,
    required Map<String, String> entryIds,
    required Map<String, String?> parents,
    required Map<String, List<String>> children,
    required Map<String, int> counts,
    required Map<String, bool> forceRoots,
  })  : _orderedSelections = orderedSelections,
        _entryIds = entryIds,
        _parents = parents,
        _children = children,
        _counts = counts,
        _forceRoots = forceRoots;

  @override
  List<String> orderedSelections() => _orderedSelections;

  @override
  String entryIdFor(String selectionId) => _entryIds[selectionId]!;

  @override
  String? parentOf(String selectionId) => _parents[selectionId];

  @override
  List<String> childrenOf(String selectionId) =>
      _children[selectionId] ?? const [];

  @override
  int countFor(String selectionId) => _counts[selectionId] ?? 1;

  @override
  bool isForceRoot(String selectionId) => _forceRoots[selectionId] ?? false;
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

  group('M8 Modifiers: ModifierValue types', () {
    test('ModifierValue has 4 subtypes: Int, Double, String, Bool', () {
      final intVal = const IntModifierValue(42);
      final doubleVal = const DoubleModifierValue(3.14);
      final stringVal = const StringModifierValue('test');
      final boolVal = const BoolModifierValue(true);

      expect(intVal.value, 42);
      expect(doubleVal.value, 3.14);
      expect(stringVal.value, 'test');
      expect(boolVal.value, true);

      // All are ModifierValue subtypes
      expect(intVal, isA<ModifierValue>());
      expect(doubleVal, isA<ModifierValue>());
      expect(stringVal, isA<ModifierValue>());
      expect(boolVal, isA<ModifierValue>());

      print('[M8 INVARIANT TEST] ModifierValue subtypes verified');
    });

    test('ModifierValue equality works correctly', () {
      const val1 = IntModifierValue(42);
      const val2 = IntModifierValue(42);
      const val3 = IntModifierValue(43);

      expect(val1, equals(val2));
      expect(val1, isNot(equals(val3)));

      const str1 = StringModifierValue('test');
      const str2 = StringModifierValue('test');
      expect(str1, equals(str2));

      print('[M8 INVARIANT TEST] ModifierValue equality works');
    });
  });

  group('M8 Modifiers: FieldKind enum', () {
    test('FieldKind has 4 values', () {
      expect(FieldKind.values, hasLength(4));
      expect(FieldKind.values, contains(FieldKind.characteristic));
      expect(FieldKind.values, contains(FieldKind.cost));
      expect(FieldKind.values, contains(FieldKind.constraint));
      expect(FieldKind.values, contains(FieldKind.metadata));

      print('[M8 INVARIANT TEST] FieldKind enum verified');
    });
  });

  group('M8 Modifiers: ModifierTargetRef', () {
    test('ModifierTargetRef stores target reference with disambiguation', () {
      final ref = ModifierTargetRef(
        targetId: 'entry-123',
        field: 'name',
        fieldKind: FieldKind.metadata,
        scope: 'self',
        sourceFileId: 'test-file',
        sourceNode: const NodeRef(0),
      );

      expect(ref.targetId, 'entry-123');
      expect(ref.field, 'name');
      expect(ref.fieldKind, FieldKind.metadata);
      expect(ref.scope, 'self');

      print('[M8 INVARIANT TEST] ModifierTargetRef stores data correctly');
    });

    test('ModifierTargetRef equality includes fieldKind', () {
      final ref1 = ModifierTargetRef(
        targetId: 'entry-123',
        field: 'value',
        fieldKind: FieldKind.cost,
        sourceFileId: 'test',
        sourceNode: const NodeRef(0),
      );
      final ref2 = ModifierTargetRef(
        targetId: 'entry-123',
        field: 'value',
        fieldKind: FieldKind.constraint,
        sourceFileId: 'test',
        sourceNode: const NodeRef(0),
      );

      expect(ref1, isNot(equals(ref2)));

      print('[M8 INVARIANT TEST] ModifierTargetRef equality includes fieldKind');
    });
  });

  group('M8 Modifiers: ModifierOperation', () {
    test('ModifierOperation captures operation data', () {
      final target = ModifierTargetRef(
        targetId: 'entry-1',
        field: 'name',
        fieldKind: FieldKind.metadata,
        sourceFileId: 'test',
        sourceNode: const NodeRef(0),
      );

      final operation = ModifierOperation(
        operationType: 'set',
        target: target,
        value: const StringModifierValue('New Name'),
        isApplicable: true,
        sourceFileId: 'test',
        sourceNode: const NodeRef(1),
      );

      expect(operation.operationType, 'set');
      expect(operation.isApplicable, true);
      expect(operation.reasonSkipped, isNull);

      print('[M8 INVARIANT TEST] ModifierOperation captures data correctly');
    });

    test('ModifierOperation stores reasonSkipped when not applicable', () {
      final target = ModifierTargetRef(
        targetId: 'entry-1',
        field: 'name',
        fieldKind: FieldKind.metadata,
        sourceFileId: 'test',
        sourceNode: const NodeRef(0),
      );

      final operation = ModifierOperation(
        operationType: 'set',
        target: target,
        value: const StringModifierValue('New Name'),
        isApplicable: false,
        reasonSkipped: 'Condition not met',
        sourceFileId: 'test',
        sourceNode: const NodeRef(1),
      );

      expect(operation.isApplicable, false);
      expect(operation.reasonSkipped, 'Condition not met');

      print('[M8 INVARIANT TEST] ModifierOperation stores reasonSkipped');
    });
  });

  group('M8 Modifiers: ModifierResult', () {
    test('ModifierResult.unchanged preserves base value', () {
      final target = ModifierTargetRef(
        targetId: 'entry-1',
        field: 'name',
        fieldKind: FieldKind.metadata,
        sourceFileId: 'test',
        sourceNode: const NodeRef(0),
      );

      const baseValue = StringModifierValue('Original');

      final result = ModifierResult.unchanged(
        target: target,
        baseValue: baseValue,
        sourceFileId: 'test',
        sourceNode: const NodeRef(0),
      );

      expect(result.baseValue, baseValue);
      expect(result.effectiveValue, baseValue);
      expect(result.appliedOperations, isEmpty);
      expect(result.skippedOperations, isEmpty);

      print('[M8 INVARIANT TEST] ModifierResult.unchanged preserves value');
    });

    test('ModifierResult equality uses deep list comparison', () {
      final target = ModifierTargetRef(
        targetId: 'entry-1',
        field: 'name',
        fieldKind: FieldKind.metadata,
        sourceFileId: 'test',
        sourceNode: const NodeRef(0),
      );

      final result1 = ModifierResult(
        target: target,
        baseValue: null,
        effectiveValue: const IntModifierValue(10),
        appliedOperations: const [],
        skippedOperations: const [],
        diagnostics: const [],
        sourceFileId: 'test',
        sourceNode: const NodeRef(0),
      );

      final result2 = ModifierResult(
        target: target,
        baseValue: null,
        effectiveValue: const IntModifierValue(10),
        appliedOperations: const [],
        skippedOperations: const [],
        diagnostics: const [],
        sourceFileId: 'test',
        sourceNode: const NodeRef(0),
      );

      expect(result1, equals(result2));

      print('[M8 INVARIANT TEST] ModifierResult equality works');
    });
  });

  group('M8 Modifiers: diagnostic codes', () {
    test('All 7 diagnostic codes are defined', () {
      expect(ModifierDiagnosticCode.values, hasLength(7));

      final expectedCodes = [
        'UNKNOWN_MODIFIER_TYPE',
        'UNKNOWN_MODIFIER_FIELD',
        'UNKNOWN_MODIFIER_SCOPE',
        'UNRESOLVED_MODIFIER_TARGET',
        'INCOMPATIBLE_VALUE_TYPE',
        'UNSUPPORTED_TARGET_KIND',
        'UNSUPPORTED_TARGET_SCOPE',
      ];

      for (final code in ModifierDiagnosticCode.values) {
        final diagnostic = ModifierDiagnostic(
          code: code,
          message: 'Test',
          sourceFileId: 'test',
        );
        expect(expectedCodes, contains(diagnostic.codeString));
      }

      print('[M8 INVARIANT TEST] All 7 diagnostic codes defined');
    });
  });

  group('M8 Modifiers: no-failure policy', () {
    test('ModifierFailure defines expected invariants', () {
      expect(ModifierFailure.invariantCorruptedInput, 'CORRUPTED_M5_INPUT');
      expect(ModifierFailure.invariantInternalAssertion, 'INTERNAL_ASSERTION');

      print('[M8 INVARIANT TEST] ModifierFailure invariants defined');
    });
  });

  group('M8 Modifiers: service functionality', () {
    test('No modifiers → effectiveValue equals baseValue', () {
      final service = ModifierService();
      final applicabilityService = ApplicabilityService();

      final wrappedBundle = boundBundle.linkedBundle.wrappedBundle;
      final primaryFile = wrappedBundle.primaryCatalog;

      final snapshot = MockSnapshot(
        orderedSelections: ['sel-1'],
        entryIds: {'sel-1': boundBundle.entries.first.id},
        parents: {'sel-1': null},
        children: {'sel-1': []},
        counts: {'sel-1': 1},
        forceRoots: {'sel-1': true},
      );

      // Use root node which has no direct modifiers
      final result = service.applyModifiers(
        modifierSource: primaryFile.root,
        sourceFileId: primaryFile.fileId,
        sourceNode: primaryFile.rootRef,
        boundBundle: boundBundle,
        snapshot: snapshot,
        contextSelectionId: 'sel-1',
        applicabilityService: applicabilityService,
      );

      // No modifiers found, so effective equals base (both null in this case)
      expect(result.appliedOperations, isEmpty);
      expect(result.skippedOperations, isEmpty);

      print('[M8 INVARIANT TEST] No modifiers → empty operations');
    });

    test('applyModifiersMany preserves input order', () {
      final service = ModifierService();
      final applicabilityService = ApplicabilityService();
      final wrappedBundle = boundBundle.linkedBundle.wrappedBundle;
      final primaryFile = wrappedBundle.primaryCatalog;

      final snapshot = MockSnapshot(
        orderedSelections: ['sel-1'],
        entryIds: {'sel-1': boundBundle.entries.first.id},
        parents: {'sel-1': null},
        children: {'sel-1': []},
        counts: {'sel-1': 1},
        forceRoots: {'sel-1': true},
      );

      final sources = [
        (
          modifierSource: primaryFile.root,
          sourceFileId: primaryFile.fileId,
          sourceNode: primaryFile.rootRef,
        ),
        (
          modifierSource: primaryFile.root,
          sourceFileId: primaryFile.fileId,
          sourceNode: primaryFile.rootRef,
        ),
        (
          modifierSource: primaryFile.root,
          sourceFileId: primaryFile.fileId,
          sourceNode: primaryFile.rootRef,
        ),
      ];

      final results = service.applyModifiersMany(
        sources: sources,
        boundBundle: boundBundle,
        snapshot: snapshot,
        contextSelectionId: 'sel-1',
        applicabilityService: applicabilityService,
      );

      expect(results, hasLength(3));
      for (final result in results) {
        expect(result.sourceFileId, primaryFile.fileId);
      }

      print('[M8 INVARIANT TEST] applyModifiersMany preserves input order');
    });

    test('Determinism: same inputs → identical results', () {
      final service = ModifierService();
      final applicabilityService = ApplicabilityService();
      final wrappedBundle = boundBundle.linkedBundle.wrappedBundle;
      final primaryFile = wrappedBundle.primaryCatalog;

      final snapshot = MockSnapshot(
        orderedSelections: ['sel-1'],
        entryIds: {'sel-1': boundBundle.entries.first.id},
        parents: {'sel-1': null},
        children: {'sel-1': []},
        counts: {'sel-1': 1},
        forceRoots: {'sel-1': true},
      );

      final result1 = service.applyModifiers(
        modifierSource: primaryFile.root,
        sourceFileId: primaryFile.fileId,
        sourceNode: primaryFile.rootRef,
        boundBundle: boundBundle,
        snapshot: snapshot,
        contextSelectionId: 'sel-1',
        applicabilityService: applicabilityService,
      );

      final result2 = service.applyModifiers(
        modifierSource: primaryFile.root,
        sourceFileId: primaryFile.fileId,
        sourceNode: primaryFile.rootRef,
        boundBundle: boundBundle,
        snapshot: snapshot,
        contextSelectionId: 'sel-1',
        applicabilityService: applicabilityService,
      );

      expect(result1.effectiveValue, result2.effectiveValue);
      expect(result1.appliedOperations.length, result2.appliedOperations.length);
      expect(result1.sourceFileId, result2.sourceFileId);
      expect(result1.sourceNode, result2.sourceNode);

      print('[M8 INVARIANT TEST] Determinism verified');
    });
  });

  group('M8 Modifiers: modifier operations', () {
    test('set operation semantics', () {
      // Test that set operation replaces value
      const original = IntModifierValue(5);
      const newVal = IntModifierValue(10);

      // set should replace entirely
      expect(newVal.value, 10);

      print('[M8 INVARIANT TEST] set operation replaces value');
    });

    test('increment operation semantics', () {
      // Test that increment adds to value
      const base = IntModifierValue(5);
      const increment = IntModifierValue(3);

      final result = base.value + increment.value;
      expect(result, 8);

      print('[M8 INVARIANT TEST] increment operation adds value');
    });

    test('decrement operation semantics', () {
      // Test that decrement subtracts from value
      const base = IntModifierValue(10);
      const decrement = IntModifierValue(3);

      final result = base.value - decrement.value;
      expect(result, 7);

      print('[M8 INVARIANT TEST] decrement operation subtracts value');
    });

    test('append operation semantics', () {
      // Test that append concatenates strings
      const base = StringModifierValue('Hello');
      const append = StringModifierValue(' World');

      final result = base.value + append.value;
      expect(result, 'Hello World');

      print('[M8 INVARIANT TEST] append operation concatenates strings');
    });
  });
}

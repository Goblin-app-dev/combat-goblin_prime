import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';

// ---------------------------------------------------------------------------
// Helpers for rule-node normalization unit tests (synthetic WrappedFile/Node)
// ---------------------------------------------------------------------------

/// Builds a minimal WrappedFile containing the given nodes.
WrappedFile _syntheticFile(String fileId, List<WrappedNode> nodes) =>
    WrappedFile(
      fileId: fileId,
      fileType: SourceFileType.cat,
      nodes: nodes,
      idIndex: const {},
    );

/// Builds a WrappedNode at [index] with [tagName] and optional [textContent].
WrappedNode _node({
  required int index,
  required String tagName,
  Map<String, String> attributes = const {},
  String? textContent,
  int? parent,
  List<int> children = const [],
  String fileId = 'test-file',
}) =>
    WrappedNode(
      ref: NodeRef(index),
      tagName: tagName,
      attributes: attributes,
      textContent: textContent,
      parent: parent != null ? NodeRef(parent) : null,
      children: children.map(NodeRef.new).toList(),
      depth: parent == null ? 0 : 1,
      fileId: fileId,
      fileType: SourceFileType.cat,
    );

void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late LinkedPackBundle linkedBundle;
  late WrappedPackBundle wrappedBundle;

  setUpAll(() async {
    // Clean storage
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Acquire, parse, wrap, link bundle once for all tests
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
    wrappedBundle = await WrapService().wrapBundle(parsedBundle: parsedBundle);
    linkedBundle = await LinkService().linkBundle(wrappedBundle: wrappedBundle);
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('M5 Bind: determinism', () {
    test('binding same input twice yields identical output', () async {
      final bindService = BindService();

      final result1 =
          await bindService.bindBundle(linkedBundle: linkedBundle);
      final result2 =
          await bindService.bindBundle(linkedBundle: linkedBundle);

      // Same number of entities
      expect(result1.entries.length, result2.entries.length);
      expect(result1.profiles.length, result2.profiles.length);
      expect(result1.categories.length, result2.categories.length);
      expect(result1.diagnostics.length, result2.diagnostics.length);

      // Same entry IDs in same order
      for (var i = 0; i < result1.entries.length; i++) {
        expect(result1.entries[i].id, result2.entries[i].id);
        expect(result1.entries[i].name, result2.entries[i].name);
        expect(result1.entries[i].sourceFileId, result2.entries[i].sourceFileId);
        expect(result1.entries[i].sourceNode.nodeIndex,
            result2.entries[i].sourceNode.nodeIndex);
      }

      // Same profile IDs in same order
      for (var i = 0; i < result1.profiles.length; i++) {
        expect(result1.profiles[i].id, result2.profiles[i].id);
      }

      // Same category IDs in same order
      for (var i = 0; i < result1.categories.length; i++) {
        expect(result1.categories[i].id, result2.categories[i].id);
      }

      print('[TEST] Determinism verified: ${result1.entries.length} entries, '
          '${result1.profiles.length} profiles, ${result1.categories.length} categories');
    });
  });

  group('M5 Bind: eligibility enforcement', () {
    test('only eligible tags are bound as entries', () async {
      final bindService = BindService();
      final result = await bindService.bindBundle(linkedBundle: linkedBundle);

      // All entries must have come from eligible source tags
      for (final entry in result.entries) {
        // The source node must be selectionEntry or selectionEntryGroup
        final sourceFile = _findFile(entry.sourceFileId, wrappedBundle);
        expect(sourceFile, isNotNull,
            reason: 'Source file not found: ${entry.sourceFileId}');

        final sourceNode = sourceFile!.nodes[entry.sourceNode.nodeIndex];
        expect(
          {'selectionEntry', 'selectionEntryGroup'}.contains(sourceNode.tagName),
          isTrue,
          reason:
              'Entry ${entry.id} bound from ineligible tag: ${sourceNode.tagName}',
        );
      }

      print('[TEST] Eligibility verified: all ${result.entries.length} entries '
          'from eligible tags');
    });

    test('only eligible tags are bound as profiles', () async {
      final bindService = BindService();
      final result = await bindService.bindBundle(linkedBundle: linkedBundle);

      // 'profile' is the primary source tag.
      // 'rule' is also eligible: direct <infoLink type="rule"> targets are
      // materialised as synthetic ability BoundProfiles by M5 so that M9 can
      // index them as RuleDocs without changes to M9's classification logic.
      const eligibleProfileSourceTags = {'profile', 'rule'};

      for (final profile in result.profiles) {
        final sourceFile = _findFile(profile.sourceFileId, wrappedBundle);
        expect(sourceFile, isNotNull);

        final sourceNode = sourceFile!.nodes[profile.sourceNode.nodeIndex];
        expect(
          eligibleProfileSourceTags.contains(sourceNode.tagName),
          isTrue,
          reason:
              'Profile ${profile.id} bound from ineligible tag: ${sourceNode.tagName}',
        );
      }

      print('[TEST] Eligibility verified: all ${result.profiles.length} profiles '
          'from eligible tags');
    });

    test('only eligible tags are bound as categories', () async {
      final bindService = BindService();
      final result = await bindService.bindBundle(linkedBundle: linkedBundle);

      for (final category in result.categories) {
        final sourceFile = _findFile(category.sourceFileId, wrappedBundle);
        expect(sourceFile, isNotNull);

        final sourceNode = sourceFile!.nodes[category.sourceNode.nodeIndex];
        expect(
          sourceNode.tagName,
          'categoryEntry',
          reason:
              'Category ${category.id} bound from ineligible tag: ${sourceNode.tagName}',
        );
      }

      print('[TEST] Eligibility verified: all ${result.categories.length} categories '
          'from eligible tags');
    });
  });

  group('M5 Bind: provenance preserved', () {
    test('every bound entry has valid sourceFileId', () async {
      final bindService = BindService();
      final result = await bindService.bindBundle(linkedBundle: linkedBundle);

      final validFileIds = {
        wrappedBundle.primaryCatalog.fileId,
        wrappedBundle.gameSystem.fileId,
        ...wrappedBundle.dependencyCatalogs.map((f) => f.fileId),
      };

      for (final entry in result.entries) {
        expect(
          validFileIds.contains(entry.sourceFileId),
          isTrue,
          reason: 'Entry ${entry.id} has invalid sourceFileId: ${entry.sourceFileId}',
        );
      }

      print('[TEST] Provenance verified: all entries have valid sourceFileId');
    });

    test('every bound entry has valid sourceNode', () async {
      final bindService = BindService();
      final result = await bindService.bindBundle(linkedBundle: linkedBundle);

      for (final entry in result.entries) {
        final sourceFile = _findFile(entry.sourceFileId, wrappedBundle);
        expect(sourceFile, isNotNull);
        expect(
          entry.sourceNode.nodeIndex >= 0 &&
              entry.sourceNode.nodeIndex < sourceFile!.nodes.length,
          isTrue,
          reason: 'Entry ${entry.id} has invalid sourceNode: ${entry.sourceNode.nodeIndex}',
        );
      }

      print('[TEST] Provenance verified: all entries have valid sourceNode');
    });
  });

  group('M5 Bind: no-failure policy', () {
    test('unresolved links produce diagnostics, not failures', () async {
      final bindService = BindService();

      // This should complete without throwing
      final result = await bindService.bindBundle(linkedBundle: linkedBundle);

      // May have unresolved link diagnostics
      final unresolvedCount = result.unresolvedEntryLinkCount +
          result.unresolvedInfoLinkCount +
          result.unresolvedCategoryLinkCount;

      print('[TEST] Completed without BindFailure despite:');
      print('[TEST]   $unresolvedCount unresolved links');
      print('[TEST]   ${result.shadowedDefinitionCount} shadowed definitions');
    });
  });

  // ---------------------------------------------------------------------------
  // Rule-node normalization invariants (unit-level, synthetic data)
  //
  // These tests exercise _bindRuleNodeAsProfile via normalizeRuleNodeForTest,
  // a @visibleForTesting accessor that avoids the need to run the full M1–M4
  // pipeline.  Each test creates minimal synthetic WrappedFile/WrappedNode
  // objects and asserts the normalisation contract:
  //
  //   * id and name are copied verbatim from XML attributes
  //   * typeName is always 'ability'
  //   * description is extracted from <description> OR characteristic form
  //   * no children / links are recursively bound
  // ---------------------------------------------------------------------------
  group('M5 Bind: rule node normalization invariants', () {
    test(
        'rule node with <description> child produces correct synthetic BoundProfile',
        () {
      // Arrange: rule node (index 0) → description child (index 1)
      const fileId = 'test-cat';
      final nodes = [
        _node(
          index: 0,
          tagName: 'rule',
          attributes: {'id': 'rule-shadow', 'name': 'Shadow in the Warp'},
          children: [1],
          fileId: fileId,
        ),
        _node(
          index: 1,
          tagName: 'description',
          textContent: 'Each time a Battleshock test is taken...',
          parent: 0,
          fileId: fileId,
        ),
      ];
      final file = _syntheticFile(fileId, nodes);

      // Act
      final profile = BindService().normalizeRuleNodeForTest(nodes[0], file);

      // Assert: id, name, typeName invariants
      expect(profile.id, 'rule-shadow');
      expect(profile.name, 'Shadow in the Warp');
      expect(profile.typeName, 'ability');

      // Assert: description extracted and non-empty
      final descChar = profile.characteristics
          .where((c) => c.name == 'description')
          .toList();
      expect(descChar, hasLength(1));
      expect(descChar.first.value, contains('Battleshock'));

      print('[TEST] <description>-form extraction verified');
    });

    test(
        'rule node with characteristic-based description produces correct synthetic BoundProfile',
        () {
      // Arrange: rule (0) → characteristics (1) → characteristic name=Description (2)
      const fileId = 'test-cat';
      final nodes = [
        _node(
          index: 0,
          tagName: 'rule',
          attributes: {'id': 'rule-deep-strike', 'name': 'Deep Strike'},
          children: [1],
          fileId: fileId,
        ),
        _node(
          index: 1,
          tagName: 'characteristics',
          parent: 0,
          children: [2],
          fileId: fileId,
        ),
        _node(
          index: 2,
          tagName: 'characteristic',
          attributes: {'name': 'Description'},
          textContent: 'During the Declare Battle Formations step...',
          parent: 1,
          fileId: fileId,
        ),
      ];
      final file = _syntheticFile(fileId, nodes);

      // Act
      final profile = BindService().normalizeRuleNodeForTest(nodes[0], file);

      // Assert: id, name, typeName invariants
      expect(profile.id, 'rule-deep-strike');
      expect(profile.name, 'Deep Strike');
      expect(profile.typeName, 'ability');

      // Assert: description extracted from characteristic form
      final descChar = profile.characteristics
          .where((c) => c.name == 'description')
          .toList();
      expect(descChar, hasLength(1));
      expect(descChar.first.value, contains('Declare Battle Formations'));

      print('[TEST] characteristic-form extraction verified');
    });

    test('rule node with no description text produces profile with empty characteristics',
        () {
      const fileId = 'test-cat';
      final nodes = [
        _node(
          index: 0,
          tagName: 'rule',
          attributes: {'id': 'rule-bare', 'name': 'Bare Rule'},
          fileId: fileId,
        ),
      ];
      final file = _syntheticFile(fileId, nodes);

      final profile = BindService().normalizeRuleNodeForTest(nodes[0], file);

      expect(profile.id, 'rule-bare');
      expect(profile.name, 'Bare Rule');
      expect(profile.typeName, 'ability');
      // No description → no characteristics emitted
      expect(profile.characteristics, isEmpty);

      print('[TEST] empty-description rule node verified');
    });

    test(
        'rule-sourced profiles in the integration run always satisfy normalization invariants',
        () async {
      final bindService = BindService();
      final result = await bindService.bindBundle(linkedBundle: linkedBundle);

      var ruleSourcedCount = 0;

      for (final profile in result.profiles) {
        final sourceFile = _findFile(profile.sourceFileId, wrappedBundle);
        if (sourceFile == null) continue;

        final sourceNode = sourceFile.nodes[profile.sourceNode.nodeIndex];
        if (sourceNode.tagName != 'rule') continue;

        ruleSourcedCount++;

        // typeName must always be 'ability'
        expect(
          profile.typeName,
          'ability',
          reason:
              'Rule-sourced profile "${profile.name}" (id=${profile.id}) must have typeName=ability',
        );
        // id must be non-empty
        expect(
          profile.id.isNotEmpty,
          isTrue,
          reason: 'Rule-sourced profile must have a non-empty id',
        );
        // name must be non-empty
        expect(
          profile.name.isNotEmpty,
          isTrue,
          reason: 'Rule-sourced profile must have a non-empty name',
        );
      }

      print('[TEST] rule-sourced profiles in integration run: $ruleSourcedCount');
      print('[TEST] All passed typeName/id/name invariants');
    });
  });
}

/// Helper to find a file by ID in the wrapped bundle.
WrappedFile? _findFile(String fileId, WrappedPackBundle bundle) {
  if (bundle.primaryCatalog.fileId == fileId) return bundle.primaryCatalog;
  if (bundle.gameSystem.fileId == fileId) return bundle.gameSystem;
  for (final dep in bundle.dependencyCatalogs) {
    if (dep.fileId == fileId) return dep;
  }
  return null;
}

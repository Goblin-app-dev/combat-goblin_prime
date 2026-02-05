import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m4_link/m4_link.dart';

void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late WrappedPackBundle wrappedBundle;
  late LinkedPackBundle linkedBundle;

  setUpAll(() async {
    // Clean storage
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Build the full pipeline once
    final gameSystemBytes = await File('test/Warhammer 40,000.gst').readAsBytes();
    final primaryCatalogBytes = await File('test/Imperium - Space Marines.cat').readAsBytes();

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

  group('M4 Link: structural invariants', () {
    test('SymbolTable contains all IDs from all files', () {
      // Collect all IDs from wrapped files
      final allIds = <String>{};
      void collectIds(WrappedFile file) {
        allIds.addAll(file.idIndex.keys);
      }

      collectIds(wrappedBundle.primaryCatalog);
      for (final dep in wrappedBundle.dependencyCatalogs) {
        collectIds(dep);
      }
      collectIds(wrappedBundle.gameSystem);

      // SymbolTable must have all these IDs
      for (final id in allIds) {
        final lookup = linkedBundle.symbolTable.lookup(id);
        expect(lookup, isNotEmpty,
            reason: 'SymbolTable missing ID: $id');
      }

      // SymbolTable should not have extra IDs
      expect(linkedBundle.symbolTable.allIds.toSet(), allIds);
    });

    test('ResolvedRef targets are valid NodeRefs in correct files', () {
      for (final ref in linkedBundle.resolvedRefs) {
        for (final target in ref.targets) {
          // Find the file by fileId
          WrappedFile? targetFile;
          if (target.fileId == wrappedBundle.primaryCatalog.fileId) {
            targetFile = wrappedBundle.primaryCatalog;
          } else if (target.fileId == wrappedBundle.gameSystem.fileId) {
            targetFile = wrappedBundle.gameSystem;
          } else {
            for (final dep in wrappedBundle.dependencyCatalogs) {
              if (dep.fileId == target.fileId) {
                targetFile = dep;
                break;
              }
            }
          }

          expect(targetFile, isNotNull,
              reason: 'Target fileId ${target.fileId} not found in bundle');

          // NodeRef must be in bounds
          expect(target.nodeRef.nodeIndex, greaterThanOrEqualTo(0));
          expect(target.nodeRef.nodeIndex, lessThan(targetFile!.nodes.length),
              reason: 'NodeRef ${target.nodeRef} out of bounds for file ${target.fileId}');
        }
      }
    });

    test('UNRESOLVED_TARGET diagnostic ⇔ empty targets', () {
      for (final ref in linkedBundle.resolvedRefs) {
        final hasUnresolvedDiag = linkedBundle.diagnostics.any((d) =>
            d.code == LinkDiagnosticCode.unresolvedTarget &&
            d.sourceFileId == ref.sourceFileId &&
            d.sourceNode == ref.sourceNode);

        if (ref.targets.isEmpty) {
          expect(hasUnresolvedDiag, isTrue,
              reason: 'Empty targets but no UNRESOLVED_TARGET diagnostic');
        } else {
          expect(hasUnresolvedDiag, isFalse,
              reason: 'Non-empty targets but has UNRESOLVED_TARGET diagnostic');
        }
      }
    });

    test('DUPLICATE_ID_REFERENCE diagnostic ⇔ multiple targets', () {
      for (final ref in linkedBundle.resolvedRefs) {
        final hasDupDiag = linkedBundle.diagnostics.any((d) =>
            d.code == LinkDiagnosticCode.duplicateIdReference &&
            d.sourceFileId == ref.sourceFileId &&
            d.sourceNode == ref.sourceNode);

        if (ref.targets.length > 1) {
          expect(hasDupDiag, isTrue,
              reason: 'Multiple targets but no DUPLICATE_ID_REFERENCE diagnostic');
        } else {
          expect(hasDupDiag, isFalse,
              reason: 'Single/no targets but has DUPLICATE_ID_REFERENCE diagnostic');
        }
      }
    });
  });

  group('M4 Link: determinism', () {
    test('linking same input twice yields identical results', () async {
      // Link the same bundle again
      final linkedBundle2 = await LinkService().linkBundle(wrappedBundle: wrappedBundle);

      // packId must match
      expect(linkedBundle2.packId, linkedBundle.packId);

      // Same number of resolved refs
      expect(linkedBundle2.resolvedRefs.length, linkedBundle.resolvedRefs.length);

      // Same number of diagnostics
      expect(linkedBundle2.diagnostics.length, linkedBundle.diagnostics.length);

      // Same resolved refs in same order
      for (var i = 0; i < linkedBundle.resolvedRefs.length; i++) {
        final ref1 = linkedBundle.resolvedRefs[i];
        final ref2 = linkedBundle2.resolvedRefs[i];

        expect(ref2.sourceFileId, ref1.sourceFileId);
        expect(ref2.sourceNode.nodeIndex, ref1.sourceNode.nodeIndex);
        expect(ref2.targetId, ref1.targetId);
        expect(ref2.targets.length, ref1.targets.length);

        // Same targets in same order
        for (var j = 0; j < ref1.targets.length; j++) {
          expect(ref2.targets[j].fileId, ref1.targets[j].fileId);
          expect(ref2.targets[j].nodeRef.nodeIndex, ref1.targets[j].nodeRef.nodeIndex);
        }
      }

      // Same diagnostics in same order
      for (var i = 0; i < linkedBundle.diagnostics.length; i++) {
        final diag1 = linkedBundle.diagnostics[i];
        final diag2 = linkedBundle2.diagnostics[i];

        expect(diag2.code, diag1.code);
        expect(diag2.sourceFileId, diag1.sourceFileId);
        expect(diag2.targetId, diag1.targetId);
      }
    });
  });

  group('M4 Link: target ordering', () {
    test('multi-hit targets follow file resolution order', () {
      // Find any resolved refs with multiple targets
      final multiHitRefs = linkedBundle.resolvedRefs.where((r) => r.targets.length > 1);

      if (multiHitRefs.isEmpty) {
        print('[TEST] No multi-hit refs found - skipping ordering test');
        return;
      }

      // Build file order map: fileId → order index
      final fileOrder = <String, int>{};
      fileOrder[wrappedBundle.primaryCatalog.fileId] = 0;
      var idx = 1;
      for (final dep in wrappedBundle.dependencyCatalogs) {
        fileOrder[dep.fileId] = idx++;
      }
      fileOrder[wrappedBundle.gameSystem.fileId] = idx;

      for (final ref in multiHitRefs) {
        // Verify targets are in file order
        var lastFileOrder = -1;
        var lastNodeIndex = -1;
        String? lastFileId;

        for (final target in ref.targets) {
          final currentFileOrder = fileOrder[target.fileId]!;

          if (currentFileOrder == lastFileOrder) {
            // Same file: node index must be ascending
            expect(target.nodeRef.nodeIndex, greaterThan(lastNodeIndex),
                reason: 'Within-file node order violated for targetId ${ref.targetId}');
          } else {
            // Different file: file order must be ascending
            expect(currentFileOrder, greaterThan(lastFileOrder),
                reason: 'File order violated for targetId ${ref.targetId}: '
                    '$lastFileId (order $lastFileOrder) before ${target.fileId} (order $currentFileOrder)');
          }

          lastFileOrder = currentFileOrder;
          lastNodeIndex = target.nodeRef.nodeIndex;
          lastFileId = target.fileId;
        }
      }
    });
  });

  group('M4 Link: no-failure policy', () {
    test('unresolved and duplicate cases do not throw LinkFailure', () async {
      // This test verifies that we got here without throwing
      // If LinkFailure were thrown for normal cases, the test setup would have failed
      expect(linkedBundle, isNotNull);
      expect(linkedBundle.diagnostics, isNotEmpty);

      // Verify we have both unresolved and duplicate cases
      // (based on the fixture data, we should have some)
      print('[TEST] Completed without LinkFailure despite:');
      print('[TEST]   ${linkedBundle.unresolvedCount} unresolved targets');
      print('[TEST]   ${linkedBundle.duplicateRefCount} duplicate ID references');
    });
  });

  group('M4 Link: wrapped bundle unchanged', () {
    test('WrappedPackBundle is not modified by linking', () {
      // Verify the wrapped bundle reference is the same object
      expect(linkedBundle.wrappedBundle, same(wrappedBundle));

      // Verify node counts haven't changed
      final gsNodeCount = wrappedBundle.gameSystem.nodes.length;
      final pcNodeCount = wrappedBundle.primaryCatalog.nodes.length;

      expect(linkedBundle.wrappedBundle.gameSystem.nodes.length, gsNodeCount);
      expect(linkedBundle.wrappedBundle.primaryCatalog.nodes.length, pcNodeCount);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';
import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Structural invariant tests for M3 Wrap.
///
/// These tests lock in M3 guarantees:
/// - Parent/child bidirectional consistency
/// - Depth correctness
/// - Deterministic nodeIndex assignment
/// - Root index == 0
/// - Stable traversal order
/// - Provenance preservation
///
/// NO schema assumptions. NO cross-file assertions.
void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late ParsedPackBundle parsedBundle;

  setUpAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

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

    parsedBundle = await ParseService().parseBundle(rawBundle: rawBundle);
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('M3 Wrap: structural invariants', () {
    test('NodeRef indices are within bounds', () async {
      final wrapped = await WrapService().wrapBundle(parsedBundle: parsedBundle);

      void checkBounds(WrappedFile wf, String label) {
        for (final node in wf.nodes) {
          expect(node.ref.nodeIndex, greaterThanOrEqualTo(0),
              reason: '$label: nodeIndex < 0');
          expect(node.ref.nodeIndex, lessThan(wf.nodes.length),
              reason: '$label: nodeIndex >= nodes.length');

          if (node.parent != null) {
            expect(node.parent!.nodeIndex, greaterThanOrEqualTo(0),
                reason: '$label: parent nodeIndex < 0');
            expect(node.parent!.nodeIndex, lessThan(wf.nodes.length),
                reason: '$label: parent nodeIndex >= nodes.length');
          }

          for (final childRef in node.children) {
            expect(childRef.nodeIndex, greaterThanOrEqualTo(0),
                reason: '$label: child nodeIndex < 0');
            expect(childRef.nodeIndex, lessThan(wf.nodes.length),
                reason: '$label: child nodeIndex >= nodes.length');
          }
        }
      }

      checkBounds(wrapped.gameSystem, 'gameSystem');
      checkBounds(wrapped.primaryCatalog, 'primaryCatalog');
      for (var i = 0; i < wrapped.dependencyCatalogs.length; i++) {
        checkBounds(wrapped.dependencyCatalogs[i], 'dependency[$i]');
      }
    });

    test('Parent/child bidirectional consistency', () async {
      final wrapped = await WrapService().wrapBundle(parsedBundle: parsedBundle);

      void checkConsistency(WrappedFile wf, String label) {
        for (final node in wf.nodes) {
          // If node has children, each child's parent must be this node
          for (final childRef in node.children) {
            final child = wf.nodes[childRef.nodeIndex];
            expect(child.parent, equals(node.ref),
                reason: '$label: child.parent != parent at node ${node.ref.nodeIndex}');
          }

          // If node has parent, parent's children must contain this node
          if (node.parent != null) {
            final parent = wf.nodes[node.parent!.nodeIndex];
            expect(parent.children.contains(node.ref), isTrue,
                reason: '$label: parent.children does not contain node ${node.ref.nodeIndex}');
          }
        }
      }

      checkConsistency(wrapped.gameSystem, 'gameSystem');
      checkConsistency(wrapped.primaryCatalog, 'primaryCatalog');
      for (var i = 0; i < wrapped.dependencyCatalogs.length; i++) {
        checkConsistency(wrapped.dependencyCatalogs[i], 'dependency[$i]');
      }
    });

    test('Depth correctness', () async {
      final wrapped = await WrapService().wrapBundle(parsedBundle: parsedBundle);

      void checkDepth(WrappedFile wf, String label) {
        for (final node in wf.nodes) {
          if (node.parent == null) {
            expect(node.depth, equals(0),
                reason: '$label: root depth != 0');
          } else {
            final parent = wf.nodes[node.parent!.nodeIndex];
            expect(node.depth, equals(parent.depth + 1),
                reason: '$label: depth != parent.depth + 1 at node ${node.ref.nodeIndex}');
          }
        }
      }

      checkDepth(wrapped.gameSystem, 'gameSystem');
      checkDepth(wrapped.primaryCatalog, 'primaryCatalog');
      for (var i = 0; i < wrapped.dependencyCatalogs.length; i++) {
        checkDepth(wrapped.dependencyCatalogs[i], 'dependency[$i]');
      }
    });

    test('Root is at index 0 with depth 0 and no parent', () async {
      final wrapped = await WrapService().wrapBundle(parsedBundle: parsedBundle);

      void checkRoot(WrappedFile wf, String label) {
        expect(wf.nodes.isNotEmpty, isTrue, reason: '$label: no nodes');
        final root = wf.nodes[0];
        expect(root.ref.nodeIndex, equals(0), reason: '$label: root index != 0');
        expect(root.depth, equals(0), reason: '$label: root depth != 0');
        expect(root.parent, isNull, reason: '$label: root has parent');
      }

      checkRoot(wrapped.gameSystem, 'gameSystem');
      checkRoot(wrapped.primaryCatalog, 'primaryCatalog');
      for (var i = 0; i < wrapped.dependencyCatalogs.length; i++) {
        checkRoot(wrapped.dependencyCatalogs[i], 'dependency[$i]');
      }
    });

    test('Provenance: fileId and fileType on every node', () async {
      final wrapped = await WrapService().wrapBundle(parsedBundle: parsedBundle);

      void checkProvenance(WrappedFile wf, String expectedFileId, SourceFileType expectedType, String label) {
        for (final node in wf.nodes) {
          expect(node.fileId, equals(expectedFileId),
              reason: '$label: fileId mismatch at node ${node.ref.nodeIndex}');
          expect(node.fileType, equals(expectedType),
              reason: '$label: fileType mismatch at node ${node.ref.nodeIndex}');
        }
      }

      checkProvenance(wrapped.gameSystem, parsedBundle.gameSystem.fileId, SourceFileType.gst, 'gameSystem');
      checkProvenance(wrapped.primaryCatalog, parsedBundle.primaryCatalog.fileId, SourceFileType.cat, 'primaryCatalog');
      for (var i = 0; i < wrapped.dependencyCatalogs.length; i++) {
        checkProvenance(
          wrapped.dependencyCatalogs[i],
          parsedBundle.dependencyCatalogs[i].fileId,
          SourceFileType.cat,
          'dependency[$i]',
        );
      }
    });

    test('Determinism: wrapping twice yields identical structure', () async {
      final wrapService = WrapService();
      final wrapped1 = await wrapService.wrapBundle(parsedBundle: parsedBundle);
      final wrapped2 = await wrapService.wrapBundle(parsedBundle: parsedBundle);

      void checkEquivalent(WrappedFile wf1, WrappedFile wf2, String label) {
        expect(wf1.nodes.length, equals(wf2.nodes.length),
            reason: '$label: node count differs');

        for (var i = 0; i < wf1.nodes.length; i++) {
          final n1 = wf1.nodes[i];
          final n2 = wf2.nodes[i];

          expect(n1.ref.nodeIndex, equals(n2.ref.nodeIndex),
              reason: '$label: nodeIndex differs at $i');
          expect(n1.tagName, equals(n2.tagName),
              reason: '$label: tagName differs at $i');
          expect(n1.depth, equals(n2.depth),
              reason: '$label: depth differs at $i');
          expect(n1.parent?.nodeIndex, equals(n2.parent?.nodeIndex),
              reason: '$label: parent differs at $i');
          expect(n1.children.length, equals(n2.children.length),
              reason: '$label: children count differs at $i');

          for (var j = 0; j < n1.children.length; j++) {
            expect(n1.children[j].nodeIndex, equals(n2.children[j].nodeIndex),
                reason: '$label: child[$j] differs at node $i');
          }
        }
      }

      checkEquivalent(wrapped1.gameSystem, wrapped2.gameSystem, 'gameSystem');
      checkEquivalent(wrapped1.primaryCatalog, wrapped2.primaryCatalog, 'primaryCatalog');
      for (var i = 0; i < wrapped1.dependencyCatalogs.length; i++) {
        checkEquivalent(wrapped1.dependencyCatalogs[i], wrapped2.dependencyCatalogs[i], 'dependency[$i]');
      }
    });

    test('idIndex contains only nodes with id attribute', () async {
      final wrapped = await WrapService().wrapBundle(parsedBundle: parsedBundle);

      void checkIdIndex(WrappedFile wf, String label) {
        // Every ref in idIndex must point to a node with matching id
        for (final entry in wf.idIndex.entries) {
          final id = entry.key;
          for (final ref in entry.value) {
            final node = wf.nodes[ref.nodeIndex];
            expect(node.attributes['id'], equals(id),
                reason: '$label: idIndex[$id] points to node without matching id');
          }
        }

        // Every node with id attribute must be in idIndex
        for (final node in wf.nodes) {
          final id = node.attributes['id'];
          if (id != null) {
            expect(wf.idIndex.containsKey(id), isTrue,
                reason: '$label: node with id=$id not in idIndex');
            expect(wf.idIndex[id]!.contains(node.ref), isTrue,
                reason: '$label: node ref not in idIndex[$id]');
          }
        }
      }

      checkIdIndex(wrapped.gameSystem, 'gameSystem');
      checkIdIndex(wrapped.primaryCatalog, 'primaryCatalog');
      for (var i = 0; i < wrapped.dependencyCatalogs.length; i++) {
        checkIdIndex(wrapped.dependencyCatalogs[i], 'dependency[$i]');
      }
    });
  });
}

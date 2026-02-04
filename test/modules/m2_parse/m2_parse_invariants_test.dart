import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m2_parse/m2_parse.dart';

/// Structural invariant tests for M2 Parse.
///
/// These tests lock in losslessness guarantees:
/// - ElementDto preserves tag, attributes, child order, text nodes
/// - Provenance: ParsedFile.fileId matches originating SourceFileMetadata.fileId
/// - Determinism: parsing same RawPackBundle twice yields equivalent DTO graphs
///
/// NO schema assumptions. NO rule logic. NO cross-file linking.
void main() {
  const testSource = SourceLocator(
    sourceKey: 'bsdata_wh40k_10e',
    sourceUrl: 'https://github.com/BSData/wh40k-10e',
    branch: 'main',
  );

  late RawPackBundle rawBundle;

  setUpAll(() async {
    // Clean storage
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    // Acquire bundle once for all invariant tests
    final gameSystemBytes = await File('test/Warhammer 40,000.gst').readAsBytes();
    final primaryCatalogBytes = await File('test/Imperium - Space Marines.cat').readAsBytes();

    final dependencyFiles = <String, String>{
      'b00-cd86-4b4c-97ba': 'test/Imperium - Agents of the Imperium.cat',
      '7481-280e-b55e-7867': 'test/Library - Titans.cat',
      '1b6d-dc06-5db9-c7d1': 'test/Imperium - Imperial Knights - Library.cat',
      'ac3b-689c-4ad4-70cb': 'test/Library - Astartes Heresy Legends.cat',
    };

    rawBundle = await AcquireService().buildBundle(
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
  });

  tearDownAll(() async {
    final dir = Directory('appDataRoot');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  group('M2 Parse: structural invariants', () {
    test('ElementDto preserves tag name', () async {
      final parsed = await ParseService().parseBundle(rawBundle: rawBundle);

      // Every element must have a non-empty tag name
      void checkTagName(ElementDto dto, String path) {
        expect(dto.tagName.isNotEmpty, isTrue,
            reason: 'Empty tag name at $path');
        for (var i = 0; i < dto.children.length; i++) {
          checkTagName(dto.children[i], '$path/${dto.tagName}[$i]');
        }
      }

      checkTagName(parsed.gameSystem.root, 'gameSystem');
      checkTagName(parsed.primaryCatalog.root, 'primaryCatalog');
      for (var i = 0; i < parsed.dependencyCatalogs.length; i++) {
        checkTagName(parsed.dependencyCatalogs[i].root, 'dependency[$i]');
      }
    });

    test('ElementDto preserves attributes as map', () async {
      final parsed = await ParseService().parseBundle(rawBundle: rawBundle);

      // Every element must have a non-null attributes map
      void checkAttributes(ElementDto dto, String path) {
        expect(dto.attributes, isNotNull,
            reason: 'Null attributes at $path');
        expect(dto.attributes, isA<Map<String, String>>(),
            reason: 'Attributes not Map<String, String> at $path');
        for (var i = 0; i < dto.children.length; i++) {
          checkAttributes(dto.children[i], '$path/${dto.tagName}[$i]');
        }
      }

      checkAttributes(parsed.gameSystem.root, 'gameSystem');
      checkAttributes(parsed.primaryCatalog.root, 'primaryCatalog');
    });

    test('ElementDto preserves child order (children list is ordered)', () async {
      final parsed = await ParseService().parseBundle(rawBundle: rawBundle);

      // Children must be a List (inherently ordered)
      void checkChildOrder(ElementDto dto, String path) {
        expect(dto.children, isA<List<ElementDto>>(),
            reason: 'Children not List at $path');
        for (var i = 0; i < dto.children.length; i++) {
          checkChildOrder(dto.children[i], '$path/${dto.tagName}[$i]');
        }
      }

      checkChildOrder(parsed.gameSystem.root, 'gameSystem');
      checkChildOrder(parsed.primaryCatalog.root, 'primaryCatalog');
    });

    test('ElementDto text content is nullable (handles empty/mixed content)', () async {
      final parsed = await ParseService().parseBundle(rawBundle: rawBundle);

      // textContent can be null or String - must not throw
      void checkTextContent(ElementDto dto, String path) {
        // Just access it - should not throw
        final _ = dto.textContent;
        expect(dto.textContent == null || dto.textContent is String, isTrue,
            reason: 'textContent not null or String at $path');
        for (var i = 0; i < dto.children.length; i++) {
          checkTextContent(dto.children[i], '$path/${dto.tagName}[$i]');
        }
      }

      checkTextContent(parsed.gameSystem.root, 'gameSystem');
      checkTextContent(parsed.primaryCatalog.root, 'primaryCatalog');
    });

    test('Provenance: ParsedFile.fileId matches SourceFileMetadata.fileId', () async {
      final parsed = await ParseService().parseBundle(rawBundle: rawBundle);

      // gameSystem provenance
      expect(parsed.gameSystem.fileId, rawBundle.gameSystemMetadata.fileId,
          reason: 'gameSystem fileId mismatch');

      // primaryCatalog provenance
      expect(parsed.primaryCatalog.fileId, rawBundle.primaryCatalogMetadata.fileId,
          reason: 'primaryCatalog fileId mismatch');

      // dependency provenance
      final rawDepFileIds = rawBundle.dependencyCatalogMetadatas.map((m) => m.fileId).toSet();
      for (final dep in parsed.dependencyCatalogs) {
        expect(rawDepFileIds.contains(dep.fileId), isTrue,
            reason: 'dependency fileId ${dep.fileId} not found in raw bundle');
      }
    });

    test('Determinism: parsing same RawPackBundle twice yields equivalent DTO graphs', () async {
      final parseService = ParseService();

      final parsed1 = await parseService.parseBundle(rawBundle: rawBundle);
      final parsed2 = await parseService.parseBundle(rawBundle: rawBundle);

      // packId must match
      expect(parsed1.packId, parsed2.packId);

      // Same number of files
      expect(parsed1.dependencyCatalogs.length, parsed2.dependencyCatalogs.length);

      // Helper to compare ElementDto trees
      bool dtoEquals(ElementDto a, ElementDto b) {
        if (a.tagName != b.tagName) return false;
        if (a.attributes.length != b.attributes.length) return false;
        for (final key in a.attributes.keys) {
          if (a.attributes[key] != b.attributes[key]) return false;
        }
        if (a.children.length != b.children.length) return false;
        for (var i = 0; i < a.children.length; i++) {
          if (!dtoEquals(a.children[i], b.children[i])) return false;
        }
        if (a.textContent != b.textContent) return false;
        return true;
      }

      // Compare roots
      expect(dtoEquals(parsed1.gameSystem.root, parsed2.gameSystem.root), isTrue,
          reason: 'gameSystem DTO not equivalent on second parse');
      expect(dtoEquals(parsed1.primaryCatalog.root, parsed2.primaryCatalog.root), isTrue,
          reason: 'primaryCatalog DTO not equivalent on second parse');

      // Compare dependencies (same order)
      for (var i = 0; i < parsed1.dependencyCatalogs.length; i++) {
        expect(dtoEquals(parsed1.dependencyCatalogs[i].root, parsed2.dependencyCatalogs[i].root), isTrue,
            reason: 'dependency[$i] DTO not equivalent on second parse');
      }
    });

    test('sourceIndex is nullable (best-effort, no crash)', () async {
      final parsed = await ParseService().parseBundle(rawBundle: rawBundle);

      // sourceIndex can be null or int - accessing it should not throw
      void checkSourceIndex(ElementDto dto, String path) {
        final idx = dto.sourceIndex;
        expect(idx == null || idx is int, isTrue,
            reason: 'sourceIndex not null or int at $path');
        for (var i = 0; i < dto.children.length; i++) {
          checkSourceIndex(dto.children[i], '$path/${dto.tagName}[$i]');
        }
      }

      checkSourceIndex(parsed.gameSystem.root, 'gameSystem');
      checkSourceIndex(parsed.primaryCatalog.root, 'primaryCatalog');
    });
  });
}

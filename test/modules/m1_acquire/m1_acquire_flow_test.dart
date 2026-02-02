import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';
import 'package:combat_goblin_prime/modules/m1_acquire/services/preflight_scan_service.dart';

void main() {
  group('M1 Acquire: flow harness (fixtures)', () {
    setUp(() async {
      // Always start clean: deterministic storage root.
      final dir = Directory('appDataRoot');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    tearDown(() async {
      // Keep reruns clean.
      final dir = Directory('appDataRoot');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('buildBundle: reads fixtures, preflights, and either succeeds or fails with AcquireFailure (dependencies)', () async {
      final gameSystemFile = File('test/Warhammer 40,000.gst');
      final primaryCatalogFile = File('test/Imperium - Space Marines.cat');

      expect(await gameSystemFile.exists(), isTrue,
          reason: 'Missing fixture: test/Warhammer 40,000.gst');
      expect(await primaryCatalogFile.exists(), isTrue,
          reason: 'Missing fixture: test/Imperium - Space Marines.cat');

      final gameSystemBytes = await gameSystemFile.readAsBytes();
      final primaryCatalogBytes = await primaryCatalogFile.readAsBytes();

      // Diagnostic: scan preflight first to see rootIds
      final preflightService = PreflightScanService();
      final gsPreflight = await preflightService.scanBytes(
        bytes: gameSystemBytes,
        fileType: SourceFileType.gst,
      );
      final catPreflight = await preflightService.scanBytes(
        bytes: primaryCatalogBytes,
        fileType: SourceFileType.cat,
      );
      print('[DIAGNOSTIC] gameSystem rootId: ${gsPreflight.rootId}');
      print('[DIAGNOSTIC] primaryCatalog rootId: ${catPreflight.rootId}');
      print('[DIAGNOSTIC] primaryCatalog declaredGameSystemId: ${catPreflight.declaredGameSystemId}');
      print('[DIAGNOSTIC] primaryCatalog dependencies: ${catPreflight.importDependencies.map((d) => d.targetId).toList()}');

      final acquireService = AcquireService();

      RawPackBundle? bundle;
      try {
        bundle = await acquireService.buildBundle(
          gameSystemBytes: gameSystemBytes,
          gameSystemExternalFileName: 'Warhammer 40,000.gst',
          primaryCatalogBytes: primaryCatalogBytes,
          primaryCatalogExternalFileName: 'Imperium - Space Marines.cat',
          requestDependencyBytes: (missingTargetId) async {
            // Fixtures-only harness: no dependency catalog files yet.
            // Returning null should cause AcquireFailure if dependencies exist.
            print('[TEST] Dependency requested: $missingTargetId');
            return null;
          },
        );
      } on AcquireFailure catch (e) {
        // Expected outcome when the primary catalog declares dependencies and
        // the harness does not provide them.
        print('[TEST OUTCOME] AcquireFailure thrown: ${e.message}');
        expect(e.message.isNotEmpty, isTrue);
        return;
      }

      // If it did not throw AcquireFailure, we expect a valid bundle.
      expect(bundle, isNotNull);
      print('[TEST OUTCOME] RawPackBundle produced successfully');

      final b = bundle!;
      print('[TEST OUTCOME] packId: ${b.packId}');
      print('[TEST OUTCOME] gameSystem fileId: ${b.gameSystemMetadata.fileId}');
      print('[TEST OUTCOME] primaryCatalog fileId: ${b.primaryCatalogMetadata.fileId}');

      // Preflight sanity
      expect(b.gameSystemPreflight.fileType, SourceFileType.gst);
      expect(b.primaryCatalogPreflight.fileType, SourceFileType.cat);
      expect(b.gameSystemPreflight.rootId.isNotEmpty, isTrue);
      expect(b.primaryCatalogPreflight.rootId.isNotEmpty, isTrue);

      // Pack identity
      expect(b.packId.isNotEmpty, isTrue);

      // FileId sanity (sha-256 hex is 64 chars)
      expect(b.gameSystemMetadata.fileId.length, 64);
      expect(b.primaryCatalogMetadata.fileId.length, 64);

      // Storage results: stored files must exist
      final gsStored = File(b.gameSystemMetadata.storedPath);
      final catStored = File(b.primaryCatalogMetadata.storedPath);
      expect(await gsStored.exists(), isTrue);
      expect(await catStored.exists(), isTrue);

      // Path contract checks (string containment only; do not hardcode separators)
      expect(b.gameSystemMetadata.storedPath.contains('appDataRoot'), isTrue);
      expect(b.gameSystemMetadata.storedPath.contains('gamesystem_cache'), isTrue);
      expect(b.gameSystemMetadata.storedPath.contains(b.gameSystemPreflight.rootId), isTrue);

      expect(b.primaryCatalogMetadata.storedPath.contains('appDataRoot'), isTrue);
      expect(b.primaryCatalogMetadata.storedPath.contains('packs'), isTrue);
      expect(b.primaryCatalogMetadata.storedPath.contains(b.packId), isTrue);
      expect(b.primaryCatalogMetadata.storedPath.contains('catalogs'), isTrue);
      expect(b.primaryCatalogMetadata.storedPath.contains(b.primaryCatalogPreflight.rootId), isTrue);

      // Idempotency: second run must not change ids or break overwrite rules.
      final bundle2 = await acquireService.buildBundle(
        gameSystemBytes: gameSystemBytes,
        gameSystemExternalFileName: 'Warhammer 40,000.gst',
        primaryCatalogBytes: primaryCatalogBytes,
        primaryCatalogExternalFileName: 'Imperium - Space Marines.cat',
        requestDependencyBytes: (missingTargetId) async {
          return null;
        },
      );

      expect(bundle2.packId, b.packId);
      expect(bundle2.gameSystemMetadata.fileId, b.gameSystemMetadata.fileId);
      expect(bundle2.primaryCatalogMetadata.fileId, b.primaryCatalogMetadata.fileId);

      expect(await File(bundle2.gameSystemMetadata.storedPath).exists(), isTrue);
      expect(await File(bundle2.primaryCatalogMetadata.storedPath).exists(), isTrue);
    });
  });
}

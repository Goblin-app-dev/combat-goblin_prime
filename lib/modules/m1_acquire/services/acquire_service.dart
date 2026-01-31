import 'package:crypto/crypto.dart';

import '../models/acquire_failure.dart';
import '../models/preflight_scan_result.dart';
import '../models/raw_pack_bundle.dart';
import '../models/source_file_metadata.dart';
import '../models/source_file_type.dart';
import '../services/preflight_scan_service.dart';
import '../storage/acquire_storage.dart';

class AcquireService {
  Future<RawPackBundle> buildBundle({
    required List<int> gameSystemBytes,
    required String gameSystemExternalFileName,
    required List<int> primaryCatalogBytes,
    required String primaryCatalogExternalFileName,
    required Future<List<int>?> Function(String missingTargetId)
        requestDependencyBytes,
  }) async {
    final preflightScanService = PreflightScanService();
    final acquireStorage = AcquireStorage();

    final gameSystemPreflight = await preflightScanService.scanBytes(
      bytes: gameSystemBytes,
      fileType: SourceFileType.gst,
    );

    final primaryCatalogPreflight = await preflightScanService.scanBytes(
      bytes: primaryCatalogBytes,
      fileType: SourceFileType.cat,
    );

    if (primaryCatalogPreflight.declaredGameSystemId != null &&
        primaryCatalogPreflight.declaredGameSystemId !=
            gameSystemPreflight.rootId) {
      throw AcquireFailure(
        message: 'Catalog game system mismatch.',
        details:
            'Expected ${gameSystemPreflight.rootId} but got ${primaryCatalogPreflight.declaredGameSystemId}.',
      );
    }

    final primaryCatalogHash = sha256.convert(primaryCatalogBytes).toString();
    final packId =
        '${gameSystemPreflight.rootId}_${primaryCatalogPreflight.rootId}_$primaryCatalogHash';

    final gameSystemExtensionIndex =
        gameSystemExternalFileName.lastIndexOf('.');
    final gameSystemFileExtension = gameSystemExtensionIndex == -1
        ? gameSystemPreflight.fileType.name
        : gameSystemExternalFileName.substring(gameSystemExtensionIndex + 1);

    final primaryCatalogExtensionIndex =
        primaryCatalogExternalFileName.lastIndexOf('.');
    final primaryCatalogFileExtension = primaryCatalogExtensionIndex == -1
        ? primaryCatalogPreflight.fileType.name
        : primaryCatalogExternalFileName.substring(
            primaryCatalogExtensionIndex + 1,
          );

    final gameSystemMetadata = await acquireStorage.storeFile(
      bytes: gameSystemBytes,
      fileType: SourceFileType.gst,
      externalFileName: gameSystemExternalFileName,
      rootId: gameSystemPreflight.rootId,
      packId: null,
      fileExtension: gameSystemFileExtension,
    );

    final primaryCatalogMetadata = await acquireStorage.storeFile(
      bytes: primaryCatalogBytes,
      fileType: SourceFileType.cat,
      externalFileName: primaryCatalogExternalFileName,
      rootId: primaryCatalogPreflight.rootId,
      packId: packId,
      fileExtension: primaryCatalogFileExtension,
    );

    final dependencyTargetIds = primaryCatalogPreflight.importDependencies
        .map((dependency) => dependency.targetId)
        .toSet();
    dependencyTargetIds.remove(primaryCatalogPreflight.rootId);
    final missingTargetIds = dependencyTargetIds.toList()..sort();

    final dependencyCatalogMetadatas = <SourceFileMetadata>[];
    final dependencyCatalogPreflights = <PreflightScanResult>[];
    final dependencyCatalogBytesList = <List<int>>[];

    for (final targetId in missingTargetIds) {
      final dependencyBytes = await requestDependencyBytes(targetId);
      if (dependencyBytes == null) {
        throw AcquireFailure(
          message: 'Missing dependency catalog bytes.',
          details: 'targetId=$targetId',
        );
      }

      final dependencyPreflight = await preflightScanService.scanBytes(
        bytes: dependencyBytes,
        fileType: SourceFileType.cat,
      );

      if (dependencyPreflight.rootId != targetId) {
        throw AcquireFailure(
          message: 'Dependency catalog id mismatch.',
          details:
              'targetId=$targetId rootId=${dependencyPreflight.rootId}.',
        );
      }

      final dependencyMetadata = await acquireStorage.storeFile(
        bytes: dependencyBytes,
        fileType: SourceFileType.cat,
        externalFileName: targetId,
        rootId: dependencyPreflight.rootId,
        packId: packId,
        fileExtension: SourceFileType.cat.name,
      );

      dependencyCatalogMetadatas.add(dependencyMetadata);
      dependencyCatalogPreflights.add(dependencyPreflight);
      dependencyCatalogBytesList.add(dependencyBytes);
    }

    return RawPackBundle(
      packId: packId,
      createdAt: DateTime.now().toUtc(),
      gameSystemMetadata: gameSystemMetadata,
      gameSystemPreflight: gameSystemPreflight,
      gameSystemBytes: gameSystemBytes,
      primaryCatalogMetadata: primaryCatalogMetadata,
      primaryCatalogPreflight: primaryCatalogPreflight,
      primaryCatalogBytes: primaryCatalogBytes,
      dependencyCatalogMetadatas: dependencyCatalogMetadatas,
      dependencyCatalogPreflights: dependencyCatalogPreflights,
      dependencyCatalogBytesList: dependencyCatalogBytesList,
      acquireDiagnostics: const [],
    );
  }
}

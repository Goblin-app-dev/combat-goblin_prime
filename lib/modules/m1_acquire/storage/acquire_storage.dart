import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/acquire_failure.dart';
import '../models/source_file_metadata.dart';
import '../models/source_file_type.dart';

class AcquireStorage {
  final Directory appDataRoot;

  AcquireStorage({Directory? appDataRoot})
      : appDataRoot = appDataRoot ?? Directory('appDataRoot');

  /// Rejects path segments that could escape the storage root.
  static void _validateSegment(String segment, String label) {
    if (segment.isEmpty) {
      throw AcquireFailure(message: '$label must not be empty.');
    }
    if (p.isAbsolute(segment)) {
      throw AcquireFailure(message: '$label must not be an absolute path.');
    }
    if (segment.contains('..')) {
      throw AcquireFailure(message: '$label must not contain path traversal.');
    }
    if (segment.contains('/') || segment.contains('\\')) {
      throw AcquireFailure(message: '$label must not contain path separators.');
    }
  }

  /// Ensures [resolved] is a child of [base] after normalization.
  static void _ensureContained(String base, String resolved) {
    final normalizedBase = p.normalize(p.absolute(base)) + p.separator;
    final normalizedResolved = p.normalize(p.absolute(resolved));
    if (!normalizedResolved.startsWith(normalizedBase)) {
      throw AcquireFailure(
        message: 'Resolved storage path escapes the base directory.',
      );
    }
  }

  Future<SourceFileMetadata> storeFile({
    required List<int> bytes,
    required SourceFileType fileType,
    required String externalFileName,
    required String rootId,
    required String? packId,
    required String fileExtension,
  }) async {
    if (fileType == SourceFileType.cat && packId == null) {
      throw StateError('Catalog storage requires packId.');
    }

    // Validate caller-supplied path segments before constructing any path.
    _validateSegment(rootId, 'rootId');
    if (packId != null) {
      _validateSegment(packId, 'packId');
    }

    final fileId = sha256.convert(bytes).toString();
    final byteLength = bytes.length;
    final importedAt = DateTime.now().toUtc();
    final normalizedFileExtension =
        fileExtension.startsWith('.') ? fileExtension : '.${fileExtension}';
    final storedPath = fileType == SourceFileType.gst
        ? p.join(appDataRoot.path, 'gamesystem_cache', rootId,
            '$fileId$normalizedFileExtension')
        : p.join(appDataRoot.path, 'packs', packId!, 'catalogs', rootId,
            '$fileId$normalizedFileExtension');

    // Final containment check: the resolved path must stay inside appDataRoot.
    _ensureContained(appDataRoot.path, storedPath);

    final storedFile = File(storedPath);

    await storedFile.parent.create(recursive: true);

    if (await storedFile.exists()) {
      final existingBytes = await storedFile.readAsBytes();
      final existingFileId = sha256.convert(existingBytes).toString();
      if (existingFileId != fileId) {
        throw StateError('Stored file hash mismatch for $storedPath.');
      }
    } else {
      await storedFile.writeAsBytes(bytes, flush: true);
    }

    final metadata = SourceFileMetadata(
      fileId: fileId,
      fileType: fileType,
      externalFileName: externalFileName,
      storedPath: storedPath,
      byteLength: byteLength,
      importedAt: importedAt,
    );

    if (fileType == SourceFileType.gst) {
      final metadataFile = File(
        '${appDataRoot.path}/gamesystem_cache/gamesystem_metadata.json',
      );

      if (await metadataFile.exists()) {
        final decoded = jsonDecode(await metadataFile.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw StateError('Cached gamesystem metadata is invalid.');
        }
        final storedFileId = decoded['fileId'];
        final storedFileType = decoded['fileType'];
        final storedExternalFileName = decoded['externalFileName'];
        final storedPathValue = decoded['storedPath'];
        final storedByteLength = decoded['byteLength'];
        final storedImportedAt = decoded['importedAt'];
        if (storedFileId is! String ||
            storedFileType is! String ||
            storedExternalFileName is! String ||
            storedPathValue is! String ||
            storedByteLength is! int ||
            storedImportedAt is! String) {
          throw StateError('Cached gamesystem metadata is invalid.');
        }
        if (storedFileId != fileId) {
          throw StateError('Cached gamesystem fileId mismatch.');
        }
        if (storedPathValue == storedPath) {
          final cachedFile = File(storedPathValue);
          if (!await cachedFile.exists()) {
            throw StateError('Cached gamesystem file is missing.');
          }

          return SourceFileMetadata(
            fileId: storedFileId,
            fileType: SourceFileType.values.byName(storedFileType),
            externalFileName: storedExternalFileName,
            storedPath: storedPathValue,
            byteLength: storedByteLength,
            importedAt: DateTime.parse(storedImportedAt),
          );
        }
      }

      await metadataFile.writeAsString(
        jsonEncode({
          'fileId': metadata.fileId,
          'fileType': metadata.fileType.name,
          'externalFileName': metadata.externalFileName,
          'storedPath': metadata.storedPath,
          'byteLength': metadata.byteLength,
          'importedAt': metadata.importedAt.toIso8601String(),
          'rootId': rootId,
        }),
        flush: true,
      );
    }

    return metadata;
  }

  Future<void> deleteCachedGameSystem() async {
    final gamesystemCache =
        Directory('${appDataRoot.path}/gamesystem_cache');
    if (await gamesystemCache.exists()) {
      await gamesystemCache.delete(recursive: true);
    }
  }

  Future<SourceFileMetadata?> readCachedGameSystemMetadata() async {
    final metadataFile = File(
        '${appDataRoot.path}/gamesystem_cache/gamesystem_metadata.json');
    if (!await metadataFile.exists()) {
      return null;
    }
    final decoded = jsonDecode(await metadataFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Cached gamesystem metadata is invalid.');
    }
    final fileId = decoded['fileId'];
    final fileType = decoded['fileType'];
    final externalFileName = decoded['externalFileName'];
    final storedPath = decoded['storedPath'];
    final byteLength = decoded['byteLength'];
    final importedAt = decoded['importedAt'];
    if (fileId is! String ||
        fileType is! String ||
        externalFileName is! String ||
        storedPath is! String ||
        byteLength is! int ||
        importedAt is! String) {
      throw StateError('Cached gamesystem metadata is invalid.');
    }

    return SourceFileMetadata(
      fileId: fileId,
      fileType: SourceFileType.values.byName(fileType),
      externalFileName: externalFileName,
      storedPath: storedPath,
      byteLength: byteLength,
      importedAt: DateTime.parse(importedAt),
    );
  }

  Future<List<int>?> readCachedGameSystemBytes() async {
    final metadata = await readCachedGameSystemMetadata();
    if (metadata == null) {
      return null;
    }
    final storedFile = File(metadata.storedPath);
    if (!await storedFile.exists()) {
      throw StateError('Cached gamesystem file is missing.');
    }
    return storedFile.readAsBytes();
  }
}

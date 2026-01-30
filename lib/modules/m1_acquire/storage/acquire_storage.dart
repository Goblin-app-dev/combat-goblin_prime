import '../models/source_file_metadata.dart';
import '../models/source_file_type.dart';

abstract class AcquireStorage {
  Future<SourceFileMetadata> storeFile({
    required List<int> bytes,
    required SourceFileType fileType,
    required String externalFileName,
    required String rootId,
    required String fileExtension,
  });

  Future<void> deleteCachedGameSystem();

  Future<SourceFileMetadata?> readCachedGameSystemMetadata();

  Future<List<int>?> readCachedGameSystemBytes();
}

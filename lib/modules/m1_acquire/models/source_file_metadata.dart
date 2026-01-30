import 'source_file_type.dart';

class SourceFileMetadata {
  final String fileId;
  final SourceFileType fileType;
  final String externalFileName;
  final String storedPath;
  final int byteLength;
  final DateTime importedAt;

  const SourceFileMetadata({
    required this.fileId,
    required this.fileType,
    required this.externalFileName,
    required this.storedPath,
    required this.byteLength,
    required this.importedAt,
  });
}

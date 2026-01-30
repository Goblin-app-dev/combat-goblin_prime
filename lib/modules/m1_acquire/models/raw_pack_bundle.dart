import 'preflight_scan_result.dart';
import 'source_file_metadata.dart';

class Diagnostic {
  const Diagnostic();
}

class RawPackBundle {
  final String packId;
  final DateTime createdAt;

  final SourceFileMetadata gameSystemMetadata;
  final PreflightScanResult gameSystemPreflight;
  final List<int> gameSystemBytes;

  final SourceFileMetadata primaryCatalogMetadata;
  final PreflightScanResult primaryCatalogPreflight;
  final List<int> primaryCatalogBytes;

  final List<SourceFileMetadata> dependencyCatalogMetadatas;
  final List<PreflightScanResult> dependencyCatalogPreflights;
  final List<List<int>> dependencyCatalogBytesList;

  final List<Diagnostic> acquireDiagnostics;

  const RawPackBundle({
    required this.packId,
    required this.createdAt,
    required this.gameSystemMetadata,
    required this.gameSystemPreflight,
    required this.gameSystemBytes,
    required this.primaryCatalogMetadata,
    required this.primaryCatalogPreflight,
    required this.primaryCatalogBytes,
    required this.dependencyCatalogMetadatas,
    required this.dependencyCatalogPreflights,
    required this.dependencyCatalogBytesList,
    required this.acquireDiagnostics,
  });
}

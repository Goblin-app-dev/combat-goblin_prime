import 'pack_manifest.dart';
import 'preflight_scan_result.dart';
import 'source_file_metadata.dart';

class Diagnostic {
  const Diagnostic();
}

/// The lossless collection of source files and metadata produced by M1 Acquire.
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

  /// Manifest data for persistence after downstream success.
  /// Contains version tokens for update checking.
  final PackManifest manifest;

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
    required this.manifest,
  });
}

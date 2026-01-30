import '../models/raw_pack_bundle.dart';

abstract class AcquireService {
  Future<RawPackBundle> buildBundle({
    required List<int> gameSystemBytes,
    required String gameSystemExternalFileName,
    required List<int> primaryCatalogBytes,
    required String primaryCatalogExternalFileName,
    required Future<List<int>?> Function(String missingTargetId)
        requestDependencyBytes,
  });
}

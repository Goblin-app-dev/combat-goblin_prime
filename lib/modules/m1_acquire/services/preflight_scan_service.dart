import '../models/preflight_scan_result.dart';
import '../models/source_file_type.dart';

abstract class PreflightScanService {
  Future<PreflightScanResult> scanBytes({
    required List<int> bytes,
    required SourceFileType fileType,
  });
}

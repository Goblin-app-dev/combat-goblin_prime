import 'import_dependency.dart';
import 'source_file_type.dart';

class PreflightScanResult {
  final SourceFileType fileType;
  final String rootTag;
  final String rootId;
  final String? rootName;
  final String? rootRevision;
  final String? rootType;
  final String? declaredGameSystemId;
  final String? declaredGameSystemRevision;
  final String? libraryFlag;
  final List<ImportDependency> importDependencies;

  const PreflightScanResult({
    required this.fileType,
    required this.rootTag,
    required this.rootId,
    this.rootName,
    this.rootRevision,
    this.rootType,
    this.declaredGameSystemId,
    this.declaredGameSystemRevision,
    this.libraryFlag,
    required this.importDependencies,
  });
}

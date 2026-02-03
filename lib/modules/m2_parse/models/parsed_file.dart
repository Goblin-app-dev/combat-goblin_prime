import 'package:combat_goblin_prime/modules/m1_acquire/m1_acquire.dart';

import 'element_dto.dart';

/// A parsed XML file with its root element and source provenance.
///
/// Part of M2 Parse (Phase 1B).
class ParsedFile {
  /// SHA-256 from SourceFileMetadata (links back to raw bytes).
  final String fileId;

  /// gst or cat.
  final SourceFileType fileType;

  /// Root element's id attribute (from preflight).
  final String rootId;

  /// The parsed root element (gameSystem or catalogue).
  final ElementDto root;

  const ParsedFile({
    required this.fileId,
    required this.fileType,
    required this.rootId,
    required this.root,
  });
}

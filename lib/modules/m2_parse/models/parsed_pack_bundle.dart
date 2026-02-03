import 'parsed_file.dart';

/// The complete parsed output for a pack.
///
/// Part of M2 Parse (Phase 1B).
class ParsedPackBundle {
  /// From RawPackBundle.
  final String packId;

  /// When parsing completed.
  final DateTime parsedAt;

  /// Parsed .gst file.
  final ParsedFile gameSystem;

  /// Parsed primary .cat file.
  final ParsedFile primaryCatalog;

  /// Parsed dependency .cat files (document order preserved).
  final List<ParsedFile> dependencyCatalogs;

  const ParsedPackBundle({
    required this.packId,
    required this.parsedAt,
    required this.gameSystem,
    required this.primaryCatalog,
    required this.dependencyCatalogs,
  });
}

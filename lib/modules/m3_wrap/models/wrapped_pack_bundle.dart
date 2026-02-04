import 'wrapped_file.dart';

/// Complete M3 output for a pack.
///
/// One-to-one correspondence with ParsedPackBundle.
/// No merging. No linking. No interpretation.
///
/// Part of M3 Wrap (Phase 1C).
class WrappedPackBundle {
  /// From ParsedPackBundle.packId.
  final String packId;

  /// When wrapping completed.
  final DateTime wrappedAt;

  /// Wrapped .gst file.
  final WrappedFile gameSystem;

  /// Wrapped primary .cat file.
  final WrappedFile primaryCatalog;

  /// Wrapped dependency .cat files.
  final List<WrappedFile> dependencyCatalogs;

  const WrappedPackBundle({
    required this.packId,
    required this.wrappedAt,
    required this.gameSystem,
    required this.primaryCatalog,
    required this.dependencyCatalogs,
  });
}

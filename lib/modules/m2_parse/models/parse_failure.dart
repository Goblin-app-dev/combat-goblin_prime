/// Exception for parse errors with diagnostic context.
///
/// Part of M2 Parse (Phase 1B).
class ParseFailure implements Exception {
  /// Human-readable error description.
  final String message;

  /// Which file failed (if known).
  final String? fileId;

  /// Document-order index where error occurred (if known).
  final int? sourceIndex;

  /// Additional context.
  final String? details;

  const ParseFailure({
    required this.message,
    this.fileId,
    this.sourceIndex,
    this.details,
  });

  @override
  String toString() {
    final parts = ['ParseFailure: $message'];
    if (fileId != null) parts.add('fileId=$fileId');
    if (sourceIndex != null) parts.add('sourceIndex=$sourceIndex');
    if (details != null) parts.add('details=$details');
    return parts.join(', ');
  }
}

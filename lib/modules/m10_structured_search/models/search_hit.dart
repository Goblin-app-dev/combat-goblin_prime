import 'match_reason.dart';
import 'search_doc_type.dart';

/// A single document that matched a [SearchRequest].
///
/// Contains identification and match metadata only.
/// No derived computation. No evaluation output.
class SearchHit {
  /// Unique document ID from M9 (e.g. "unit:abc", "weapon:xyz").
  final String docId;

  /// Document type.
  final SearchDocType docType;

  /// Canonical key from M9 index (normalized name for grouping).
  final String canonicalKey;

  /// Human-readable display name.
  final String displayName;

  /// Reasons this document matched the query.
  ///
  /// Stored in deterministic order: the service must sort match reasons
  /// by enum index before constructing this list.
  final List<MatchReason> matchReasons;

  const SearchHit({
    required this.docId,
    required this.docType,
    required this.canonicalKey,
    required this.displayName,
    required this.matchReasons,
  });
}

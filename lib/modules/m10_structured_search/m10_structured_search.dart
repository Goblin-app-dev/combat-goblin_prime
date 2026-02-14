/// M10 Structured Search — deterministic search over frozen M9 IndexBundle.
///
/// ## STATUS: FROZEN (2026-02-14)
///
/// ## Frozen Invariants
///
/// - **Public API**: [StructuredSearchService.search],
///   [StructuredSearchService.suggest], [StructuredSearchService.resolveByDocId]
/// - **Query drivers**: text, keywords, characteristicFilters (docTypes alone
///   is NOT a driver)
/// - **Empty-query contract**: no drivers → emptyQuery diagnostic, 0 hits
/// - **Deterministic ordering**: all results use explicit tie-break chain
///   terminating at docId (see [SearchResult] doc)
/// - **Diagnostic uniqueness**: at most one diagnostic per unsupported
///   dimension per request; sorted by code index then message
/// - **M9 delegation**: delegates to frozen M9 primitives; raw inspection
///   only for weapon keyword tokens and characteristic value matching
/// - **Filter support**: keywords unsupported for rules (invalidFilter);
///   characteristics unsupported for rules (no characteristics)
/// - **Suggest semantics**: merged, deduplicated, lex-sorted, limit-respecting
library m10_structured_search;

// Models
export 'models/match_reason.dart';
export 'models/search_config.dart';
export 'models/search_diagnostic.dart';
export 'models/search_doc_type.dart';
export 'models/search_failure.dart';
export 'models/search_hit.dart';
export 'models/search_mode.dart';
export 'models/search_request.dart';
export 'models/search_result.dart';
export 'models/search_sort.dart';
export 'models/sort_direction.dart';

// Services
export 'services/structured_search_service.dart';

// Extensions (optional)
export 'extensions/search_intent_parser.dart';
export 'extensions/search_presentation_formatter.dart';

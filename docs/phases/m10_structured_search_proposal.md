# M10 Structured Search — Names Proposal (Phase-Safe)

**Status:** SCAFFOLDED (names + file structure committed)
**Date:** 2026-02-13
**Depends on:** M9 Index (frozen)
**Input:** IndexBundle
**Output:** Deterministic search results
**Mutation:** None

## Overview

M10 introduces a deterministic structured search layer over the frozen M9
IndexBundle. This is **engine search over IndexBundle** — not repo search,
not GitHub search, not external search.

M10:
- Consumes IndexBundle
- Performs deterministic query resolution
- Returns stable, order-guaranteed results
- Does not mutate data
- Does not evaluate constraints
- Does not apply modifiers
- Does not reinterpret diagnostics

M10 operates in Index-only mode by default.
Optional higher-level features (intent parsing, presentation formatting) are
defined as separate abstract interfaces and are not required for core search.

## Scope Boundary

M10 may:
- Filter documents by type
- Match canonical keys
- Match indexed keywords
- Match indexed characteristics
- Perform deterministic fuzzy matching (optional, bounded)

M10 must not:
- Evaluate constraints (M6)
- Determine applicability (M7)
- Apply modifiers (M8)
- Re-link data (M4)
- Mutate IndexBundle
- Introduce global state
- Reinterpret M9 diagnostics

## Core Design

### Single Query Model

Replaces per-type queries with a unified request model.

#### SearchRequest

Represents a deterministic query over IndexBundle.

Fields:
- `String? text` — free-text query
- `Set<SearchDocType>? docTypes` — filter by document type
- `Set<String>? keywords` — filter by keyword tokens
- `Map<String, String>? characteristicFilters` — key=name, value=query
- `SearchMode mode` — autocomplete / fullText / structured
- `int limit` — max results
- `SearchSort sort` — relevance / alphabetical / docTypeThenAlphabetical
- `SortDirection sortDirection` — ascending / descending

Const constructor with defaults. No parsing logic. Pure request container.

#### SearchHit

- `String docId`
- `SearchDocType docType`
- `String canonicalKey`
- `String displayName`
- `List<MatchReason> matchReasons` — deterministic order by enum index

No derived computation. No evaluation output.

#### SearchResult

- `List<SearchHit> hits` — deterministically ordered by service
- `List<SearchDiagnostic> diagnostics` — M10-only

Tie-break rules for ordering:
1. Score (if applicable)
2. docType (enum index)
3. canonicalKey (lexicographic)
4. docId (lexicographic)

### Enums and Supporting Types

| Type | Values |
|------|--------|
| `SearchDocType` | unit, weapon, rule |
| `SearchMode` | autocomplete, fullText, structured |
| `SearchSort` | relevance, alphabetical, docTypeThenAlphabetical |
| `SortDirection` | ascending, descending |
| `MatchReason` | canonicalKeyMatch, keywordMatch, characteristicMatch, fuzzyMatch |

Relevance must be deterministic and stable.

### SearchConfig

Immutable, const-constructible configuration for the service:
- `int defaultLimit` (default: 20)
- `bool fuzzyEnabled` (default: false)
- `int fuzzyMaxEditDistance` (default: 2)

### Diagnostics + Failures (M10-only)

**SearchDiagnosticCode** (closed set):
- invalidFilter
- emptyQuery
- resultLimitApplied
- unsupportedMode

**SearchDiagnostic**: code + message + optional context map.

**SearchFailure**: Hard failures (invalid state, misuse). Does not reuse M9
diagnostics.

## Core Service Interface

### StructuredSearchService

Constructor: `StructuredSearchService({SearchConfig config})`

Consumes IndexBundle per-call (stateless with respect to index data).

Public methods:
- `SearchResult search(IndexBundle index, SearchRequest request)`
- `List<String> suggest(IndexBundle index, String prefix, {int limit})`
- `SearchHit? resolveByDocId(IndexBundle index, String docId)`

Must:
- Preserve deterministic ordering
- Never mutate inputs
- Never depend on evaluation modules (M6–M8)

M9 delegation policy:
- M10 delegates to the frozen M9 query surface where appropriate (lookup by
  docId, lookup by canonicalKey).
- Raw index access (sorted lists, SplayTreeMap indices) is allowed only for
  higher-level composition (filtering, sorting, fuzzy matching) that M9 does
  not provide.
- M10 must not re-implement functionality already present in M9's frozen
  query surface.

## Optional Extensions (Separate Layer)

These are **not part of core M10** and must remain optional.

### SearchIntentParser (abstract)

- Converts natural language → SearchRequest
- Must not access M6–M8
- Must not access IndexBundle directly

### SearchPresentationFormatter (abstract)

- Converts SearchResult → display/voice strings
- Must not access IndexBundle directly
- Must not access M6–M8

Voice/display formatting is **not** an M10 core responsibility.

## Determinism Guarantees

M10 must guarantee:
- Stable sorting across runs
- Explicit tie-break rules (score → docType → canonicalKey → docId)
- No iteration over unordered maps
- No time-based or random scoring

## File Structure

```
lib/modules/m10_structured_search/
  m10_structured_search.dart          # barrel export
  models/
    match_reason.dart
    search_config.dart
    search_diagnostic.dart
    search_doc_type.dart
    search_failure.dart
    search_hit.dart
    search_mode.dart
    search_request.dart
    search_result.dart
    search_sort.dart
    sort_direction.dart
  services/
    structured_search_service.dart
  extensions/                         # optional, not required for core
    search_intent_parser.dart
    search_presentation_formatter.dart
```

## Non-Goals for M10

- No constraint evaluation
- No modifier application
- No roster awareness
- No persistence
- No caching layer (caller responsibility)
- No cross-pack merging
- No voice formatting in core (separate extension only)

## Dependencies

- M9 IndexBundle (frozen)
- No dependency on M6–M8

## Open Questions (Explicitly Deferred)

1. Should fuzzy matching be enabled by default or opt-in?
2. Should relevance scoring be introduced now or deferred?
3. Should composite multi-field queries be fully supported in v1?
4. Where should caching of SearchResult live (outside M10)?

## Compatibility Note

M10 must function with:
- Index-only mode (primary)
- Optional enrichment layer (external, additive only)

M10 must not require orchestrator output.

## Why This Version Is Safer

- Eliminates query-type explosion (single SearchRequest replaces per-type queries)
- Removes voice formatting from core
- Makes intent parsing explicitly optional
- Locks search to M9 IndexBundle input only — no GitHub search, no repo search
- Aligns with existing module naming discipline
- Prevents evaluation creep

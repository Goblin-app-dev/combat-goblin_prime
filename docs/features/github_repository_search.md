# GitHub Repository Search Feature (Names-Only Design)

## Status and boundary

- This is a **feature**, not a pipeline module.
- It is **not part of M1–M9** and must not change M1–M9 contracts.
- Implementation location: `lib/features/github_repository_search/`.

## Isolation rules (enforceable)

1. No imports from `lib/modules/` inside `lib/features/github_repository_search/`.
2. No global singletons (no top-level shared HTTP client/cache/token store).
3. Explicit entrypoint only: UI/provider calls `GitHubRepositorySearchService`; no other feature uses internal implementation classes.
4. Auth token must not be logged or exposed in diagnostics.

## Public API (frozen surface)

```dart
abstract interface class GitHubRepositorySearchService {
  Future<RepoSearchPage> search({
    required RepoSearchQuery query,
    String? pageCursor, // page-number token semantics
  });
}
```

### Query object

```dart
final class RepoSearchQuery {
  final String? text;
  final RepoSearchSort sort; // stars | updated
  final SortOrder order; // desc | asc
  final int pageSize; // default 30
  final RepoSearchMode mode; // flutterDiscovery | exactName
}
```

- No raw query-string concatenation outside query builder.
- Public `pageCursor` uses page-number semantics; treat it internally as `pageToken`/`page`.
- `pageCursor` maps to GitHub `page` (stringified int).
- `pageSize` default is **30** and maps to GitHub `per_page`; override only via `RepoSearchQuery` options.

## Request headers and API versioning

All requests to GitHub Search Repositories must send:

- `Accept: application/vnd.github+json`
- `X-GitHub-Api-Version: 2022-11-28`

### Result model

```dart
final class RepoSearchPage {
  final List<RepoSummary> items;
  final String? nextPageToken;
  final bool isLastPage;
  final int? totalCount;
  final RepoSearchDiagnostics? diagnostics;
}
```

### Normalized summary model

```dart
final class RepoSummary {
  final String fullName; // owner/name canonical
  final Uri htmlUrl;
  final String? description; // null-safe + trimmed
  final String? language;
  final int stargazersCount;
  final int forksCount;
  final DateTime updatedAt;
}
```

Normalization rules:
- `fullName` canonicalized to `owner/name`.
- `description` trimmed; empty string normalized to null.
- `updatedAt` represented as `DateTime`.
- Topics omitted unless explicitly supported by API variant/header.

## Query builder rules

Default mode (`flutterDiscovery`) base qualifiers:
- `archived:false`
- `language:dart`
- `topic:flutter`

Fallback when topic coverage is poor:
- `flutter in:name,description,readme`
- `language:dart`
- `archived:false`

Determinism:
1. Same inputs => same query string (stable qualifier ordering).
2. Same request params => stable ordering (always send explicit `sort` + `order`).

Defaults (frozen):
- `sort=stars`
- `order=desc`



Canonical default query payload (byte-for-byte test target):
- `language:dart topic:flutter archived:false`

Canonical fallback payload:
- `flutter in:name,description,readme language:dart archived:false`

Qualifier ordering rule (frozen for composed/dynamic queries):
- `archived`, `in`, `language`, `topic`, then free-text
- `flutterDiscovery` default still uses the canonical literal payload above for byte-for-byte assertions

Escaping/validation:
- Escape user text (quotes, colon, hyphen, unicode-safe).
- Reject invalid qualifiers from UI (whitelist supported qualifiers only).
- Disallow invalid language selector like `language:flutter`.

## Error model and mapping

```dart
enum RepoSearchError {
  unauthorized,
  rateLimited,
  forbidden,
  invalidQuery,
  networkFailure,
  invalidResponse,
  serverFailure,
}
```

Mapping:
- `401` => `unauthorized`
- `403` + rate-limit headers / secondary-limit signals => `rateLimited`
- `403` otherwise => `forbidden`
- `422` => `invalidQuery`
- timeout/DNS/socket => `networkFailure`
- JSON parse / schema mismatch => `invalidResponse`
- other 5xx => `serverFailure`

## Auth strategy

- Constructor injection only (example: `authTokenProvider`).
- Keep call-site stable even if auth is optional initially.
- Never include token or raw `Authorization` header in diagnostics.

## Test requirements (pre-implementation acceptance)

1. Unit tests: query builder determinism, qualifier ordering, escaping, whitelist enforcement.
2. Unit tests: normalization (`fullName`, trimming, casing expectations, null handling).
3. Contract tests with stubbed HTTP client (no live GitHub): 200 empty, 200 paged, 401, 403 rate-limit, 403 forbidden, 422, timeout, invalid JSON.
4. Redaction tests: diagnostics/log records must not contain auth token/header.
5. Coupling check: automated script verifies no imports from `lib/modules/` in feature files.


## AI-coder review checklist (paste-ready)

- ✅ Feature folder only (`lib/features/github_repository_search/`)
- ✅ No `lib/modules/` imports (enforced by isolation script)
- ✅ No global singletons
- ✅ Frozen API + data fields exactly
- ✅ Stable query builder ordering + escaping
- ✅ Always sends `sort=stars&order=desc` unless overridden
- ✅ Page/`per_page` pagination, `nextPageToken` is stringified page #
- ✅ Error mapping table implemented (`403` rateLimited vs forbidden)
- ✅ Auth injected, never logged
- ✅ Tests: determinism/escaping, whitelist, normalization, contract matrix, redaction, isolation

## Skills compliance notes

This feature design aligns to repository skills as follows:

- `skill_06_module_boundary_integrity`: feature code stays in `lib/features/github_repository_search/` and must not import `lib/modules/`.
- `skill_10_deterministic_behavior`: query builder and sort/order defaults are frozen and testable.
- `skill_11_debug_visibility`: typed error mapping and diagnostics are required.
- `skill_07_module_io_accountability`: request headers, auth injection, and output models are explicit.
- `skill_01_read_before_write` + naming skills (`02`, `03`, `13`): names/spec documented before implementation.

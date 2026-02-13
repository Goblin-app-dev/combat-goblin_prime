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
    String? pageCursor,
  });
}
```

### Query object

```dart
final class RepoSearchQuery {
  final String? text;
  final RepoSearchSort sort; // stars | updated
  final SortOrder order; // desc | asc
  final int pageSize; // default 20
  final RepoSearchMode mode; // flutterDiscovery | exactName
}
```

- No raw query-string concatenation outside query builder.
- `pageCursor` maps to GitHub `page` (stringified int).

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

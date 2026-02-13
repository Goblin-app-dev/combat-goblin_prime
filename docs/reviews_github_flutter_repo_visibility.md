# GitHub Flutter Repository Visibility Bug Review

## What I found in the current codebase

1. The app entry point is a static `MaterialApp`/`Scaffold` placeholder with no GitHub integration, no networking, and no repository browser UI.
2. There is no module that calls GitHub REST/GraphQL APIs, no OAuth token handling, and no search query builder.
3. The `pubspec.yaml` dependency list does not include an HTTP client package (such as `http` or `dio`) that would be needed to query GitHub repositories.
4. The existing modules are a deterministic pipeline (`m1_acquire` through `m9_index`) for parsing and evaluating Battlescribe-style data, not GitHub repository discovery.

## Why the Flutter GitHub visibility bug is happening

The bug cannot be fixed in-place because the feature is not implemented yet in this repository. There is currently nothing that could list repositories from GitHub (Flutter or otherwise).

## Fix plan (safe and incremental)

### Phase 1 — Add a repository search adapter

- Add a GitHub service abstraction:
  - `GitHubRepositorySearchService`
  - `GitHubRepositorySummary`
- Implement query composition with explicit Flutter-safe defaults:
  - `language:dart topic:flutter archived:false`
- Add pagination support (`page`, `per_page`) and deterministic sorting (`stars`, `updated`).

### Phase 2 — Add the Flutter-safe query guardrails

When user selects "Flutter repositories", map it to:

- `language:dart topic:flutter`

Avoid invalid filters such as:

- `language:flutter` (invalid language token on GitHub search)

Optional fallback if topic is sparse:

- `flutter in:name,description,readme language:dart`

### Phase 3 — UI and failure visibility

- Create a dedicated search screen with:
  - query field
  - chips for language/topic filters
  - explicit empty-state reason ("No results" vs "Rate limited" vs "Auth required")
- Surface GitHub response status and rate-limit diagnostics in-app.

### Phase 4 — Tests

- Unit tests for query builder:
  - ensures `language:dart topic:flutter`
  - rejects/normalizes `language:flutter`
- Contract tests with mocked GitHub responses:
  - empty result
  - invalid query
  - rate limit
  - pagination

## Architecture fit notes

This fits cleanly by adding a dedicated GitHub module rather than forcing behavior into existing M1-M9 parsing modules.


---

## Review adjustments from inline comments

The following constraints are now explicitly adopted for implementation review:

1. **Hard isolation boundary**
   - Feature lives only under `lib/features/github_repository_search/`.
   - No imports from `lib/modules/` into this feature.
   - No global singletons/caches/shared mutable state.
   - Add dedicated feature doc clarifying this is not part of M1–M9.

2. **Narrow stable API**
   - Public method shape:
     - `Future<RepoSearchPage> search({required RepoSearchQuery query, String? pageCursor})`
   - Query passed as value object only (no external raw query concatenation).
   - `RepoSummary` intentionally minimal and UI-focused.

3. **Determinism rules**
   - Same inputs produce same query string (stable qualifier ordering).
   - Same request parameters produce stable result ordering (explicit `sort` + `order`).
   - Default sorting frozen to `sort=stars&order=desc`.

4. **Pagination contract**
   - Expose `nextPageToken`, `isLastPage`, `totalCount`.
   - `nextPageToken` maps to GitHub integer `page` represented as string.

5. **Expanded error mapping**
   - `403` with rate-limit indicators => `rateLimited`.
   - `403` without such indicators => `forbidden`.
   - Invalid JSON/parse failures => `invalidResponse` (or `serverFailure` fallback).

6. **Authentication posture**
   - Auth injected via constructor/provider.
   - No auth material in diagnostics/logging.
   - Test doubles must stub auth header behavior.

7. **Test coverage additions**
   - Query escaping cases (quotes, colon, hyphen, unicode).
   - Qualifier whitelist enforcement.
   - Deterministic normalization checks.
   - Redaction test ensuring token/header never leaked.
   - Coupling check script to enforce no feature->modules imports.

For copy/paste, use the section below and/or `docs/features/github_repository_search.md`.


8. **Request headers and API versioning**
   - Always send `Accept: application/vnd.github+json`.
   - Always send `X-GitHub-Api-Version: 2022-11-28`.
   - Default `per_page` is frozen to `30`; override only via query options.

9. **Canonical query spec**
   - Default payload (byte-for-byte): `language:dart topic:flutter archived:false`.
   - Fallback payload (byte-for-byte): `flutter in:name,description,readme language:dart archived:false`.
   - Qualifier ordering is frozen to: `archived`, `in`, `language`, `topic`, then free-text.

10. **Pagination naming clarity**
   - Public param may remain `pageCursor`, but implementation uses explicit `pageToken`/`page` naming to avoid cursor ambiguity.

### Paste-ready implementation checklist

- ✅ Feature folder only (`lib/features/github_repository_search/`)
- ✅ No `lib/modules/` imports (enforced by isolation script)
- ✅ No global singletons
- ✅ Frozen API + data fields exactly
- ✅ Stable query builder ordering + escaping
- ✅ Always sends `sort=stars&order=desc` unless overridden
- ✅ Page/`per_page` pagination, `nextPageToken` is stringified page #
- ✅ Error mapping matches table + distinguishes `403` rateLimited vs forbidden
- ✅ Auth injected, never logged
- ✅ Tests: query determinism/escaping, whitelist, normalization, contract matrix, redaction, isolation


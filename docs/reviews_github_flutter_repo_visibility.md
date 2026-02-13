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


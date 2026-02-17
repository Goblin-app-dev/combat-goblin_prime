# Phase 11B: Multi-Catalog Selection & GitHub Sync — Names Proposal

**Status:** APPROVED
**Date:** 2026-02-17
**Approved:** 2026-02-17
**Author:** Claude
**Approval Required:** No (approved by user)

---

## Overview

Phase 11B extends the import workflow to support:
1. **Multi-catalog selection** — Users select up to 3 primary catalogs; each runs M1-M9 independently
2. **GitHub sync state** — Track blob SHAs separately from M1 storage for per-file update detection
3. **Multi-pack search** — Deterministic search merge across multiple IndexBundles

### Key Design Decisions (from user review)

1. **No M1 unfreeze** — Call M1 once per selected catalog, no engine changes
2. **Extend BsdResolverService** — No new parallel services (GitHubRepoTreeClient, etc.)
3. **Track both SHAs** — GitHub blob SHA for update detection, local fileId (SHA-256) for storage
4. **3-catalog limit** — Applies to user-selected primaries only; dependencies are auto-resolved and don't count
5. **Per-file updates** — "Update All" re-downloads only changed files, not everything
6. **Separate sync state** — GitHubSyncState stored in `appDataRoot/github_sync_state.json`, not in M1 metadata

---

## Proposed Names

### Constants

| Name | Type | Location | Purpose |
|------|------|----------|---------|
| `kMaxSelectedCatalogs` | `int` (value: 3) | `import_session_controller.dart` | Maximum user-selected primary catalogs |

### GitHub Sync State Types

| Name | Type | Location | Purpose |
|------|------|----------|---------|
| `TrackedFile` | class | `github_sync_state.dart` | Tracked file entry with blob SHA and local storage metadata |
| `SessionPackState` | class | `github_sync_state.dart` | Session pack state: selected primary rootIds + dependency closure |
| `RepoSyncState` | class | `github_sync_state.dart` | Per-repository sync state with tracked files map |
| `GitHubSyncState` | class | `github_sync_state.dart` | Complete sync state across all repositories |
| `GitHubSyncStateService` | class | `github_sync_state.dart` | Persistence service for sync state |

### Multi-Pack Search Types

| Name | Type | Location | Purpose |
|------|------|----------|---------|
| `MultiPackSearchHit` | class | `multi_pack_search_service.dart` | Search hit with source pack attribution |
| `MultiPackSearchResult` | class | `multi_pack_search_service.dart` | Merged search result with deduplication metadata |
| `MultiPackSearchService` | class | `multi_pack_search_service.dart` | Stateless service for cross-bundle search |

### BsdResolverService Extensions

| Name | Type | Location | Purpose |
|------|------|----------|---------|
| `RepoTreeEntry` | class | `bsd_resolver_service.dart` | Single file entry from GitHub Trees API |
| `RepoTreeResult` | class | `bsd_resolver_service.dart` | Complete tree fetch result with blob SHA map |
| `fetchRepoTree()` | method | `BsdResolverService` | Fetches repository tree with blob SHAs |

### ImportSessionController Extensions

| Name | Type | Location | Purpose |
|------|------|----------|---------|
| `selectedCatalogs` | `List<SelectedFile>` getter | `ImportSessionController` | Selected primary catalogs (max 3) |
| `indexBundles` | `Map<String, IndexBundle>` getter | `ImportSessionController` | Index bundles per selected catalog |
| `boundBundles` | `Map<String, BoundPackBundle>` getter | `ImportSessionController` | Bound bundles per selected catalog |
| `rawBundles` | `Map<String, RawPackBundle>` getter | `ImportSessionController` | Raw bundles per selected catalog |
| `setSelectedCatalogs()` | method | `ImportSessionController` | Sets all selected catalogs (replaces) |
| `addSelectedCatalog()` | method | `ImportSessionController` | Adds a catalog to selection |
| `removeSelectedCatalog()` | method | `ImportSessionController` | Removes a catalog by index |

### SearchScreen Extensions

| Name | Type | Location | Purpose |
|------|------|----------|---------|
| `indexBundles` | `Map<String, IndexBundle>?` param | `SearchScreen` | Multiple index bundles for multi-pack search |
| `bundleOrder` | `List<String>?` param | `SearchScreen` | Deterministic ordering for merge tie-breaks |
| `SearchScreen.single()` | factory | `SearchScreen` | Creates screen for single bundle |
| `SearchScreen.multi()` | factory | `SearchScreen` | Creates screen for multiple bundles |

---

## TrackedFile Fields

| Field | Type | Purpose |
|-------|------|---------|
| `repoPath` | `String` | Repository file path (e.g., "Imperium - Space Marines.cat") |
| `fileType` | `String` | File type: 'gst' or 'cat' |
| `rootId` | `String?` | Root ID extracted from file |
| `blobSha` | `String` | GitHub blob SHA for update detection |
| `localStoredPath` | `String?` | Local storage path (absolute) |
| `localFileId` | `String?` | Local file ID (SHA-256) for integrity |
| `lastCheckedAt` | `DateTime` | Last update check timestamp |

---

## SessionPackState Fields

| Field | Type | Purpose |
|-------|------|---------|
| `selectedPrimaryRootIds` | `List<String>` | User-selected primary catalog rootIds (max 3) |
| `dependencyRootIds` | `List<String>` | Auto-resolved dependency rootIds |
| `indexBuiltAt` | `DateTime?` | Timestamp when index was last built |

---

## RepoSyncState Fields

| Field | Type | Purpose |
|-------|------|---------|
| `repoUrl` | `String` | Repository URL |
| `branch` | `String` | Branch name |
| `trackedFiles` | `Map<String, TrackedFile>` | Tracked files keyed by repoPath |
| `lastTreeFetchAt` | `DateTime?` | Last GitHub tree fetch timestamp |

---

## MultiPackSearchHit Fields

| Field | Type | Purpose |
|-------|------|---------|
| `hit` | `SearchHit` | Original M10 search hit |
| `sourcePackKey` | `String` | Pack identifier for tie-breaking |
| `sourcePackIndex` | `int` | Pack index in session order |

---

## MultiPackSearchResult Fields

| Field | Type | Purpose |
|-------|------|---------|
| `hits` | `List<MultiPackSearchHit>` | Merged hits in deterministic order |
| `diagnostics` | `List<SearchDiagnostic>` | Merged diagnostics from all packs |
| `resultLimitApplied` | `bool` | Whether limit was applied after merge |
| `totalHitsBeforeLimit` | `int` | Total hits before limit |

---

## Multi-Pack Search Merge Algorithm

1. Run M10 search on each bundle
2. Merge hits into single list with pack attribution
3. Stable sort with tie-breaks: `docType → canonicalKey → docId → sourcePackKey`
4. Deduplicate by `docId` (prefer earlier pack order)
5. Apply limit after merge
6. Emit single `resultLimitApplied` diagnostic

---

## Deprecations

The following are deprecated but preserved for backward compatibility:

| Deprecated | Replacement | Location |
|------------|-------------|----------|
| `primaryCatalogFile` | `selectedCatalogs` | `ImportSessionController` |
| `rawBundle` | `rawBundles` | `ImportSessionController` |
| `boundBundle` | `boundBundles` | `ImportSessionController` |
| `indexBundle` | `indexBundles` | `ImportSessionController` |
| `setPrimaryCatalogFile()` | `setSelectedCatalogs()` | `ImportSessionController` |
| `SearchScreen.indexBundle` | `SearchScreen.indexBundles` | `SearchScreen` |

---

## File Locations

| File | Purpose |
|------|---------|
| `lib/services/github_sync_state.dart` | GitHub sync state types and persistence |
| `lib/services/multi_pack_search_service.dart` | Multi-pack search service |
| `lib/services/bsd_resolver_service.dart` | Extended with tree fetch methods |
| `lib/ui/import/import_session_controller.dart` | Extended with multi-catalog support |
| `lib/ui/search/search_screen.dart` | Extended with multi-bundle support |

---

## Approval Checklist

- [x] Names reviewed and approved (2026-02-17)
- [x] Glossary entries added (2026-02-17)
- [x] Name change log updated (2026-02-17)
- [x] Implementation may proceed

---

## Notes

- This proposal documents names that already exist in code from a prior implementation session
- Per Skills 13, documentation should have preceded code; this retroactively corrects that
- No new names may be added without updating this proposal first

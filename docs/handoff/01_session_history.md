# Session Handoff — History

**Date:** 2026-02-17
**Branch:** `claude/init-combat-goblin-context-eH9Ou`
**Last Commit:** `6f7408d docs(phase11b): mark names proposal as APPROVED`

---

## Session 3 — 2026-02-18

**Branch:** `claude/github-catalog-picker-Py9xI`
**Commits:** `484caa8`, `8b47baa`

### What Happened

#### 1. Icon Font Fix

All icons in the app were rendering as boxes-with-X. Root cause: `pubspec.yaml` was missing the `flutter: uses-material-design: true` flag, so the Material icon font was never bundled. Added the flag; no external icon pack required.

**File changed:** `pubspec.yaml` — added `flutter: uses-material-design: true`

#### 2. Dependency Pre-Fetch Before Slot Ready

Bug: when the user selected a catalog (e.g. `Tyranids.cat`), the slot would transition to `ready` without downloading its `catalogueLinks` dependencies (e.g. `Library - Tyranids`). The pipeline then discovered the missing deps, threw `AcquireFailure`, and `_autoResolveSlotDeps` attempted recovery — but this reactive cycle could leave deps undownloaded if rate-limited or if transitive deps were involved.

Fix: `assignCatalogToSlot` now runs `PreflightScanService.scanBytes` on the downloaded primary bytes immediately after fetch, extracts all `catalogueLinks` targetIds, and calls `_bsdResolver.fetchCatalogBytes` for any not already in `_resolvedDependencies`. The slot only transitions to `SlotStatus.ready` after all reachable deps have been cached. The `_autoResolveSlotDeps` path is preserved as a safety net.

**File changed:** `lib/ui/import/import_session_controller.dart`
- Added import for `preflight_scan_service.dart`
- Modified `assignCatalogToSlot` to pre-fetch deps before `SlotStatus.ready`

---

## What Happened in This Session (Session 2 — 2026-02-17)

### 1. Context Recovery

The session began by recovering context from prior sessions that had been interrupted by rate limits and errors. The project is **Combat Goblin Prime** — a deterministic Flutter/Dart data pipeline engine that transforms BattleScribe-format XML game data (.gst/.cat files) into a queryable search index through 10+ numbered modules (M1-M10).

### 2. Skills Audit & Documentation Compliance

Previous sessions had implemented code **without** creating required documentation first, violating Skills 01-03, 13. This session corrected that:

- **Created:** `docs/phases/phase_11b_multi_catalog_names_proposal.md` — formal names proposal
- **Updated:** `docs/glossary.md` — added 14 new Phase 11B term definitions
- **Updated:** `docs/name_change_log.md` — added 7 new name change entries
- **Marked proposal as APPROVED** by user

### 3. What Was Implemented (Prior Sessions + This One)

#### Code Already Committed (commits `d839f78` through `6f7408d`):

**a) Multi-Catalog Selection (`import_session_controller.dart`)**
- `selectedCatalogs: List<SelectedFile>` (max 3 primaries via `kMaxSelectedCatalogs`)
- `indexBundles: Map<String, IndexBundle>` — one per catalog
- `setSelectedCatalogs()`, `addSelectedCatalog()`, `removeSelectedCatalog()`
- Each catalog runs M1-M9 independently (no M1 unfreeze)
- Dependencies don't count toward 3-catalog limit
- Deprecated single-catalog accessors preserved for backward compat

**b) BsdResolverService Extensions (`bsd_resolver_service.dart`)**
- `RepoTreeEntry`, `RepoTreeResult` classes for blob SHA tracking
- `fetchRepoTree()` method — gets all .gst/.cat files with blob SHAs
- `RepoIndexResult` enhanced with `pathToBlobSha` and `targetIdToBlobSha`

**c) GitHub Sync State (`github_sync_state.dart`)**
- `TrackedFile` — file entry with blob SHA + local storage metadata
- `SessionPackState` — selected primaries + dependency closure
- `RepoSyncState` — per-repo sync state
- `GitHubSyncState` — complete sync across repos
- `GitHubSyncStateService` — persistence to `appDataRoot/github_sync_state.json`

**d) Multi-Pack Search (`multi_pack_search_service.dart`)**
- `MultiPackSearchService` — stateless cross-bundle search
- Merge algorithm: search each bundle → merge → stable sort (docType → canonicalKey → docId → sourcePackKey) → deduplicate by docId → apply limit
- `MultiPackSearchHit`, `MultiPackSearchResult` types

**e) UI Updates**
- `main.dart` — uses `controller.indexBundles` + `SearchScreen.multi()`
- `SearchScreen` — supports `indexBundles: Map<String, IndexBundle>` with factory constructors `.single()` and `.multi()`
- `FilePickerView` — multi-catalog card UI with add/remove controls
- `ImportWizardScreen` — aggregated stats in success view

**f) Tests**
- 38 tests passing in `import_session_controller_test.dart`
- Includes 13 multi-catalog tests
- All existing module tests unaffected

### 4. User's Key Architecture Decisions (from Phase 11B Review)

These decisions were made by the user and are **binding**:

1. **No M1 unfreeze** — Call M1 once per selected catalog; no engine changes
2. **Extend BsdResolverService** — No new parallel services
3. **Track both SHAs** — GitHub blob SHA for updates, local fileId (SHA-256) for storage
4. **3-catalog limit** — Primaries only; dependencies auto-resolved, don't count
5. **Per-file updates** — "Update All" re-downloads only changed files
6. **Separate sync state** — `github_sync_state.json`, not in M1 metadata
7. **Library files** — Auto-resolved as dependencies, not user-selectable
8. **Offline mode** — Must work offline once files + indexes built
9. **Deterministic merge** — Sort chain: docType → canonicalKey → docId → sourcePackKey

### 5. What Was NOT Implemented (Remaining Work)

The user's last request was: **"Implement the GitHub catalog picker."** Specific requirements gathered:

- **Replace local file picker** — GitHub picker becomes primary flow (local picker removed)
- **Auto-select .gst** — If repo has exactly 1 .gst, select it automatically
- **Auto-resolve dependencies** — Download selected files + all dependencies in one pass (since repo tree is already available)
- Need to get both .gst and .cat files from the repo on user selection
- Files should be downloaded locally and then ingested through the pipeline

This was NOT started. This is where the next session should resume.

### 6. Known Issues

- **"Did not boot to main screen"** — User reported app worked but no visible changes from multi-catalog feature. Root cause: the UI was wired to deprecated single-catalog APIs. This was fixed in commit `da3dfbe` (main.dart now uses `controller.indexBundles` + `SearchScreen.multi()`).
- **Mojibake** — Encoding corruption in data/text assets. Documented in `CODEX_TASKS.md` as post-M10 follow-up. Not investigated this session.
- **TODO at line ~1420** — `import_session_controller.dart`: dependency path tracking for session persistence is stubbed with empty map.

---

## File Change Summary (Session 2 — 2026-02-17)

| File | Change |
|------|--------|
| `docs/phases/phase_11b_multi_catalog_names_proposal.md` | Created, APPROVED |
| `docs/glossary.md` | +14 Phase 11B terms |
| `docs/name_change_log.md` | +7 name entries |
| `lib/services/github_sync_state.dart` | Created (prior session) |
| `lib/services/multi_pack_search_service.dart` | Created (prior session) |
| `lib/services/bsd_resolver_service.dart` | Extended with RepoTreeEntry/Result, fetchRepoTree() |
| `lib/ui/import/import_session_controller.dart` | Multi-catalog support |
| `lib/ui/import/widgets/file_picker_view.dart` | Multi-catalog card UI |
| `lib/ui/import/import_wizard_screen.dart` | Aggregated stats |
| `lib/ui/search/search_screen.dart` | Multi-bundle support |
| `lib/main.dart` | Updated to use indexBundles + SearchScreen.multi() |
| `test/ui/import/import_session_controller_test.dart` | 38 tests (13 new) |

## File Change Summary (Session 3 — 2026-02-18)

| File | Change |
|------|--------|
| `pubspec.yaml` | Added `flutter: uses-material-design: true` to fix broken icons |
| `lib/ui/import/import_session_controller.dart` | Pre-fetch catalogueLink deps in `assignCatalogToSlot` |

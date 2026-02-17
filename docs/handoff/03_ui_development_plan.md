# Session Handoff — UI Development Plan

**Date:** 2026-02-17
**Resume Point:** GitHub Catalog Picker implementation (not started)

---

## Current UI Architecture

```
main.dart
└── CombatGoblinApp (StatefulWidget)
    └── ImportSessionProvider (InheritedWidget, provides ImportSessionController)
        └── MaterialApp
            └── _AppNavigator (StatefulWidget)
                ├── ImportWizardScreen (when not in search mode)
                │   ├── FilePickerView (idle)
                │   ├── ImportProgressView (preparing/building)
                │   ├── DependencyResolutionView (resolvingDeps)
                │   ├── _buildSuccessView (success)
                │   └── _buildErrorView (failed)
                │
                └── SearchScreen.multi() (when indexBundles available)
```

### Key Files

| File | Path | Purpose |
|------|------|---------|
| App entry | `lib/main.dart` | Wires controller → navigator → screens |
| Controller | `lib/ui/import/import_session_controller.dart` | State management for import workflow |
| Provider | `lib/ui/import/import_session_provider.dart` | InheritedWidget for controller access |
| Wizard | `lib/ui/import/import_wizard_screen.dart` | Status-based view switching |
| File Picker | `lib/ui/import/widgets/file_picker_view.dart` | Local file selection cards |
| Progress | `lib/ui/import/widgets/import_progress_view.dart` | Loading indicator |
| Dep Resolution | `lib/ui/import/widgets/dependency_resolution_view.dart` | Missing dependency UI |
| Search | `lib/ui/search/search_screen.dart` | Multi-pack search UI |
| BSD Resolver | `lib/services/bsd_resolver_service.dart` | GitHub API integration |
| Sync State | `lib/services/github_sync_state.dart` | Blob SHA tracking |
| Multi-Pack Search | `lib/services/multi_pack_search_service.dart` | Cross-bundle search merge |
| Session Persistence | `lib/services/session_persistence_service.dart` | Session save/reload |
| Controller Tests | `test/ui/import/import_session_controller_test.dart` | 38 tests (all passing) |
| BSD Resolver Tests | `test/services/bsd_resolver_service_test.dart` | HTTP mocking tests |

---

## IMMEDIATE TASK: GitHub Catalog Picker

### User Requirements (Confirmed)

1. **Replace local file picker** — GitHub picker becomes the primary flow. Remove or hide `FilePickerView` with its local file selection cards.
2. **Auto-select .gst** — If the repo has exactly 1 `.gst` file, select it automatically. Show picker only if multiple `.gst` files exist.
3. **Auto-resolve dependencies** — After user selects catalog files, download all selected files PLUS all their dependencies in a single pass. No separate "resolve deps" step since the repo tree is already fetched.
4. **Download both .gst and .cat** — The app must download both file types from the repo.
5. **Downloaded files feed into existing pipeline** — Create `SelectedFile` objects from downloaded bytes and call `attemptBuild()`.

### Proposed Flow

```
Step 1: User enters GitHub repo URL
         (e.g., https://github.com/BSData/wh40k-10e)
         ↓
Step 2: App calls BsdResolverService.fetchRepoTree()
         → Gets all .gst and .cat files with blob SHAs
         ↓
Step 3: Auto-select .gst (if only 1)
         Show .gst picker only if multiple exist
         ↓
Step 4: Show catalog picker
         User selects up to 3 .cat files from list
         ↓
Step 5: App downloads selected files + auto-resolves dependencies
         Uses existing BsdResolverService._fetchFileContent()
         Builds repo index to identify dependency targetIds
         Downloads all in one pass
         ↓
Step 6: Creates SelectedFile objects from downloaded bytes
         Sets gameSystemFile + selectedCatalogs on controller
         ↓
Step 7: Calls controller.attemptBuild()
         Runs M1-M9 pipeline per catalog
         ↓
Step 8: Navigates to SearchScreen on success
```

### Implementation Steps (Detailed)

#### Step 1: Propose New Names (Skill 03/13 — MUST DO FIRST)

New names will be needed for the GitHub picker UI. Propose to user and get approval before writing any code. Likely names:

- Widget: Name TBD (e.g., `GitHubRepoBrowserView` or `RepoCatalogPickerView`)
- State enum: Name TBD for picker loading states
- Controller methods: Name TBD for `fetchAndSelectFromRepo()` or similar

**Action:** Update `docs/phases/phase_11b_multi_catalog_names_proposal.md` with new names, update glossary and name_change_log, get user approval.

#### Step 2: Add Controller Method for GitHub-Based Import

Add a new method to `ImportSessionController` that:
1. Takes a `SourceLocator` (repo URL)
2. Calls `BsdResolverService.fetchRepoTree()` to get all files
3. Returns the tree result for the UI to display
4. After user selection, downloads files and sets them as `SelectedFile` objects
5. Calls `attemptBuild()`

**Key design consideration:** The controller needs new state for "browsing repo" vs "files selected". This might be a new `ImportStatus` value or a separate state field. Need to decide:
- Option A: Add `ImportStatus.browsingRepo` enum value
- Option B: Separate `repoBrowserState` field on controller
- Option C: Keep repo browsing state entirely in the view widget

#### Step 3: Replace FilePickerView

Replace the current `FilePickerView` (which uses `FilePicker.platform.pickFiles()` for local files) with the GitHub repo browser.

The current `FilePickerView` at `lib/ui/import/widgets/file_picker_view.dart` contains:
- Repo URL text field (line 146-155) — KEEP THIS
- Local file picker cards — REPLACE with repo browser results
- "Reload Last Session" card — KEEP THIS (may need adjustment)
- Import button — MODIFY to trigger download + build

#### Step 4: Download Files from GitHub

Use existing `BsdResolverService` methods:
- `fetchRepoTree()` — already implemented, returns `RepoTreeResult` with blob SHAs
- `_fetchFileContent()` — private, needs to be exposed or wrapped in a public method
- `buildRepoIndex()` — builds targetId → path mapping for dependency resolution

**Need to expose:** A public method on `BsdResolverService` to download a file by repo path. Currently `_fetchFileContent()` is private. Either:
- Make it public as `fetchFileByPath(SourceLocator, String path) → Uint8List?`
- Or add a new public method

#### Step 5: Auto-Resolve Dependencies

After user selects their .cat files:
1. Already have the repo tree from Step 2
2. Already have the repo index from `buildRepoIndex()` (targetId → path mapping)
3. For each selected .cat, run M1 `buildBundle()` — it will report `missingTargetIds` via `AcquireFailure`
4. Since we have the full repo index, immediately download all missing deps
5. Retry `buildBundle()` with resolved deps

**Alternative (simpler):** Since we already have the repo index, pre-compute likely dependencies before even calling M1:
- Parse selected .cat files for `<catalogueLink>` elements
- Extract targetIds
- Resolve via repo index
- Download all before calling M1
This avoids the AcquireFailure round-trip.

#### Step 6: Update GitHubSyncState

After successful download and build:
1. Update `GitHubSyncState` with tracked files (blob SHAs, local paths)
2. Update `SessionPackState` with selected primaryRootIds and dependency closure
3. This enables future "Check Updates" functionality

#### Step 7: Wire Navigation

Update `ImportWizardScreen._buildBody()` to handle the new flow:
- `ImportStatus.idle` → Show GitHub repo browser (replaces FilePickerView)
- New status or state for "loading repo tree" → Show loading indicator
- New status or state for "user selecting catalogs" → Show catalog picker list
- `ImportStatus.preparing` → "Downloading files..."
- Rest of flow unchanged

#### Step 8: Tests

- Add tests for the new controller method(s)
- Mock HTTP responses for `fetchRepoTree()` and file downloads
- Test auto-.gst selection logic
- Test dependency auto-resolution
- Test error states (network failure, rate limit, empty repo)

---

## Existing Infrastructure to Reuse

| What | Where | How |
|------|-------|-----|
| GitHub Trees API fetch | `BsdResolverService.fetchRepoTree()` | Returns `RepoTreeResult` with all .gst/.cat files and blob SHAs |
| Repo index building | `BsdResolverService.buildRepoIndex()` | Maps targetId → repo path for dep resolution |
| File download | `BsdResolverService._fetchFileContent()` | Downloads full file bytes (needs to be made public) |
| Partial fetch for rootId | `BsdResolverService._extractCatalogId()` | Range-header fetch for parsing catalogue id |
| Rate limit handling | `BsdResolverService._handleErrorResponse()` | Detects 403/429 and exposes `lastError` |
| Auth token | `BsdResolverService.setAuthToken()` | Already wired to controller and UI |
| Multi-catalog pipeline | `ImportSessionController.attemptBuild()` | Runs M1-M9 per catalog, stores IndexBundles |
| Sync state persistence | `GitHubSyncStateService` | Saves blob SHAs and session pack state |

---

## Questions to Ask User Before Coding

1. **New widget name** — What should the GitHub repo browser widget be called? (Skill 03 requires approval)
2. **Repo URL default** — Should there be a default repo URL (e.g., `https://github.com/BSData/wh40k-10e`)? Or always require user input?
3. **Catalog display** — Show just filenames (e.g., "Imperium - Space Marines.cat") or also show extracted rootIds?
4. **Error UX** — If downloading 1 of 5 files fails mid-download, should the whole flow fail, or continue with partial results?
5. **Token prompt** — If rate limit is hit during tree fetch, should the UI immediately prompt for PAT, or show error with manual option?

---

## Architecture Constraints (Binding)

These are user decisions that CANNOT be changed without explicit re-approval:

- **No M1 unfreeze** — Each catalog runs M1 independently
- **Extend BsdResolverService** — Do NOT create new parallel services
- **Track both SHAs** — Blob SHA for updates, fileId for storage
- **3-catalog limit** — Primaries only; dependencies auto-resolved
- **Per-file updates** — Not full re-download
- **Separate sync state** — `github_sync_state.json`, not in M1 metadata
- **GitHub picker replaces local picker** — User decision from this session
- **Auto-select .gst if only one** — User decision from this session
- **Auto-resolve deps in one pass** — User decision from this session

---

## File Tree (What Exists vs What's Needed)

```
lib/
├── main.dart                                    ✅ EXISTS (wired to multi-catalog)
├── modules/                                     ✅ ALL FROZEN
├── services/
│   ├── bsd_resolver_service.dart                ✅ EXISTS (needs fetchFileByPath public method)
│   ├── github_sync_state.dart                   ✅ EXISTS
│   ├── multi_pack_search_service.dart           ✅ EXISTS
│   └── session_persistence_service.dart         ✅ EXISTS
└── ui/
    ├── import/
    │   ├── import_session_controller.dart        ✅ EXISTS (needs GitHub import method)
    │   ├── import_session_provider.dart          ✅ EXISTS
    │   ├── import_wizard_screen.dart             ✅ EXISTS (needs updated status routing)
    │   └── widgets/
    │       ├── file_picker_view.dart             ❌ REPLACE with GitHub repo browser
    │       ├── import_progress_view.dart         ✅ EXISTS
    │       └── dependency_resolution_view.dart   ⚠️ MAY NOT BE NEEDED (deps auto-resolved)
    └── search/
        └── search_screen.dart                   ✅ EXISTS

test/
├── ui/import/
│   └── import_session_controller_test.dart      ✅ EXISTS (38 tests, needs new tests)
└── services/
    └── bsd_resolver_service_test.dart           ✅ EXISTS (needs new tests)
```

---

## Resume Checklist for Next Session

1. [ ] Read `skills/README.md` to load behavioral contract
2. [ ] Read `docs/phases/phase_11b_multi_catalog_names_proposal.md` (APPROVED)
3. [ ] Read this file (`docs/handoff/03_ui_development_plan.md`)
4. [ ] Propose new names for GitHub picker widget and controller methods → get user approval
5. [ ] Update glossary and name_change_log with approved names
6. [ ] Implement GitHub catalog picker (replace `FilePickerView`)
7. [ ] Expose `fetchFileByPath()` on BsdResolverService
8. [ ] Add controller method for GitHub-based import flow
9. [ ] Wire auto-.gst selection and auto-dep resolution
10. [ ] Update GitHubSyncState after successful downloads
11. [ ] Add tests
12. [ ] Run `flutter analyze` and `flutter test` — all must pass
13. [ ] Commit and push

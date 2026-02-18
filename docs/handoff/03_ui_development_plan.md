# Session Handoff — UI Development Plan

**Last Updated:** 2026-02-18
**Branch:** `claude/github-catalog-picker-Py9xI`

---

## Current UI Architecture

```
main.dart
└── CombatGoblinApp (StatefulWidget)
    └── ImportSessionProvider (InheritedWidget, provides ImportSessionController)
        └── MaterialApp
            └── AppShell (StatefulWidget — navigation drawer)
                ├── HomeScreen   (index 0) — search bar + results + slot status chips
                └── DownloadsScreen (index 1) — GitHub repo picker + slot panels
```

### Key Files

| File | Path | Purpose |
|------|------|---------|
| App entry | `lib/main.dart` | Bootstraps controller, wires persistence + update check |
| Controller | `lib/ui/import/import_session_controller.dart` | All session state (slots, deps, build status) |
| Provider | `lib/ui/import/import_session_provider.dart` | InheritedWidget for controller access |
| App Shell | `lib/ui/app_shell.dart` | Navigation drawer + AppBar with update badge |
| Home Screen | `lib/ui/home/home_screen.dart` | Search bar, results list, slot status chips |
| Downloads Screen | `lib/ui/downloads/downloads_screen.dart` | GitHub repo URL, game system selector, slot panels |
| BSD Resolver | `lib/services/bsd_resolver_service.dart` | GitHub API integration |
| Sync State | `lib/services/github_sync_state.dart` | Blob SHA tracking for update checks |
| Multi-Pack Search | `lib/services/multi_pack_search_service.dart` | Cross-bundle search aggregation |
| Session Persistence | `lib/services/session_persistence_service.dart` | Session save/restore |

---

## Downloads Screen Flow (IMPLEMENTED)

```
Step 1: User enters GitHub repo URL in DownloadsScreen
         ↓
Step 2: Tap "Fetch" → controller.loadRepoCatalogTree()
         → BsdResolverService.fetchRepoTree() returns RepoTreeResult
         → UI shows .gst file list + .cat file list
         ↓
Step 3: User taps a .gst file → controller.fetchAndSetGameSystem()
         → Downloads .gst bytes, stores as gameSystemFile
         ↓
Step 4: User picks a .cat from a slot panel → controller.assignCatalogToSlot()
         → Downloads primary .cat bytes
         → PreflightScanService scans bytes for catalogueLinks
         → Fetches all missing dependency targetIds via BsdResolverService.fetchCatalogBytes()
         → Slot transitions to SlotStatus.ready (with all deps pre-cached)
         ↓
Step 5: User taps "Load" (or "Load All Ready Slots")
         → controller.loadSlot() runs M2-M9 pipeline
         → All deps already in _resolvedDependencies cache → no AcquireFailure
         → Slot transitions to SlotStatus.loaded with IndexBundle
         ↓
Step 6: HomeScreen slot chips show loaded catalogs
         Search is available immediately
```

### Slot Lifecycle

```
empty → fetching (primary + deps downloading) → ready → building → loaded
                                                   ↓                  ↓
                                                 error              error
```

`SlotStatus.fetching` covers both the primary `.cat` download and the dependency
pre-fetch. `_autoResolveSlotDeps` remains as a safety net if pre-fetch partially
fails (rate limit, network error).

---

## Per-Slot State (`SlotState`)

| Field | Type | Populated when |
|-------|------|----------------|
| `status` | `SlotStatus` | Always |
| `catalogPath` | `String?` | After assign |
| `catalogName` | `String?` | After assign |
| `sourceLocator` | `SourceLocator?` | After assign |
| `fetchedBytes` | `Uint8List?` | After fetch success |
| `errorMessage` | `String?` | On error |
| `missingTargetIds` | `List<String>` | On AcquireFailure (safety net path) |
| `indexBundle` | `IndexBundle?` | After pipeline success |

---

## Architecture Constraints (Binding)

These are user decisions that CANNOT be changed without explicit re-approval:

- **No M1 unfreeze** — Each catalog runs M1 independently
- **Extend BsdResolverService** — Do NOT create new parallel services
- **Track both SHAs** — Blob SHA for updates, fileId for storage
- **2-catalog limit** — `kMaxSelectedCatalogs = 2` (demo limit)
- **Per-file updates** — Not full re-download
- **Separate sync state** — `github_sync_state.json`, not in M1 metadata
- **GitHub picker is the primary flow** — No local file picker
- **Auto-resolve deps in slot fetch** — Pre-fetched before `SlotStatus.ready`

---

## File Tree (Current State)

```
lib/
├── main.dart                                    ✅ Bootstraps controller + session restore
├── modules/                                     ✅ ALL FROZEN (M1-M10)
├── services/
│   ├── bsd_resolver_service.dart                ✅ fetchRepoTree, fetchCatalogBytes, fetchFileByPath
│   ├── github_sync_state.dart                   ✅ Blob SHA tracking
│   ├── multi_pack_search_service.dart           ✅ Cross-bundle search merge
│   └── session_persistence_service.dart         ✅ Session save/restore
└── ui/
    ├── app_shell.dart                           ✅ Nav drawer + update badge
    ├── home/
    │   └── home_screen.dart                     ✅ Search + slot status chips
    ├── downloads/
    │   └── downloads_screen.dart                ✅ GitHub picker + slot panels
    └── import/
        ├── import_session_controller.dart        ✅ All session state
        └── import_session_provider.dart          ✅ InheritedWidget accessor

test/
├── ui/import/
│   └── import_session_controller_test.dart      ✅ 38 tests (passing)
└── services/
    └── bsd_resolver_service_test.dart           ✅ HTTP mocking tests
```

---

## Known Issues / Remaining Work

| Item | Priority | Notes |
|------|----------|-------|
| Dependency path tracking in session persistence | Low | `_saveSession()` passes empty `dependencyPaths: {}` |
| Transitive dependencies (deps-of-deps) | Medium | Pre-fetch only reads primary catalog's `catalogueLinks`; deps' own deps not scanned |
| Mojibake in data/text assets | Low | Documented in `CODEX_TASKS.md`, post-M10 |
| Tests for `assignCatalogToSlot` dep pre-fetch | Medium | New behavior has no unit test coverage yet |

---

## Resume Checklist for Next Session

1. [ ] Read `skills/README.md` to load behavioral contract
2. [ ] Read this file (`docs/handoff/03_ui_development_plan.md`)
3. [ ] Run `flutter analyze` and `flutter test` to confirm baseline
4. [ ] Address remaining work items above as directed by user

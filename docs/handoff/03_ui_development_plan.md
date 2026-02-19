# Session Handoff — UI Development Plan

**Last Updated:** 2026-02-19
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
                └── DownloadsScreen (index 1) — repo URL + game system + slot panels
                    └── FactionPickerScreen (pushed route, per slot)
```

### Key Files

| File | Path | Purpose |
|------|------|---------|
| App entry | `lib/main.dart` | Bootstraps controller, wires persistence + update check |
| Controller | `lib/ui/import/import_session_controller.dart` | All session state (slots, deps, build status) |
| Provider | `lib/ui/import/import_session_provider.dart` | InheritedWidget for controller access |
| App Shell | `lib/ui/app_shell.dart` | Navigation drawer + AppBar with update badge |
| Home Screen | `lib/ui/home/home_screen.dart` | Search bar, results list, slot status chips |
| Downloads Screen | `lib/ui/downloads/downloads_screen.dart` | Repo URL, game system selector, slot panels |
| Faction Picker Screen | `lib/ui/downloads/faction_picker_screen.dart` | Searchable faction picker for a slot |
| BSD Resolver | `lib/services/bsd_resolver_service.dart` | GitHub API integration |
| Sync State | `lib/services/github_sync_state.dart` | Blob SHA tracking for update checks |
| Multi-Pack Search | `lib/services/multi_pack_search_service.dart` | Cross-bundle search aggregation |
| Session Persistence | `lib/services/session_persistence_service.dart` | Session save/restore |

---

## Downloads Screen Flow (IMPLEMENTED — Phase 11D)

```
App mount → DownloadsScreen.initState
         → auto-fetch https://github.com/BSData/wh40k-10e
         → If 1 .gst found: auto-download game system
         ↓
User taps Slot 1 or Slot 2 → FactionPickerScreen opens
         → Filter field + faction list
         → Currently loaded faction highlighted with check
         ↓
User taps a faction → loadFactionIntoSlot(slot, faction, locator)
         → Downloads primary .cat bytes
         → Pre-flight scan → fetch catalogueLink deps
         → Slot transitions: fetching → ready
         → Immediately calls loadSlot() → building → loaded
         → FactionPickerScreen pops
         ↓
HomeScreen slot chips show "Tyranids", "Necrons", etc.
Search is immediately available.
```

### Slot Lifecycle

```
empty → fetching (primary + deps) → [ready] → building → loaded
                                                  ↓          ↓
                                                error      error
```

`[ready]` is transient when game system is available (immediately continues to building).
Stays at `ready` only if game system is not yet set — then manual "Load" button appears.

---

## Faction Picker Behaviour

- **Highlight-and-replace**: Currently loaded faction highlighted with `Icons.check_circle`.
  Tapping another faction replaces the slot — no second confirmation.
- **Filter field**: Substring match on `displayName` (case-insensitive).
- **Library deps**: Shown as a subtitle ("Includes: Library - Tyranids") — informational only.
  Actual dep download is driven by catalogueLinks pre-flight scan, not the `libraryPaths` list.
- **Clear Slot**: Available as AppBar action; calls `clearSlot(slot)` and pops.

---

## Per-Slot State (`SlotState`)

| Field | Type | Populated when |
|-------|------|----------------|
| `status` | `SlotStatus` | Always |
| `catalogPath` | `String?` | After assign |
| `catalogName` | `String?` | After assign — now faction `displayName` (e.g. "Tyranids") |
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
- **Highlight-and-replace** — No second confirmation when tapping a faction in picker

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
    │   └── home_screen.dart                     ✅ Search + slot status chips + game system name
    ├── downloads/
    │   ├── downloads_screen.dart                ✅ Repo URL (read-only+Change), auto-fetch, slot panels
    │   └── faction_picker_screen.dart           ✅ Faction list, filter, highlight-and-replace
    └── import/
        ├── import_session_controller.dart        ✅ FactionOption, availableFactions(),
        │                                            loadFactionIntoSlot(), gameSystemDisplayName,
        │                                            cachedRepoTree
        └── import_session_provider.dart          ✅ InheritedWidget accessor

test/
├── ui/import/
│   └── import_session_controller_test.dart      ✅ 80 tests (all passing)
└── services/
    └── bsd_resolver_service_test.dart           ✅ HTTP mocking tests
```

---

## Known Issues / Remaining Work

| Item | Priority | Notes |
|------|----------|-------|
| Transitive dependencies (deps-of-deps) | Medium | Pre-fetch only reads primary catalog's `catalogueLinks`; deps' own deps not scanned |
| Dependency path tracking in session persistence | Low | `_saveSession()` passes empty `dependencyPaths: {}` |
| Tests for `loadFactionIntoSlot` | Medium | New behaviour has no unit test coverage yet |
| Mojibake in data/text assets | Low | Documented in `CODEX_TASKS.md`, post-M10 |
| Repo URL not persisted across sessions | Low | User must re-fetch on next cold start (default URL auto-fetches) |

---

## Resume Checklist for Next Session

1. [ ] Read `skills/README.md` to load behavioural contract
2. [ ] Read this file (`docs/handoff/03_ui_development_plan.md`)
3. [ ] Run `flutter analyze --no-fatal-infos` and `flutter test` to confirm baseline (80 tests)
4. [ ] Address remaining work items above as directed by user

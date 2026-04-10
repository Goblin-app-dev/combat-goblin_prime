# Combat Goblin Prime — Session Handoff Document
**Date:** 2026-04-10
**Prepared for:** New Claude Code instance (performance handoff)
**Branch:** `claude/github-catalog-picker-Py9xI`
**Working Directory:** `/home/user/combat-goblin_prime`

---

## FIRST ACTIONS FOR NEW INSTANCE

Before doing anything else, run these in order:

```bash
# 1. Confirm branch
git branch --show-current
# Expected: claude/github-catalog-picker-Py9xI

# 2. Confirm baseline
flutter test
# Expected: all tests pass (check count — was ~80+ last session)

# 3. Check uncommitted work
git status
git diff
```

Then read these documents IN ORDER (mandatory per skill_01):
1. `skills/README.md` — the governance contract; read this first
2. `docs/handoff/02_skills_and_rules_reference.md` — quick rules reference
3. `docs/handoff/03_ui_development_plan.md` — current UI architecture
4. `docs/handoff/01_session_history.md` — full session history
5. `docs/phases/phase_12_voice_integration_proposal.md`
6. `docs/phases/phase_12d_voice_understanding_proposal.md`
7. `docs/phases/phase_12e_spoken_output_proposal.md` (now replaced — see below)

After reading, give the user a full status update covering all sections in this document.

---

## PROJECT IDENTITY

**Name:** `combat_goblin_prime`
**Description:** Deterministic multi-phase data pipeline engine for structured game system processing
**Language:** Flutter/Dart (SDK `>=3.0.0 <4.0.0`)
**Domain:** Warhammer 40,000 10th Edition army builder / BattleScribe XML data processing
**Data Source:** [BSData/wh40k-10e](https://github.com/BSData/wh40k-10e) (30 faction catalogs)

---

## MANDATORY SKILL SYSTEM (14 Skills — ALL BINDING)

Skills live in `/skills/`. These are **non-negotiable governance rules**, not suggestions.

| # | File | Rule |
|---|------|------|
| 01 | `skill_01_read_before_write.md` | Read existing code/docs before any action |
| 02 | `skill_02_single_source_of_truth_for_names.md` | Names defined in one place only |
| 03 | `skill_03_no_new_names_without_permission.md` | Cannot invent identifiers without approval |
| 04 | `skill_04_no_silent_renames.md` | All renames logged in `name_change_log.md` |
| 05 | `skill_05_full_file_output_only.md` | Output full files, no partial snippets |
| 06 | `skill_06_module_boundary_integrity.md` | No crossing module boundaries |
| 07 | `skill_07_module_io_accountability.md` | No hidden data flow |
| 08 | `skill_08_phase_freeze_discipline.md` | Frozen modules locked — no changes without explicit unfreeze |
| 09 | `skill_09_copyright_guardrail.md` | No copyrighted game content in code |
| 10 | `skill_10_deterministic_behavior.md` | Same input → same output, always |
| 11 | `skill_11_debug_visibility.md` | Failures must be explainable |
| 12 | `skill_12_stop_when_uncertain.md` | STOP and ask if unsure — do not assume |
| 13 | `skill_13_naming_docs_are_authoritative_and_mutable.md` | Docs updated BEFORE code |
| 14 | `skill_14_single_game_system_only.md` | Single game system per session |

### Mandatory Workflow Order (NEVER reverse this)
```
Design intent
    ↓
Naming docs updated (glossary + name_change_log)
    ↓
Explicit user approval
    ↓
Code written using approved names
```

---

## FROZEN MODULES (DO NOT TOUCH without explicit unfreeze approval)

| Module | Phase | Frozen Since |
|--------|-------|-------------|
| M1 Acquire | 1A | 2026-02-03 |
| M2 Parse | 1B | 2026-02-03 |
| M3 Wrap | 1C | 2026-02-04 |
| M4 Link | 2 | 2026-02-05 |
| M5 Bind | 3 | 2026-02-10 |
| M6 Evaluate | 4 | 2026-02-11 |
| M7 Applicability | 5 | 2026-02-12 |
| M8 Modifiers | 6 | 2026-02-12 |
| Orchestrator v1 | — | 2026-02-12 |
| M9 Index-Core | — | 2026-02-13 |
| M10 Structured Search | 11 | 2026-02-13 |

**Key principle:** M1 is frozen. Multi-catalog support calls M1 once per catalog — no contract changes. This is a binding user decision.

---

## PIPELINE ARCHITECTURE

```
Source Files (.gst / .cat)
    ↓
M1 Acquire → M2 Parse → M3 Wrap → M4 Link → M5 Bind
                                                  ↓
                          ← M8 Modifiers ← M7 Applicability
                                  ↓
                    Orchestrator → M9 Index → M10 Structured Search
```

**Multi-catalog (Phase 11B):** Each selected catalog runs this full pipeline independently → produces its own `IndexBundle`. UI layer merges via `MultiPackSearchService`. Max 2 catalogs (`kMaxSelectedCatalogs = 2`).

---

## CURRENT UI ARCHITECTURE

```
main.dart
└── CombatGoblinApp (StatefulWidget)
    └── ImportSessionProvider (InheritedWidget)
        └── MaterialApp
            └── AppShell (nav drawer + AppBar update badge)
                ├── HomeScreen    — search bar + results + slot status chips
                └── DownloadsScreen — repo URL + game system + slot panels
                    └── FactionPickerScreen — per-slot faction selector (pushed route)
```

### Key Files

| Purpose | Path |
|---------|------|
| App entry | `lib/main.dart` |
| All session state | `lib/ui/import/import_session_controller.dart` |
| InheritedWidget accessor | `lib/ui/import/import_session_provider.dart` |
| Nav shell | `lib/ui/app_shell.dart` |
| Search + status | `lib/ui/home/home_screen.dart` |
| Repo + slots | `lib/ui/downloads/downloads_screen.dart` |
| Faction picker | `lib/ui/downloads/faction_picker_screen.dart` |
| GitHub API | `lib/services/bsd_resolver_service.dart` |
| Blob SHA tracking | `lib/services/github_sync_state.dart` |
| Cross-bundle search | `lib/services/multi_pack_search_service.dart` |
| Session save/restore | `lib/services/session_persistence_service.dart` |

---

## VOICE SYSTEM (Phase 12)

Voice integration is in `lib/voice/`. Key subdirectories:

| Directory | Purpose |
|-----------|---------|
| `adapters/` | Platform audio adapters |
| `models/` | Voice domain models |
| `runtime/` | Audio session runtime |
| `services/` | KWS (keyword spotting) + ASR (speech recognition) via Sherpa ONNX |
| `settings/` | Voice configuration |
| `understanding/` | Intent parsing + disambiguation + name resolution |
| `voice_search_facade.dart` | Unified voice-to-search entry point |

### Phase 12 Status

| Phase | Status |
|-------|--------|
| 12A Voice Seam Extraction | COMPLETE |
| 12B Audio Runtime | COMPLETE |
| 12C Platform Audio | COMPLETE |
| 12D Voice Understanding | IN PROGRESS (see uncommitted work below) |
| 12E Spoken Output (TTS) | Phase doc REPLACED — see commit `c8437de` |

**Phase 12E note:** The original spoken output proposal was replaced with a "Voice Usability Design Guide" in commit `c8437de`. Read the current `docs/phases/phase_12e_spoken_output_proposal.md` (or whatever file replaced it) to understand current intent before acting on TTS.

---

## UNCOMMITTED WORK (MUST HANDLE FIRST)

There is **one modified file** not yet committed:

```
modified: lib/voice/understanding/voice_intent_classifier.dart
```

**Change summary:** The `_questionPrefixes` list was expanded with additional question trigger strings:
- `"what's "`, `"whats "` — stat queries with contraction
- `"how far"` — movement queries
- `"rules for"`, `"rules of"` — rule/ability queries
- `"abilities of"`, `"abilities for"` — ability queries
- `"which units"`, `"what units"` — cross-unit ability queries
- `"show "`, `"tell me"`, `"describe "` — general question words
- `"how many"`, `"how much"`, `"does it"`, `"can it"` — boolean/count queries
- `"list "`, `"get info"`, `"abilities"`, `"stats"`, `"info "`, `"info about"` — info queries

**Action needed:** Ask the user whether to commit this change as-is, modify it, or discard it before starting new work.

---

## GIT STATE

**Branch:** `claude/github-catalog-picker-Py9xI`
**Remote:** `origin/claude/github-catalog-picker-Py9xI` (up to date as of last push)

### Recent Commits (newest first)

| Hash | Message |
|------|---------|
| `c8437de` | Replace Phase 12E doc with Voice Usability Design Guide |
| `21fde1e` | Add missing faction aliases: imperial agents and votann |
| `4204458` | feat(voice): name resolution + entity selection (V1 blockers) |
| `3e92e5a` | Add CanonicalNameResolver for BSData-compatible query normalization |
| `990feba` | test(Q1): correct BS data path + add coordinator integration coverage |
| `80e9f6d` | test(sweep): faction sweep validation across all 30 BSData wh40k-10e catalogs |
| `6efcaae` | chore(test): add faction sweep test stub and downloaded catalog fixtures |
| `a8b22b2` | test(validation): fix AOI leakage check |
| `c59ec60` | Update audit dump outputs from baseline test run |
| `6f912f3` | Add Leagues of Votann fixture and refresh Agents of the Imperium fixture |

### Git Push Instructions
- Always: `git push -u origin claude/github-catalog-picker-Py9xI`
- On network failure: retry up to 4× with exponential backoff (2s, 4s, 8s, 16s)

---

## KNOWN OUTSTANDING ISSUES

### Priority Items

| Item | Location | Notes |
|------|----------|-------|
| Uncommitted voice classifier changes | `lib/voice/understanding/voice_intent_classifier.dart` | Ask user before committing |
| V1 answer-layer blocker (Q1) | `docs/v1_correctness_report.md` | Attribute question routing (e.g. "BS of unit X") requires `_handleAttributeQuestion()` to query weapon profiles |
| V1 entity resolution | `docs/v1_correctness_report.md` | Canonical-key lookup, not raw search position |

### Low-Priority / Tracked

| Item | Location | Notes |
|------|----------|-------|
| Mojibake in data/text assets | `CODEX_TASKS.md` | Post-M10 follow-up; encoding corruption investigation |
| Dependency path tracking | `import_session_controller.dart` ~line 1420 | TODO — `_saveSession()` passes empty `dependencyPaths: {}` |
| Transitive deps (deps-of-deps) | `import_session_controller.dart` | Pre-fetch only reads primary `catalogueLinks`; dep's own deps not scanned |
| Tests for `loadFactionIntoSlot` / `availableFactions` | `test/ui/import/` | No unit test coverage yet |
| Repo URL not persisted | `downloads_screen.dart` | Default URL auto-fetches on cold start |
| Game system SHA not persisted | `downloads_screen.dart` | `_gstLoadedBlobSha` is view-local |

---

## AUTHORITATIVE NAMING DOCUMENTS

These are the **single source of truth** for all identifiers. Read before any code change:

| Document | Path | Purpose |
|----------|------|---------|
| Glossary | `docs/glossary.md` | Definitions for every public concept (~50KB) |
| Name Change Log | `docs/name_change_log.md` | All renames/deprecations (~40KB) |
| Naming Contract | `docs/naming_contract.md` | Naming conventions |
| Module IO Registry | `docs/module_io_registry.md` | Inputs/outputs for every module (~26KB) |

---

## BINDING ARCHITECTURE DECISIONS (Cannot change without user re-approval)

1. **No M1 unfreeze** — multi-catalog calls M1 once per catalog
2. **Extend BsdResolverService** — do NOT create new parallel services
3. **Track both SHAs** — GitHub blob SHA for updates, SHA-256 fileId for storage
4. **2-catalog limit** — `kMaxSelectedCatalogs = 2` (demo limit)
5. **Per-file updates** — not full re-download
6. **Separate sync state** — `github_sync_state.json`, not embedded in M1 metadata
7. **GitHub picker is primary flow** — no local file picker
8. **Auto-resolve deps in slot fetch** — pre-fetched before `SlotStatus.ready`
9. **Highlight-and-replace** — no second confirmation when selecting faction
10. **No engine changes** — no semantic merge of symbol tables, no cross-catalog linking

---

## PROJECT STATISTICS

- **174** Dart source files in `lib/`
- **43** test files with comprehensive coverage
- **~80+** tests (all expected to pass)
- **10** frozen modules (M1–M10 + Orchestrator)
- **50+** documentation files
- **14** mandatory development skills

---

## ENVIRONMENT

- **Flutter SDK:** Stable channel, auto-installed by SessionStart hook
- **Platform:** Linux 6.18.5
- **SessionStart hook:** `.claude/hooks/session-start.sh` — runs `flutter pub get` automatically
- **No manual setup needed** in remote sessions

---

## HOW TO GIVE THE USER A STATUS UPDATE

After reading all docs above, report on:
1. Current phase of development (Phase 12D in progress)
2. Uncommitted changes and what to do with them
3. Test baseline (run `flutter test` and report count/result)
4. Outstanding known issues (see table above)
5. What the user should prioritize next
6. Any questions before proceeding

**Then wait for user direction. Do not assume what to implement next.**

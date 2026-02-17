# Session Handoff — Skills & Rules Reference

**Date:** 2026-02-17

---

## Mandatory Workflow

Every change MUST follow this order. Reverse order is forbidden.

```
Design intent
↓
Naming docs updated (glossary / name_change_log)
↓
Explicit user approval
↓
Code written using approved names
```

---

## Skills Location

All skills are in `/skills/` directory. **Read `skills/README.md` first** — it explains how the 14 skills work together.

---

## Skills Quick Reference

### Documentation-First Cluster (MUST read before any code change)

| Skill | File | One-Line Rule |
|-------|------|---------------|
| 01 | `skill_01_read_before_write.md` | Read existing code and docs before acting |
| 02 | `skill_02_single_source_of_truth_for_names.md` | Names exist in one authoritative place |
| 03 | `skill_03_no_new_names_without_permission.md` | You may NOT invent identifiers without approval |
| 13 | `skill_13_naming_docs_are_authoritative_and_mutable.md` | New/changed names must be written to docs BEFORE code |

### No-Drift Cluster (Prevents silent breakage)

| Skill | File | One-Line Rule |
|-------|------|---------------|
| 04 | `skill_04_no_silent_renames.md` | Renaming is logged in `name_change_log.md` |
| 08 | `skill_08_phase_freeze_discipline.md` | Frozen modules cannot change without explicit approval |

### Mechanical Safety

| Skill | File | One-Line Rule |
|-------|------|---------------|
| 05 | `skill_05_full_file_output_only.md` | Prevents copy/paste and context loss |
| 06 | `skill_06_module_boundary_integrity.md` | No crossing module boundaries |
| 07 | `skill_07_module_io_accountability.md` | No hidden data flow or leaky abstractions |

### Determinism & Safety

| Skill | File | One-Line Rule |
|-------|------|---------------|
| 09 | `skill_09_copyright_guardrail.md` | No copyrighted content in code |
| 10 | `skill_10_deterministic_behavior.md` | Same input → same output |
| 11 | `skill_11_debug_visibility.md` | Failures must be explainable |
| 12 | `skill_12_stop_when_uncertain.md` | If unsure, STOP and ask |
| 14 | `skill_14_single_game_system_only.md` | Single game system per session |

---

## Authoritative Naming Documents

These are the **single source of truth** for all names. Read before modifying any public API.

| Document | Path | Purpose |
|----------|------|---------|
| Glossary | `docs/glossary.md` | Definitions for every public concept |
| Name Change Log | `docs/name_change_log.md` | All renames and deprecations |
| Naming Contract | `docs/naming_contract.md` | Naming conventions |
| Module IO Registry | `docs/module_io_registry.md` | Inputs/outputs for every module |

---

## Frozen Modules (DO NOT MODIFY without explicit unfreeze approval)

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

**Key implication for Phase 11B:** M1 is frozen. The multi-catalog approach calls M1 once per catalog — no M1 contract changes. This was an explicit user decision.

---

## Phase Documentation

Per-phase proposals live in `docs/phases/`. Current Phase 11B:

- `docs/phases/phase_11b_multi_catalog_names_proposal.md` — **APPROVED**

---

## Pipeline Architecture

```
Source Files → M1 Acquire → M2 Parse → M3 Wrap → M4 Link → M5 Bind
                                                                ↓
                                    ← M8 Modifiers ← M7 Applicability
                                            ↓
                      Orchestrator → M9 Index → M10 Structured Search
```

For Phase 11B multi-catalog: each selected catalog runs this pipeline independently, producing its own `IndexBundle`. The UI layer merges search results across bundles via `MultiPackSearchService`.

---

## Key Design Principle

> "No engine changes. No semantic merge of symbol tables. No cross-catalog linking assumptions."
> — User's binding decision on multi-catalog architecture

Each catalog is an independent "pack" with its own pipeline run. Search merging happens at the UI layer only.

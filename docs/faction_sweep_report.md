# Faction Sweep Validation Report

Generated: 2026-04-06  
Test file: `test/faction_sweep_test.dart`  
Sweep method: Sequential M1→M9 pipeline load for each faction, then P2–P5 validation  
Pipeline: M1 Acquire → M2 Parse → M3 Wrap → M4 Link → M5 Bind → M9 Index → M10 Search

---

## Section 1 — Coverage Summary

### Previously tested (excluded from sweep)
- Space Marines
- Tyranids
- Leagues of Votann
- Imperial Agents

### Newly tested in this sweep: 30 factions

| Group | Factions |
|-------|---------|
| Aeldari | Craftworlds, Drukhari, Ynnari |
| Chaos | Chaos Daemons, Chaos Knights, Chaos Space Marines, Death Guard, Emperor's Children, Thousand Sons, World Eaters |
| Genestealer Cults | Genestealer Cults |
| Imperium | Adepta Sororitas, Adeptus Custodes, Adeptus Mechanicus, Astra Militarum, Black Templars, Blood Angels, Dark Angels, Deathwatch, Grey Knights, Imperial Fists, Iron Hands, Raven Guard, Salamanders, Space Wolves, Ultramarines, White Scars |
| Xenos | Necrons, Orks, T'au Empire |

**Total factions across all sessions: 34** (30 new + 4 previously tested)

---

## Section 2 — Per-Faction Status Table

All 30 factions passed ingestion with non-empty unit, weapon, and rule indexes.  
Zero pipeline crashes, zero ingestion failures, zero duplicate docIds, zero dangling weapon refs.  
Stat coverage (T, M, W): 100% across all 30 factions.  
Rule resolution (≥1 resolved rule): 100% across all 30 factions.

| Faction | Units | Deps | kw_hits | Ingestion | Stat 100% | Rules 100% | Notes |
|---------|------:|-----:|--------:|-----------|-----------|------------|-------|
| Aeldari - Craftworlds | 219 | 1 | 100 | PASS | ✓ | ✓ | Aeldari Library holds all units |
| Aeldari - Drukhari | 219 | 1 | 45 | PASS | ✓ | ✓ | Identical index to Craftworlds |
| Aeldari - Ynnari | 219 | 1 | 94 | PASS | ✓ | ✓ | Identical index to Craftworlds |
| Chaos - Chaos Daemons | 235 | 4 | 0 | PASS | ✓ | ✓ | Identity keyword mismatch (see OB-01) |
| Chaos - Chaos Knights | 235 | 4 | 19 | PASS | ✓ | ✓ | Same index as Chaos Daemons (shared deps) |
| Chaos - Chaos Space Marines | 272 | 4 | 100 | PASS | ✓ | ✓ | 7 Heresy Legends "Adeptus Astartes" units (see OB-02) |
| Chaos - Death Guard | 207 | 5 | 45 | PASS | ✓ | ✓ | 7 Heresy Legends "Adeptus Astartes" units (see OB-02) |
| Chaos - Emperor's Children | 185 | 5 | 23 | PASS | ✓ | ✓ | 7 Heresy Legends "Adeptus Astartes" units (see OB-02) |
| Chaos - Thousand Sons | 200 | 5 | 37 | PASS | ✓ | ✓ | 7 Heresy Legends "Adeptus Astartes" units (see OB-02) |
| Chaos - World Eaters | 191 | 5 | 30 | PASS | ✓ | ✓ | 7 Heresy Legends "Adeptus Astartes" units (see OB-02) |
| Genestealer Cults | 330 | 3 | 46 | PASS | ✓ | ✓ | 16 Tyranid units from Library - Tyranids dep (see OB-03) |
| Imperium - Adepta Sororitas | 182 | 3 | 63 | PASS | ✓ | ✓ | |
| Imperium - Adeptus Custodes | 160 | 3 | 41 | PASS | ✓ | ✓ | |
| Imperium - Adeptus Mechanicus | 167 | 3 | 46 | PASS | ✓ | ✓ | |
| Imperium - Astra Militarum | 387 | 5 | 100 | PASS | ✓ | ✓ | Largest non-SM index; 5 deps |
| Imperium - Black Templars | 237 | 1 | 40 | PASS | ✓ | ✓ | SM-only dep; faction units differ from SM core |
| Imperium - Blood Angels | 338 | 3 | 26 | PASS | ✓ | ✓ | SM supplement; index includes SM core units |
| Imperium - Dark Angels | 347 | 3 | 35 | PASS | ✓ | ✓ | SM supplement; largest SM supplement index |
| Imperium - Deathwatch | 261 | 1 | 64 | PASS | ✓ | ✓ | SM-only dep |
| Imperium - Grey Knights | 175 | 4 | 34 | PASS | ✓ | ✓ | |
| Imperium - Imperial Fists | 293 | 2 | 3 | PASS | ✓ | ✓ | Only 3 faction-specific units (see OB-04) |
| Imperium - Iron Hands | 314 | 3 | 2 | PASS | ✓ | ✓ | Only 2 faction-specific units (see OB-04) |
| Imperium - Raven Guard | 314 | 3 | 2 | PASS | ✓ | ✓ | Only 2 faction-specific units (see OB-04) |
| Imperium - Salamanders | 314 | 3 | 2 | PASS | ✓ | ✓ | Only 2 faction-specific units (see OB-04) |
| Imperium - Space Wolves | 383 | 3 | 71 | PASS | ✓ | ✓ | Large supplement with unique units |
| Imperium - Ultramarines | 328 | 3 | 16 | PASS | ✓ | ✓ | SM supplement |
| Imperium - White Scars | 314 | 3 | 2 | PASS | ✓ | ✓ | Only 2 faction-specific units (see OB-04) |
| Necrons | 89 | 1 | 67 | PASS | ✓ | ✓ | Standalone; smallest index (89 units) |
| Orks | 148 | 1 | 100 | PASS | ✓ | ✓ | Standalone |
| T'au Empire | 105 | 1 | 83 | PASS | ✓ | ✓ | Standalone |

---

## Section 3 — Issue List

### OB-01 — Chaos Daemons identity keyword mismatch

**Affected faction:** Chaos - Chaos Daemons  
**Description:** Keyword search for "chaos daemons" returns 0 hits. The BSData faction category for this army is `Faction: Legiones Daemonica`, which normalizes to the token `legiones daemonica`. The colloquial name "Chaos Daemons" does not appear in any category or keyword token.  
**Classification:** BSData structural variation  
**Systemic or local:** Local to this faction  
**Evidence:** M10 keyword search `{keywords: {"chaos daemons"}}` → 0 hits; `{keywords: {"legiones daemonica"}}` → expected non-zero hits (not tested but derivable from the Bloodthirster category data)  
**Smallest recommended action:** The answer layer (voice/UI, above M10) must maintain a name-mapping table: `"chaos daemons"` → query token `"legiones daemonica"`. No change to M9 or M10 required. The pipeline correctly indexes the BSData category names; only the call-site mapping is missing.

---

### OB-02 — Chaos faction indexes contain 7 "Adeptus Astartes" Legends units

**Affected factions:** Chaos Space Marines, Death Guard, Emperor's Children, Thousand Sons, World Eaters (all factions that pull in Library - Astartes Heresy Legends)  
**Description:** Each of these factions' indexes contains exactly 7 units carrying the `adeptus astartes` category token. These are Legends-tagged units from `Library - Astartes Heresy Legends.cat`: Javelin Attack Speeder, Deathstorm Drop Pod, Sicaran Arcus, Sicaran Omega, Vindicator Laser Destroyer, Dreadnought Drop Pod, Tarantula Sentry Battery.  
**Classification:** OK / expected variation  
**Systemic or local:** Systemic across all Chaos factions that declare Library - Astartes Heresy Legends as a dependency  
**Evidence:** Confirmed by direct XML inspection; these are BSData Legends cross-listing units that retain "Faction: Adeptus Astartes" even in the shared library.  
**Smallest recommended action:** None required for the pipeline. The answer layer may want to filter `[Legends]` entries or surface them with a Legends label. A keyword search for "adeptus astartes" in a Chaos faction index will surface these 7 units; the answer layer should not treat this as surprising.

---

### OB-03 — Genestealer Cults index contains 16 Tyranid units

**Affected faction:** Genestealer Cults  
**Description:** The Genestealer Cults index contains 16 units with the `tyranids` category token. Source is `Library - Tyranids.cat`, which is a declared dependency of the GSC catalog. These are bio-forms that can be fielded in GSC armies per BSData/game rules.  
**Classification:** OK / expected variation  
**Systemic or local:** Local to Genestealer Cults  
**Evidence:** `Library - Tyranids.cat` is listed as a `catalogueLink` dependency in `Genestealer Cults.cat`.  
**Smallest recommended action:** None required. The answer layer should be aware that a GSC index will include Tyranid units. If the answer layer filters by faction, it should include "tyranids" as a valid token in a GSC context.

---

### OB-04 — SM chapter supplements have very few faction-specific units

**Affected factions:** Imperial Fists (3 units), Iron Hands (2), Raven Guard (2), Salamanders (2), White Scars (2)  
**Description:** These chapter supplement catalogs add only 2–3 named characters per chapter. The full index (293–314 units) is almost entirely composed of inherited Space Marines units. Keyword search for the chapter name returns only 2–3 hits.  
**Classification:** OK / expected variation  
**Systemic or local:** Systemic across small chapter supplements  
**Evidence:** Direct XML inspection of `Imperium - Imperial Fists.cat` shows 8 `selectionEntry` elements total: 3 named characters + 5 items (relics/weapons with no `Faction:` category).  
**Smallest recommended action:** The answer layer must gracefully handle "list all [chapter] units" responses that return only 2–3 results. These are intentionally small supplements; a result set of 2–3 is correct and complete.

---

### OB-05 — Aeldari sub-factions produce identical indexes

**Affected factions:** Aeldari - Craftworlds, Aeldari - Drukhari, Aeldari - Ynnari  
**Description:** All three sub-factions depend solely on `Aeldari - Aeldari Library.cat`, which holds essentially all Aeldari unit content. The three primary catalogs contain only `entryLink` references, not independent `selectionEntry` elements. As a result, all three produce identical indexes: 219 units, 752 weapons, 855 rules.  
**Classification:** OK / expected variation  
**Systemic or local:** Local to Aeldari  
**Evidence:** Drukhari keyword search → 45 hits; Ynnari → 94 hits; Craftworlds "aeldari" → 100 hits. Differentiation is by category/keyword token, not by separate unit definitions.  
**Smallest recommended action:** None required at the pipeline level. The answer layer can distinguish sub-faction content correctly via keyword search. A query for "craftworlds" units and a query for "drukhari" units on the same index returns different result sets.

---

### OB-06 — Universal diagnostics: duplicateSourceProfileSkipped

**Affected factions:** All 30  
**Description:** Every faction produces exactly 2 `duplicateSourceProfileSkipped` diagnostics: one for ~17,805 rule profiles and one for ~798 weapon profiles. These represent BSData's pattern of attaching shared profiles (from the game system or shared library files) to multiple entry links, so the same profileId appears under multiple entries. M9 de-duplicates these correctly.  
**Classification:** OK / expected variation  
**Systemic or local:** Systemic across all factions  
**Smallest recommended action:** None. This is working as designed. The counts reflect the scale of BSData's shared-profile approach, not a data quality issue.

---

## Section 4 — Systemic Findings

### S-01 — Faction name ≠ BSData category token (Chaos Daemons case)

The "Chaos Daemons" case confirms a systemic risk: **the user-facing faction name does not always match the BSData category token**. Other factions to watch:

| User-facing name | BSData token (after normalization) | Risk level |
|-----------------|-------------------------------------|------------|
| Chaos Daemons | `legiones daemonica` | **Confirmed mismatch** |
| Emperor's Children | `emperors children` | Matches after apostrophe removal — OK |
| T'au Empire | `tau empire` | Matches after apostrophe removal — OK |
| Agents of the Imperium | (already tested) | Already handled |

**Recommendation:** Build an authoritative name-to-token mapping table in the answer layer before V1. Do not assume user-facing names normalize to matching BSData tokens.

---

### S-02 — SM supplements inflate the index with shared units

All SM chapter supplement catalogs declare `Imperium - Space Marines.cat` as a dependency. Their indexes include the full Space Marines unit set (~200–300 base units) plus their supplement-specific additions. The supplement-specific units are correctly identified by faction keyword token (e.g., `blood angels`, `dark angels`).

This pattern is confirmed across: Black Templars, Blood Angels, Dark Angels, Deathwatch, Imperial Fists, Iron Hands, Raven Guard, Salamanders, Space Wolves, Ultramarines, White Scars.

**Implication:** A voice query "what units does [chapter] have?" should filter by the chapter's keyword token, not return the full index (which includes all SM units). The keyword-filtered result is the correct answer.

---

### S-03 — Dependency complexity varies significantly across factions

| Dep count | Factions |
|-----------|---------|
| 0 | (none — all have at least 1) |
| 1 | Aeldari sub-factions, Black Templars, Deathwatch, Necrons, Orks, T'au Empire |
| 2 | Imperial Fists |
| 3 | Adepta Sororitas, Adeptus Custodes, Adeptus Mechanicus, Blood Angels, Dark Angels, Grey Knights (partial), Genestealer Cults |
| 4 | Chaos Daemons, Chaos Knights, Chaos Space Marines, Grey Knights |
| 5 | Death Guard, Emperor's Children, Thousand Sons, World Eaters, Astra Militarum |

Maximum depth observed: 5 direct dependencies (M1 depth-1 resolution). No faction in the sweep has a dependency graph that exceeds what M1 can handle at depth 1.

**Note:** Some factions with 4–5 deps also have transitive dependencies (e.g., Chaos Space Marines depends on the Astartes Heresy Legends library, which itself has no declared deps, so no depth-2 issue). The current depth-1 M1 model covers the full BSData catalog correctly as tested.

---

### S-04 — Rule resolution is fully faction-agnostic

100% of units across all 30 tested factions have at least one resolved `RuleDoc` entry. The `_findRuleAncestor()` inheritance logic introduced in M9 works correctly for every faction tested, including complex dep graphs (Chaos 5-dep factions, GSC with Tyranid cross-reference, SM supplements with full SM inheritance).

---

### S-05 — Stat completeness is fully faction-agnostic

100% of units across all 30 tested factions have T, M, and W characteristics. No faction has a unit that is missing standard datasheet stats. This holds for all unit types: infantry, characters, vehicles, monsters, titans, knights.

---

## Section 5 — Final Conclusion

**The pipeline is fully faction-agnostic.**

Every faction tested ingested cleanly, produced non-empty indexes, achieved 100% stat coverage, and achieved 100% rule resolution. No pipeline bug was found in 30 consecutive faction loads across all BSData wh40k-10e catalogs in the available fixture set.

### What is working cleanly across all 34 factions tested (including previously-tested)
- M1 Acquire: dependency resolution for graphs of 0–5 deps at depth 1
- M2 Parse → M5 Bind: XML parsing and binding for all BSData catalog structures
- M9 Index: unit/weapon/rule indexing with rule inheritance
- M10 Search: keyword filtering, text search, stat lookup

### Known answer-layer gaps that remain before V1

| Gap | Classification | Smallest fix |
|-----|---------------|-------------|
| "chaos daemons" → must map to "legiones daemonica" | BSData structural variation | Add name-to-token mapping table in answer layer |
| Small chapter supplements (2–3 unique units) | OK / expected | Answer layer handles small result sets gracefully |
| Shared unit dilution in SM supplements | OK / expected | Answer layer uses keyword token to filter, not index size |
| "BS of X" still on weapons not units | V1_BLOCKER (pre-existing) | Answer layer routes BS queries through WeaponDoc |

### No pipeline changes required
All findings above are either OK/expected or require answer-layer routing. M9 and M10 are confirmed faction-agnostic. No new module changes are recommended based on this sweep.

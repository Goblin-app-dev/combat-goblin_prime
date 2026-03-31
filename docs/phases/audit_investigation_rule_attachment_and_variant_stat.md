# Audit Investigation: Rule Attachment Gaps + Hive Tyrant Variant Stat

**Date:** 2026-03-23
**Branch:** claude/github-catalog-picker-Py9xI
**Baseline:** 9-unit ground-truth set (verified 2026-03-08 to 2026-03-10)
**Scope:** Two focused investigation passes against the refreshed 9-unit baseline

---

## Pass 1 — Datasheet-Level Rule Attachment Gaps (Leader + Onslaught)

### Background

The `unit_audit_test.dart` audit for **Hive Tyrant** reports two rules as missing:
`Onslaught` and `Leader`. The hypothesis was that both share the same underlying cause.

The investigation covered:
- Hive Tyrant (Tyranids catalog)
- Winged Hive Tyrant (Tyranids catalog)
- The Swarmlord (Tyranids catalog)
- Captain (Space Marines catalog — as a working reference)

---

### Finding 1a: Onslaught — Ground Truth Name Mismatch

**Observed:** rule `"Onslaught (Aura, Psychic)"` (docId `rule:d038-2f3d-1c4a-a15`) is present in the Hive Tyrant dump.

**Ground truth had:** `"name": "Onslaught", "descriptionSubstring": "charge"`

**Root cause:** The BSData 10e catalog stores 10th-edition ability qualifiers as part of the rule name. The Hive Tyrant Onslaught ability is stored as `"Onslaught (Aura, Psychic)"`, not `"Onslaught"`. The pipeline emits the catalog name verbatim (correct behaviour). The ground truth was written from Wahapedia, which omits the qualifier.

Additionally, the Wahapedia description mentions "charge" (referring to the ASSAULT ability allowing charges after Advancing), while the catalog description uses the 10th-ed keyword form: `"...ranged weapons equipped by models in that unit have the [ASSAULT] and [LETHAL HITS] abilities."` These describe the same mechanic but the text differs.

**Fix applied:** Ground truth updated to `"name": "Onslaught (Aura, Psychic)"`, `"descriptionSubstring": "LETHAL HITS"`.

**This was NOT a pipeline bug.** The pipeline was correct; the ground truth was miscalibrated.

---

### Finding 1b: Paroxysm (Winged Hive Tyrant) — Same Name Mismatch

Same pattern as Onslaught. The Winged Hive Tyrant's Paroxysm ability is stored in the catalog as `"Paroxysm (Psychic)"`. The ground truth had `"Paroxysm"`.

**Fix applied:** Ground truth updated to `"name": "Paroxysm (Psychic)"`.

---

### Finding 1c: Shadow in the Warp — descriptionSubstring Hyphen Mismatch

The Winged Hive Tyrant ground truth had `"descriptionSubstring": "Battleshock"` (no hyphen), but the catalog description spells it `"Battle-shock"`. The comparator uses `String.contains()` so `"Battle-shock".contains("Battleshock")` → false.

**Fix applied:** Updated to `"descriptionSubstring": "Battle-shock"`.

---

### Finding 1d: Leader — Genuine Pipeline Gap

**Observed:** `Leader` is absent from the dumps of both **Hive Tyrant** and **The Swarmlord** (Tyranids). It IS present in the **Captain** dump (Space Marines, rule `rule:6e66-2c98-4726-d12d`).

**Cross-catalog contrast:**

| Unit | Catalog | Leader in dump? |
|------|---------|----------------|
| Captain | Space Marines | YES (with full unit-specific description) |
| Hive Tyrant | Tyranids | NO |
| The Swarmlord | Tyranids | NO |

The Swarmlord result is particularly diagnostic: The Swarmlord is a top-level entry (correct stats, no variant-selection ambiguity). Its dump contains other infoLink-resolved rules (Shadow in the Warp, Synapse, Deadly Demise, Hive Commander, Malign Presence, Domination of the Hive Mind). These all work because their catalog rule nodes have non-empty descriptions.

**Root cause (confirmed by code trace):**

1. M5 `_resolveInfoLink` resolves the Leader `<infoLink>` target → finds the `<rule>` node → calls `_bindRuleNodeAsProfile`.

2. `_bindRuleNodeAsProfile` calls `_extractRuleDescriptionText`. For the Tyranid catalog's Leader rule, the `<description>` element is **empty** (or absent). Returns `""`.

3. The old `_bindRuleNodeAsProfile` used `if (description.isNotEmpty)` to guard the characteristic:
   ```dart
   characteristics: [
     if (description.isNotEmpty) (name: 'description', value: description),
   ],
   ```
   With empty description → `characteristics = []`.

4. M9 `_buildRuleDocs` calls `_extractDescription(profile)`. With empty characteristics → returns `null`.

5. M9 guard: `if (description == null || description.isEmpty) continue;` → skips the profile → no RuleDoc created.

6. `_collectRuleRefs` never finds a Leader RuleDoc → not added to unit's `ruleDocRefs`.

**The Space Marines Captain works** because its catalog contains a unit-specific Leader rule with a full non-empty description listing which units the Captain can join. The Tyranids catalog either omits that description or leaves it blank.

**Why Onslaught surfaces but Leader doesn't:** Both go through the same `_bindRuleNodeAsProfile` path, but Onslaught has a non-empty description in the catalog. Leader does not. This confirms the shared underlying cause: the description-emptiness filter.

**Fix applied (two-part):**

*M5 `bind_service.dart` — `_bindRuleNodeAsProfile`:*
Changed to always emit the description characteristic, even when empty:
```dart
// Before
characteristics: [
  if (description.isNotEmpty) (name: 'description', value: description),
],

// After
characteristics: [(name: 'description', value: description)],
```

*M9 `index_service.dart` — `_buildRuleDocs`:*
Relaxed the skip guard from `null || isEmpty` to `null` only:
```dart
// Before
if (description == null || description.isEmpty) { continue; }

// After
if (description == null) { continue; }
```

**Effect:** Rules materialized from `<rule>` nodes with empty catalog descriptions now produce RuleDocs with `description = ""`. They appear in unit dumps and the audit comparator's `"descriptionSubstring": null` check passes (no substring match required for Leader).

**Expected outcome after fix:**
- Hive Tyrant dump: Leader appears (possibly with empty description)
- Swarmlord dump: Leader appears (possibly with empty description)
- No regressions for rules that already had descriptions (Onslaught, Shadow in the Warp, etc.)

---

### Swarmlord Inline Ability Note Correction

The Swarmlord ground truth notes incorrectly stated that inline ability profiles (Hive Commander, Malign Presence, Domination of the Hive Mind, Lord of Deceit) would NOT surface in the pipeline output. They DO surface — `_resolveInfoLink` materialises both `<profile>` and `<rule>` targets as BoundProfiles, and `_collectRuleRefs` finds them via `entry.profiles`. Notes updated to reflect the actual pipeline behaviour.

---

## Pass 2 — Hive Tyrant / Winged Hive Tyrant Wrong-Variant Stat + Weapon Binding

### Background

The Hive Tyrant dump (docId `unit:3e96-8098-3401-77af`) shows:

| Stat | Observed (dump) | Expected (Wahapedia) |
|------|----------------|---------------------|
| M    | 8"             | 10"                 |
| T    | 10             | 10                  |
| SV   | 2+             | 2+                  |
| W    | 10             | 14                  |
| LD   | 7+             | 6+                  |
| OC   | 3              | 3                   |

The weapons in the dump also do not match the walking Hive Tyrant's ground truth:
- **Dump has:** Stranglethorn cannon, Monstrous scything talons, Monstrous bonesword and lash whip, Heavy venom cannon, Vertebrax of Vodun
- **Ground truth expects:** Monstrous Bonesword and Lash Whip (PRECISION), Tyrant Talons, Heavy Venom Cannon, Monstrous Bio-Cannon, Monstrous Rending Claws, Psychic Scream

The Winged Hive Tyrant dump shows correct stats (M=12", T=9) but has 6 weapons when 4 are expected, including "Tyrant talons" which belongs to the walking variant.

### Finding 2a: Stats — Catalog Version Drift vs Wrong Entry

The Swarmlord dump (ground truth verified from BSData fixture) also shows M=8", T=10, W=10, LD=7+. This means M=8"/W=10 stats exist in the BSData fixture for Tyranid MONSTER/CHARACTER entries. Two candidate explanations remain:

**Candidate A (Version Drift):** The BSData Tyranid fixture snapshot has outdated stats for the walking Hive Tyrant (M=8", W=10 rather than the current Wahapedia M=10", W=14). The catalog hasn't been updated since a balance dataslate changed the stats. The selected entry IS the correct walking HT entry, just with stale data.

**Candidate B (Wrong Entry Selected):** The BSData catalog structures the Hive Tyrant as an outer "unit container" entry (id `3e96-8098-3401-77af`) with unit-profile stats and shared weapon entryLinks, plus an inner "model entry" with the correct walking stats. M9 selects the outer container because it also has a unit profile and its entryId sorts first.

### Finding 2b: Weapon Set — Confirms Wrong Entry or Shared Pool

The weapons observed on the walking Hive Tyrant dump match what a SHARED weapon pool would contain (weapons available to any Hive Tyrant variant), not the walking-specific weapons. The walking-specific weapons (Tyrant Talons, Monstrous Bio-Cannon, Monstrous Rending Claws, Psychic Scream) are absent. The Winged Hive Tyrant dump has "Tyrant talons" which belongs to the walking variant — confirming both variants are drawing from the same weapon pool.

This is more consistent with **Candidate B**: the outer unit container entry (selected as "Hive Tyrant") owns the shared weapon entryLinks. The inner walking model entry owns the variant-specific weapons. M9 picks the container.

### Finding 2c: Shared Unit-Profile Entry Pattern

Both the container and model entries have unit-type profiles, causing both to be indexed as separate UnitDocs. M9's `_buildUnitDocs` does not distinguish between "container" entries and "model" entries at the index layer. The alphabetically-first docId wins.

### Next Steps for Pass 2 (NOT implemented in this pass)

1. **Run the inspection test** (`hive_tyrant_inspection_test.dart`) with the catalog fixture to confirm whether multiple "hive tyrant" canonical-key entries exist and which has the correct stats.

2. **Determine BSData catalog XML structure** for the Hive Tyrant: is there an outer container entry (`type="unit"`) with a placeholder unit profile, and an inner model entry (`type="model"`) with the real stats?

3. **Fix strategy (candidates):**
   - **M9 entry-type preference:** When both an outer `type="unit"` entry and inner `type="model"` entries have unit profiles under the same canonical name, prefer the inner model entries. Requires reading the `type` attribute from BoundEntry (currently not materialised from M5).
   - **M5 entry-type surfacing:** Surface the BSData `type` attribute from `<selectionEntry>` onto `BoundEntry` so M9 can make type-aware selection decisions.
   - **Disambiguation by stat completeness:** Prefer unit entries whose unit profile has the most non-empty stat characteristics (proxy for the "real" data entry vs a placeholder).

4. **Weapon binding fix:** Once the correct entry is selected, variant-specific weapons should surface naturally. The shared-pool weapon duplication (walking weapons appearing on the winged dump) will also be resolved if the entry boundary is correctly identified.

---

## Summary of Changes Made in This Investigation Pass

| File | Change |
|------|--------|
| `test/audit/ground_truth/hive_tyrant.json` | Onslaught name → "Onslaught (Aura, Psychic)"; descriptionSubstring → "LETHAL HITS"; added knownDiscrepancy entries for Onslaught and Leader |
| `test/audit/ground_truth/winged_hive_tyrant.json` | Paroxysm name → "Paroxysm (Psychic)"; Shadow in the Warp descriptionSubstring → "Battle-shock"; added knownDiscrepancy entries |
| `test/audit/ground_truth/the_swarmlord.json` | Corrected notes about inline abilities surfacing; added knownDiscrepancy for Leader gap |
| `lib/modules/m5_bind/services/bind_service.dart` | `_bindRuleNodeAsProfile`: always emit description characteristic even when empty |
| `lib/modules/m9_index/services/index_service.dart` | `_buildRuleDocs`: relax skip guard from `null \|\| isEmpty` to `null` only |

**Pass 2 (wrong-variant stat + weapon binding) is documented above but not fixed.** The fix requires confirming the catalog entry structure and surfacing the `type` attribute from `<selectionEntry>` — a targeted follow-up.

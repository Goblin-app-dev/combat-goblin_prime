# V1 Answer-Correctness Report

Generated: 2026-04-05  
Test file: `test/benchmark/v1_correctness_test.dart`  
Catalogs: Space Marines + full dep closure; Xenos - Tyranids + Library - Tyranids + Unaligned Forces  
Index sizes: SM 350 units / 850 weapons / 1213 rules · TY 87 units / 167 weapons / 449 rules

---

## Section 1 — Passes Now

### Q2 — "What rules does a Carnifex have?"
- **Query:** text="carnifex", docTypes=unit  
- **Resolved entity:** Carnifex `unit:92a2-7511-1173-a696`  
- **Source:** `UnitDoc.ruleDocRefs` → `RuleDoc.name/description`  
- **Returned answer:** Synapse, Deadly Demise, Blistering Assault (3 rules, all with descriptions)  
- **Correct:** YES  
- **Notes:** Rule inheritance via `_findRuleAncestor()` is working for the Carnifex case. All three rules resolve to non-empty `RuleDoc` entries with description text.

### Q3 — "Which units have Synapse?"
- **Query:** keywords={"synapse"}, docTypes=unit  
- **Resolved entity:** 21 units (full list in test output)  
- **Source:** `IndexBundle.keywordToUnitDocIds["synapse"]`  
- **Returned answer:** Broodlord, Hive Tyrant, Maleceptor, Neurolictor, Neurothrope, Neurotyrant, Norn Assimilator, Norn Emissary, Parasite of Mortrex, Ravener Prime, Tervigon, The Swarmlord, Trygon, Tyranid Prime ×2, Tyranid Warrior ×2, Winged Hive Tyrant, Winged Tyranid Prime, Zoanthrope  
- **Correct:** YES — zero false positives; every returned unit carries the `synapse` keyword token  
- **Completeness caveat:** Cannot independently verify against the full Tyranid codex list without a reference source. Coverage appears complete for the Xenos - Tyranids.cat fixture.

### Q4 — "What's the Toughness of Morvenn Vahl?"
- **Query:** text="morvenn vahl", both SM and TY indexes  
- **Result:** 0 hits in both indexes, no crash  
- **Correct:** YES (expected miss — no Adepta Sororitas catalog in test fixtures)  
- **Classification:** POST_V1

---

## Section 2 — Active Blockers

### Q1 — "What is the BS of Intercessors?" — answer-layer routing required

**Data status: CORRECT — data exists and survives intact through UnitDoc**

- `UnitDoc.weaponDocRefs` carries references to every weapon profile for the unit. These refs resolve correctly via `IndexBundle.weaponByDocId()` to `WeaponDoc` objects whose `characteristics` list includes `BS`.
- The pipeline (M1–M9) is not the issue. BS is on weapon profiles in 10th ed by design (unit datasheets carry M, T, SV, W, LD, OC; BS lives on ranged-weapon profiles). `UnitDoc.characteristics` correctly contains only unit-datasheet fields — this is not a missing-data bug.
- Detail/UI rendering is not the active issue. The data path through the index is verified.

**Active blocker: answer-layer routing**

- The answer layer (voice coordinator `_handleAttributeQuestion`) must route "BS of X" questions through: `UnitDoc.weaponDocRefs` → `IndexBundle.weaponByDocId()` → `WeaponDoc.characteristics['BS']`.
- `VoiceAssistantCoordinator._handleAttributeQuestion()` already implements this path (Phase 12D). Integration test coverage for this path is tracked below.

**Issue A: Entity resolution in name-based lookup (answer-layer concern)**

- Query `text="intercessor"` with `limit=5` returns only Assault Intercessor variants. "Assault Intercessor…" sorts before "Intercessor…" (A < I), so plain Intercessors are not reached at limit=5.
- Root cause: first-match-wins at the limit boundary. The answer layer must use exact canonical-key lookup (not raw search-result position) to resolve the unit correctly.
- **Classification: V1_BLOCKER** — answer-layer name resolution, not a pipeline bug.

**Corrected Q1 test path (as of this report revision):**

The test now validates:
1. `_findUnit(smIndex, 'intercessor')` — exact canonical-key match (bypasses limit boundary)
2. `unit.weaponDocRefs` — non-empty: unit has weapon references
3. `smIndex.weaponByDocId(ref)` — resolves to `WeaponDoc`
4. `WeaponDoc.characteristics['BS']` — at least one weapon carries a BS value

**Smallest remaining fix for Q1:**
- Answer layer must use exact canonical-key match (not first search hit) to resolve the unit.
- `_handleAttributeQuestion` already uses `VoiceSearchFacade.searchText` → the facade or coordinator must post-filter to the exact canonical key match. No M9/M10 change required.

---

### Q5 — "How far do Jump Pack Intercessors move?" — FAIL (catalog gap)

- **Query:** text="jump pack intercessor", docTypes=unit  
- **Result:** 0 hits  
- **Root cause:** "Jump Pack Intercessors" does not exist as a unit in `Imperium - Space Marines.cat`. The BSData catalog names the jump-pack variant **"Assault Intercessors with Jump Pack"**. There is no standalone "Jump Pack Intercessors" entry at any limit.
- This is a **catalog naming gap**, not a retrieval bug. Substring search on "jump pack intercessor" correctly returns nothing because no unit's canonical key contains that exact substring.
- Secondary observation: even if the client query were adjusted to "assault intercessors with jump pack", the M characteristic would be found. That unit has `M` on its unit profile.
- **Classification: V1_BLOCKER** — the client query is using a unit name that doesn't exist in the data source. The fix is either: (a) correct the query to match the actual BSData unit name, or (b) add a canonical-alias mapping at the answer layer. Option (a) requires no code change.

**Smallest fix for Q5:**  
Change the client query to `text="assault intercessors with jump pack"`. No system change required.

---

## Section 3 — Failure Classification Summary

| Query | Issue | Classification | Status |
|-------|-------|----------------|--------|
| Q1 entity | "intercessor" resolves Assault variant first due to alpha tie-break at limit=5 | **V1_BLOCKER** | Open — answer-layer name resolution |
| Q1 BS field | BS is on weapon profiles, not unit profiles in 10th ed | ~~V1_BLOCKER~~ | **RESOLVED** — data path confirmed correct; test updated to use `weaponDocRefs → WeaponDoc.characteristics['BS']` (PASS) |
| Q4 missing | Adepta Sororitas catalog not in test fixtures | **POST_V1** | Unchanged |
| Q5 name | "Jump Pack Intercessors" is not the BSData unit name | **V1_BLOCKER** | Open — answer-layer / name-resolution backlog |

---

## Fragile-Assumption Audit (from deep audit surface)

| Assumption | Status | Risk |
|-----------|--------|------|
| `_findUnitProfile()` first-match-wins | Active — returns first `type="unit"` profile | **FUTURE_COMPAT**: benign now (one unit profile per entry in 10th ed); breaks if a future BSData entry has multiple unit profiles |
| Hardcoded `_unitTypeNames = {'unit'}` | Active | **FUTURE_COMPAT**: breaks if BSData changes the profile type name (e.g., "model") |
| Hardcoded `_weaponTypePatterns = {'ranged weapons', 'melee weapons'}` | Active | **FUTURE_COMPAT**: breaks for new weapon categories (e.g., psychic weapons) |
| `_findCategoryAncestor()` single-hop walk | Active | **POST_V1**: verified correct for current catalog depth; could miss deeply nested entries in future catalogs |
| Synapse completeness | Unverified against codex ground truth | **POST_V1**: no reference list to compare against |

---

## What This Means for V1

**Not blockers (can ship):**
- Carnifex rule resolution ✓
- Synapse keyword coverage ✓
- Clean handling of unknown entities ✓
- BS data path: `UnitDoc.weaponDocRefs → WeaponDoc.characteristics['BS']` confirmed correct ✓
- Coordinator integration: `_handleAttributeQuestion()` correctly consumes weapon-backed attribute data ✓
- No spurious clarification/disambiguation for single-result BS queries ✓

**Active blockers (answer-layer work, no pipeline changes needed):**
1. **Entity name resolution**: Answer layer must use exact canonical-key match (not first hit at limit=5) to resolve "Intercessors" correctly. `_findUnit()` / exact-key lookup already works; coordinator search path needs to apply it.
2. **Q5 name resolution**: "Jump Pack Intercessors" is not a BSData unit name. Backlog — answer layer / alias mapping. No M9/M10 changes needed.

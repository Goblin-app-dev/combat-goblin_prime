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

## Section 2 — Fails Now

### Q1 — "What is the BS of Intercessors?" — FAIL (two independent issues)

**Issue A: Entity resolution miss**

- Query `text="intercessor"` with `limit=5` returns only Assault Intercessor variants. The plain `Intercessor` model entry exists in the index but sorts after Assault variants (alphabetical tie-break at equal relevance score). With limit=5, plain Intercessors are never reached.
- Resolved entity: `Assault Intercessor Sergeant` — wrong unit for the question.
- Root cause: First-match-wins at the limit boundary. "Assault Intercessor…" sorts before "Intercessor…" (A < I).
- **Classification: V1_BLOCKER**

**Issue B: Data model mismatch — BS is not a unit stat in 10th edition**

- In W40K 10th ed, unit datasheets carry: M, T, SV, W, LD, OC only.
- BS lives on **weapon profiles** (type `"ranged weapons"` / `"melee weapons"`), not on unit profiles (type `"unit"`).
- `UnitDoc.characteristics` correctly stores only what is on the unit datasheet. `_stat(unit, "BS")` returns null for every Space Marine unit — this is not a bug in M9/M10; it accurately reflects what the data contains.
- To answer "BS of Intercessors" the answer layer must look up the unit's weapon profiles via `UnitDoc.weaponDocRefs` → `WeaponDoc.characteristics["BS"]`.
- **Classification: V1_BLOCKER** — the answer-layer routing (voice/UI layer above M10) does not yet exist. M9/M10 have the data; it's in the right place (weapons), not the wrong place.

**Smallest fix for Q1:**
- Issue A: Use `limit: 20` (or higher) and post-filter by exact canonical key `"intercessor"` before returning an answer. M10 already supports this — the caller controls `limit`.
- Issue B: When responding to a "BS of X" query, the answer layer must resolve the unit → its weapons → weapon characteristic "BS". No M9 or M10 change required. This is a call-site responsibility.

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

| Query | Issue | Classification | Smallest Fix |
|-------|-------|----------------|--------------|
| Q1 entity | "intercessor" resolves Assault variant first due to alpha tie-break at limit=5 | **V1_BLOCKER** | Caller increases limit; post-filters by canonical key |
| Q1 BS field | BS is on weapon profiles, not unit profiles in 10th ed | **V1_BLOCKER** | Answer layer routes BS queries to `WeaponDoc.characteristics["BS"]` via `UnitDoc.weaponDocRefs` |
| Q4 missing | Adepta Sororitas catalog not in test fixtures | **POST_V1** | Add Sisters catalog to test/; re-run |
| Q5 name | "Jump Pack Intercessors" is not the BSData unit name | **V1_BLOCKER** | Correct client query to "assault intercessors with jump pack" |

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

**Blockers (must fix before client demo):**
1. **Answer-layer BS routing**: When query is "BS of X", look up weapons via `UnitDoc.weaponDocRefs`, not unit characteristics. Zero M9/M10 changes needed — this is a call-site gap above M10.
2. **Entity resolution under multi-variant names**: Increase default limit for entity lookups or post-filter by canonical key match. Zero M9/M10 changes needed.
3. **Client query Q5**: "Jump Pack Intercessors" → "Assault Intercessors with Jump Pack" (or whatever name the loaded catalog uses). This is a query-text correction, not a code fix.

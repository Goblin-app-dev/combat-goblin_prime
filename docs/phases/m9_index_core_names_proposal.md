# M9 Index-Core (Search) — Names-Only Proposal

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **FROZEN** (2026-02-11)
- Phase 5 (M7 Applicability): **FROZEN** (2026-02-12)
- Phase 6 (M8 Modifiers): **FROZEN** (2026-02-12)
- Orchestrator v1: **FROZEN** (2026-02-12)
- M9 Index-Core: **PROPOSED**

---

## Revision History

| Rev | Date | Changes |
|-----|------|---------|
| 1 | 2026-02-12 | Initial names-only proposal (roster-driven goals) |
| 2 | 2026-02-13 | Drop CharacteristicDoc as doc type; add DUPLICATE_RULE_CANONICAL_KEY, LINK_TARGET_MISSING codes; clarify RuleDoc sources; explicit deterministic ordering |

---

## Purpose

M9 Index-Core builds a **search index** for player-facing queries:

- "Find unit X"
- "What weapons does unit X have?"
- "Show me all units with keyword Y"
- "What does rule Z do?"

The index enables voice/search UI features to deliver instant answers without re-traversing the entire bound data on each query.

---

## Roster-Driven Goals

Players interact with their data through the lens of their roster exports. Based on BattleScribe roster JSON exports, players expect to access:

1. **Unit lookup by name** — "Find Intercessor Squad"
2. **Weapon lookup by name** — "Find Bolt Rifle"
3. **Characteristics lookup** — "What are the stats for this unit?"
4. **Rules lookup** — "What does Oath of Moment do?"
5. **Keywords and categories** — "Show all Infantry units"

M9 produces an IndexBundle that supports these queries efficiently.

---

## Design Decision: M5-Only Input (v1)

M9 v1 takes only BoundPackBundle (M5 output) as input.

**Why no M6/M7/M8 dependence:**
- Search index should be buildable once at pack load time
- Roster state (M6 evaluation) changes frequently
- Effective values (M8 modifiers) are roster-dependent
- Voice/search queries often occur before roster exists

**Future versions** may add M6/M7/M8-aware indexing for roster-context queries, but v1 is pack-only.

### What Counts as a Rule (v1)

RuleDoc sources are explicitly defined as:
1. **BoundRule** — Any bound rule entity (if that type exists in M5)
2. **Ability profiles** — BoundProfile where typeName is "Abilities" (or equivalent canonical typeName) with description text
3. **Weapon keywords** — Keywords on weapons that map to a rule entry in M5 data; if keyword text exists but rule entity doesn't resolve, emit `LINK_TARGET_MISSING`

This keeps rule extraction deterministic and avoids inventing semantics.

---

## Module Layout

### Module
- Folder: `lib/modules/m9_index/`
- Barrel: `lib/modules/m9_index/m9_index.dart`

### Public Exports (barrel only)
- `services/index_service.dart`
- `models/index_bundle.dart`
- `models/unit_doc.dart`
- `models/weapon_doc.dart`
- `models/rule_doc.dart`
- `models/indexed_characteristic.dart`
- `models/index_diagnostic.dart`

### File Layout
```
lib/modules/m9_index/
├── m9_index.dart
├── models/
│   ├── index_bundle.dart
│   ├── unit_doc.dart
│   ├── weapon_doc.dart
│   ├── rule_doc.dart
│   ├── indexed_characteristic.dart
│   └── index_diagnostic.dart
└── services/
    └── index_service.dart
```

---

## Core Types

### Document Kinds (v1)

M9 v1 produces exactly three document types:
1. **UnitDoc** — Indexed unit with characteristics as fields
2. **WeaponDoc** — Indexed weapon with characteristics as fields
3. **RuleDoc** — Indexed rule with description

Characteristics are **fields on docs**, not standalone documents.

---

### IndexBundle
**File:** `models/index_bundle.dart`

Complete search index for a pack.

**Fields:**
- `String packId` — Identity (from BoundPackBundle)
- `DateTime indexedAt` — Timestamp of index build
- `List<UnitDoc> units` — All unit documents (sorted by key)
- `List<WeaponDoc> weapons` — All weapon documents (sorted by key)
- `List<RuleDoc> rules` — All rule documents (sorted by key)
- `Map<String, UnitDoc> unitsByKey` — Lookup by canonical key
- `Map<String, List<UnitDoc>> unitsByName` — Lookup by name (lowercase)
- `Map<String, WeaponDoc> weaponsByKey` — Lookup by canonical key
- `Map<String, List<WeaponDoc>> weaponsByName` — Lookup by name (lowercase)
- `Map<String, RuleDoc> rulesByKey` — Lookup by canonical key
- `Map<String, List<RuleDoc>> rulesByName` — Lookup by name (lowercase)
- `Map<String, List<String>> byCharacteristicNameToken` — Inverted index: characteristic name → doc keys
- `List<IndexDiagnostic> diagnostics` — Issues encountered (sorted by source)
- `BoundPackBundle boundBundle` — Reference to input (for provenance chain)

**Deterministic Ordering Rule:**
All doc emission and lookups MUST be sorted by stable keys. No unordered iteration.
- Doc lists sorted alphabetically by `key`
- Lookup maps use `SplayTreeMap` or equivalent sorted map
- Diagnostics sorted by `(sourceFileId, sourceNode.nodeIndex)`

---

### UnitDoc
**File:** `models/unit_doc.dart`

Indexed document for a unit (selectionEntry representing a model/unit).

**Fields:**
- `String key` — Canonical key (entryId from BoundEntry)
- `String name` — Display name (from BoundEntry.name)
- `String normalizedName` — Lowercase searchable name
- `List<String> nameTokens` — Tokenized name for search
- `List<IndexedCharacteristic> characteristics` — Unit stats (M, WS, BS, etc.)
- `List<String> keywords` — Keywords/abilities (from categories)
- `List<String> weaponKeys` — Keys of weapons this unit can take
- `List<String> ruleKeys` — Keys of rules this unit references
- `String? primaryCategory` — Primary category name (if any)
- `String sourceFileId` — Provenance
- `NodeRef sourceNode` — Provenance

**Extraction Rules:**
- One UnitDoc per BoundEntry where isGroup=false and has profileType matching unit profile (e.g., "Unit", "Model")
- Characteristics extracted from BoundProfile with appropriate typeName
- Keywords extracted from BoundCategory list
- Weapons identified by child entries with weapon-type profiles
- If weaponKey cannot be resolved, emit `LINK_TARGET_MISSING`

---

### WeaponDoc
**File:** `models/weapon_doc.dart`

Indexed document for a weapon.

**Fields:**
- `String key` — Canonical key (entryId or profileId)
- `String name` — Display name
- `String normalizedName` — Lowercase searchable name
- `List<String> nameTokens` — Tokenized name for search
- `List<IndexedCharacteristic> characteristics` — Weapon stats (Range, Type, S, AP, D)
- `List<String> keywords` — Weapon abilities/keywords
- `List<String> ruleKeys` — Keys of rules this weapon references
- `String? weaponType` — Type classification (Melee, Ranged, etc.)
- `String sourceFileId` — Provenance
- `NodeRef sourceNode` — Provenance

**Extraction Rules:**
- One WeaponDoc per BoundProfile where typeName indicates weapon (e.g., "Ranged Weapons", "Melee Weapons")
- Characteristics extracted from profile characteristics list
- Weapon type derived from typeName or inferred from characteristics
- If ruleKey (from keyword) cannot be resolved, emit `LINK_TARGET_MISSING`

---

### RuleDoc
**File:** `models/rule_doc.dart`

Indexed document for a rule.

**Fields:**
- `String key` — Canonical key (ruleId or infoLink targetId)
- `String name` — Display name
- `String normalizedName` — Lowercase searchable name
- `List<String> nameTokens` — Tokenized name for search
- `String? description` — Rule text (may be truncated for index)
- `String? publicationRef` — Publication reference (book, page)
- `String sourceFileId` — Provenance
- `NodeRef sourceNode` — Provenance

**Extraction Rules:**
- One RuleDoc per unique rule element encountered
- Deduplication by canonical key (first occurrence wins, per shadowing policy)
- If same canonical key encountered again, emit `DUPLICATE_RULE_CANONICAL_KEY`
- Description truncated if >1000 chars, emit `TRUNCATED_DESCRIPTION`

**RuleDoc Sources (v1):**
1. BoundRule entities (if M5 provides them)
2. BoundProfile where typeName = "Abilities" (or canonical equivalent) with description
3. Weapon keywords that resolve to rule entries

---

### IndexedCharacteristic
**File:** `models/indexed_characteristic.dart`

Single characteristic name-value pair as a **field** on UnitDoc/WeaponDoc (NOT a standalone document).

**Fields:**
- `String name` — Characteristic name (e.g., "M", "WS", "S")
- `String? typeId` — Type ID for disambiguation (if available)
- `String valueText` — Characteristic value (raw string, not parsed)
- `String normalizedToken` — Lowercase normalized form for search (e.g., "m", "ws")

**Design Decision:**
Characteristics are fields, not docs. This avoids:
- Huge doc set with weak standalone meaning ("T=4" isn't a player search)
- Ambiguity (same name across many profiles)
- Linking and ranking complexity

For "show me units with T > 4" queries, use the inverted index facet:
`IndexBundle.byCharacteristicNameToken` → doc keys

---

### IndexDiagnostic
**File:** `models/index_diagnostic.dart`

Non-fatal issue detected during index building.

**Fields:**
- `IndexDiagnosticCode code` — Diagnostic code (closed enum)
- `String message` — Human-readable description
- `String sourceFileId` — File where issue occurred
- `NodeRef? sourceNode` — Node where issue occurred
- `String? key` — Key involved (if applicable)
- `String? name` — Name involved (if applicable)

**Diagnostic Codes (7 codes):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `MISSING_NAME` | Entry/profile has empty or missing name | Doc created with key as fallback name |
| `DUPLICATE_DOC_KEY` | Same doc key encountered twice (unit/weapon) | First wins, diagnostic emitted |
| `DUPLICATE_RULE_CANONICAL_KEY` | Same rule canonical key encountered twice | First wins, diagnostic emitted (prevents "Assault shows up 400 times") |
| `UNKNOWN_PROFILE_TYPE` | Profile typeName not recognized | Profile indexed as generic |
| `EMPTY_CHARACTERISTICS` | Unit/weapon has no characteristics | Doc created with empty list |
| `TRUNCATED_DESCRIPTION` | Rule description exceeded max length | Description truncated |
| `LINK_TARGET_MISSING` | Unit→weapon, weapon→rule, or keyword→rule link cannot resolve | Link omitted, diagnostic emitted (makes broken links auditable) |

**Rules:**
- All diagnostics non-fatal
- Index building continues on all issues
- Diagnostics accumulated and returned in IndexBundle
- Diagnostics sorted by (sourceFileId, sourceNode.nodeIndex) for determinism

---

## Services

### IndexService
**File:** `services/index_service.dart`

**Method: buildIndex**
```dart
IndexBundle buildIndex(BoundPackBundle boundBundle)
```

**Parameters:**
- `boundBundle` — M5 output (frozen, read-only)

**Returns:**
- `IndexBundle` — Complete search index

**Implementation Sequence:**
1. Validate input (check BoundPackBundle integrity)
2. **Build RuleDoc dedupe map first** (so weapons/units can link)
3. Build WeaponDocs (link to rules, emit LINK_TARGET_MISSING if unresolved)
4. Build UnitDocs (link to weapons and rules)
5. Build inverted indices (byCharacteristicNameToken)
6. Sort all collections by stable keys
7. Aggregate diagnostics (sorted)

**Determinism Contract:**
- Same BoundPackBundle → identical IndexBundle (except indexedAt)
- All doc emission sorted by key
- All lookups sorted by key
- Entry traversal order: boundBundle.rootEntries list order
- Profile traversal order: entry.profiles list order
- No unordered iteration anywhere

---

## Profile Type Classification

M9 must classify profiles to determine document type. Initial heuristics (configurable per game system):

| typeName Pattern | Document Type |
|------------------|---------------|
| "Unit", "Model" | UnitDoc (characteristics as fields) |
| "Ranged Weapons", "Melee Weapons", "Weapon" | WeaponDoc (characteristics as fields) |
| "Abilities" | RuleDoc source |

**Unknown profile types:** Indexed generically, `UNKNOWN_PROFILE_TYPE` diagnostic emitted.

---

## Tokenization Rules

For search functionality, names are tokenized deterministically:

1. **Normalization:** lowercase, trim whitespace
2. **Token splitting:** split on whitespace and punctuation
3. **No stemming:** exact token matching (v1 simplicity)
4. **Deterministic:** same input → identical token list

Example: "Intercessor Squad" → tokens: ["intercessor", "squad"]

Single function, tested independently:
```dart
List<String> tokenize(String input)
```

---

## Deduplication Strategy

### Units
- Key = entryId
- Duplicate entryId: first wins (per file resolution order), `DUPLICATE_DOC_KEY` emitted

### Weapons
- Key = profileId (or entryId if profile nested)
- Duplicate key: first wins, `DUPLICATE_DOC_KEY` emitted

### Rules
- Key = canonical rule key (ruleId or resolved infoLink targetId)
- Duplicate canonical key: first wins, `DUPLICATE_RULE_CANONICAL_KEY` emitted
- This prevents "why does Oath of Moment appear 400 times?" problem

---

## No-Failure Policy

M9 follows the established diagnostic pattern:

- **IndexDiagnostic** for all non-fatal issues
- **IndexFailure** only for corrupted M5 input or internal bugs
- In normal operation, no IndexFailure is thrown
- Missing data produces diagnostics, not exceptions
- Index building always completes (may be partial)

---

## Scope Boundaries

### M9 MAY:
- Read BoundPackBundle (M5 output)
- Build search indices for units, weapons, rules
- Build inverted indices for characteristics
- Emit diagnostics for indexing issues
- Provide lookup APIs

### M9 MUST NOT:
- Modify BoundPackBundle (read-only)
- Depend on M6/M7/M8 (no roster state in v1)
- Persist index to storage (caller's responsibility)
- Make network calls
- Interpret rule semantics (text stored as-is)

---

## Future Extensions (Not v1)

Deferred to future versions:
- **M6-aware indexing:** Index constraint states for validation queries
- **M7-aware indexing:** Index applicability for conditional display
- **M8-aware indexing:** Index effective values for roster-context queries
- **Full-text search:** Stemming, fuzzy matching, relevance scoring
- **Faceted navigation:** Hierarchical category browsing
- **Incremental updates:** Update index without full rebuild

---

## Required Tests

### Structural Invariants (MANDATORY)
- buildIndex returns IndexBundle with correct packId
- units list contains expected count and is sorted by key
- weapons list contains expected count and is sorted by key
- rules list contains expected count and is sorted by key

### Determinism
- Calling buildIndex twice with same input yields equal output (except indexedAt)
- All doc lists sorted alphabetically by key
- All lookup maps sorted alphabetically by key
- Diagnostics sorted by (sourceFileId, nodeIndex)

### Tokenization
- tokenize() is deterministic
- tokenize("Intercessor Squad") = ["intercessor", "squad"]
- tokenize handles edge cases (empty string, punctuation-only, etc.)

### Document Extraction
- UnitDoc characteristics are IndexedCharacteristic fields (not docs)
- WeaponDoc characteristics are IndexedCharacteristic fields (not docs)
- RuleDoc contains name and description

### Deduplication
- Duplicate entryId produces single UnitDoc + `DUPLICATE_DOC_KEY`
- Duplicate profileId produces single WeaponDoc + `DUPLICATE_DOC_KEY`
- Duplicate rule canonical key produces single RuleDoc + `DUPLICATE_RULE_CANONICAL_KEY`

### Linking
- Unit→weapon links resolve correctly
- Weapon→rule links resolve correctly
- Unresolved links emit `LINK_TARGET_MISSING`

### Lookup Correctness
- unitsByKey returns correct UnitDoc
- unitsByName returns all matching units (case-insensitive)
- weaponsByKey returns correct WeaponDoc
- rulesByKey returns correct RuleDoc
- byCharacteristicNameToken returns correct doc keys

### Roster Question Smoke Test
- Find a known unit name → UnitDoc returned
- List its weapons → weaponKeys resolve to WeaponDocs
- Fetch a core rule text → RuleDoc.description contains expected text

### Edge Cases
- Entry with no profiles → UnitDoc with empty characteristics
- Profile with unknown typeName → generic indexing + `UNKNOWN_PROFILE_TYPE`
- Rule with >1000 char description → truncated + `TRUNCATED_DESCRIPTION`
- Missing name → `MISSING_NAME` + key used as fallback

---

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:

- **Index Bundle** — Complete search index for a pack containing unit/weapon/rule documents with inverted index facets
- **Unit Doc** — Indexed document for a unit with characteristics as fields and keyword lists
- **Weapon Doc** — Indexed document for a weapon with characteristics as fields
- **Rule Doc** — Indexed document for a rule with description text
- **Indexed Characteristic** — Single characteristic name-value-token tuple as a field on UnitDoc/WeaponDoc (not a standalone doc)
- **Index Diagnostic** — Non-fatal issue detected during index building
- **Index Service** — Service that builds search index from BoundPackBundle

---

## Name Change Log Entries Required

Before implementation, add to `/docs/name_change_log.md`:

```
## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexBundle, UnitDoc, WeaponDoc, RuleDoc
- Reason: New M9 Index-Core document types for search index (3 doc kinds only).
- Approval reference: M9 Index-Core names proposal Rev 2

## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: CharacteristicDoc
- New name: IndexedCharacteristic
- Reason: Demoted from standalone doc to field type on UnitDoc/WeaponDoc per reviewer feedback.
- Approval reference: M9 Index-Core names proposal Rev 2

## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexDiagnostic
- Reason: New M9 Index-Core diagnostic type.
- Approval reference: M9 Index-Core names proposal Rev 2

## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexService
- Reason: New M9 Index-Core service for building search index.
- Approval reference: M9 Index-Core names proposal Rev 2

## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: MISSING_NAME, DUPLICATE_DOC_KEY, DUPLICATE_RULE_CANONICAL_KEY, UNKNOWN_PROFILE_TYPE, EMPTY_CHARACTERISTICS, TRUNCATED_DESCRIPTION, LINK_TARGET_MISSING
- Reason: New M9 Index-Core diagnostic codes (7 codes total, +2 from Rev 1).
- Approval reference: M9 Index-Core names proposal Rev 2
```

---

## Approval Checklist

- [x] Doc kinds (v1): UnitDoc, WeaponDoc, RuleDoc only
- [x] Characteristics are fields + inverted lookup, not docs
- [x] Diagnostic codes: 7 codes including DUPLICATE_RULE_CANONICAL_KEY, LINK_TARGET_MISSING
- [x] Deterministic ordering rule explicit: "All doc emission and lookups must be sorted by stable keys; no unordered iteration"
- [x] RuleDoc sources defined: BoundRule, ability profiles, weapon keywords
- [ ] Module layout approved (lib/modules/m9_index/)
- [ ] Service name approved (IndexService)
- [ ] Service method approved (buildIndex)
- [ ] M5-only input approved (no M6/M7/M8 dependence for v1)
- [ ] Glossary terms approved

---

## Implementation Sequencing

After doc approval:

1. Create model skeletons + `IndexService.buildIndex(BoundPackBundle)`
2. Implement deterministic tokenization (single function, tested)
3. Build RuleDoc dedupe map first (so weapons/units can link)
4. Build WeaponDocs, then UnitDocs, then link
5. Tests:
   - Determinism (ignore timestamp)
   - Rule dedupe (single RuleDoc for repeated core rule)
   - Unit→Weapon→Rule linking existence
   - "Roster question" smoke: find a known unit name, list its weapons, fetch a core rule text

**PROPOSED 2026-02-13 (Rev 2). Awaiting final approval.**

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
│   ├── characteristic_doc.dart
│   ├── keyword_doc.dart
│   └── index_diagnostic.dart
└── services/
    └── index_service.dart
```

---

## Core Types

### IndexBundle
**File:** `models/index_bundle.dart`

Complete search index for a pack.

**Fields:**
- `String packId` — Identity (from BoundPackBundle)
- `DateTime indexedAt` — Timestamp of index build
- `List<UnitDoc> units` — All unit documents
- `List<WeaponDoc> weapons` — All weapon documents
- `List<RuleDoc> rules` — All rule documents
- `Map<String, UnitDoc> unitsByKey` — Lookup by canonical key
- `Map<String, List<UnitDoc>> unitsByName` — Lookup by name (lowercase)
- `Map<String, WeaponDoc> weaponsByKey` — Lookup by canonical key
- `Map<String, List<WeaponDoc>> weaponsByName` — Lookup by name (lowercase)
- `Map<String, RuleDoc> rulesByKey` — Lookup by canonical key
- `Map<String, List<RuleDoc>> rulesByName` — Lookup by name (lowercase)
- `List<IndexDiagnostic> diagnostics` — Issues encountered
- `BoundPackBundle boundBundle` — Reference to input (for provenance chain)

**Rules:**
- Deterministic: same BoundPackBundle → identical IndexBundle (except indexedAt)
- All lookup maps sorted by key for determinism
- Name lookups use lowercase normalization
- Key lookups use canonical key (entryId or profileId)

---

### UnitDoc
**File:** `models/unit_doc.dart`

Indexed document for a unit (selectionEntry representing a model/unit).

**Fields:**
- `String key` — Canonical key (entryId from BoundEntry)
- `String name` — Display name (from BoundEntry.name)
- `String? normalizedName` — Lowercase searchable name
- `List<CharacteristicDoc> characteristics` — Unit stats (M, WS, BS, etc.)
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

---

### WeaponDoc
**File:** `models/weapon_doc.dart`

Indexed document for a weapon.

**Fields:**
- `String key` — Canonical key (entryId or profileId)
- `String name` — Display name
- `String? normalizedName` — Lowercase searchable name
- `List<CharacteristicDoc> characteristics` — Weapon stats (Range, Type, S, AP, D)
- `List<String> keywords` — Weapon abilities/keywords
- `String? weaponType` — Type classification (Melee, Ranged, etc.)
- `String sourceFileId` — Provenance
- `NodeRef sourceNode` — Provenance

**Extraction Rules:**
- One WeaponDoc per BoundProfile where typeName indicates weapon (e.g., "Ranged Weapons", "Melee Weapons")
- Characteristics extracted from profile characteristics list
- Weapon type derived from typeName or inferred from characteristics

---

### RuleDoc
**File:** `models/rule_doc.dart`

Indexed document for a rule.

**Fields:**
- `String key` — Canonical key (ruleId or infoLink targetId)
- `String name` — Display name
- `String? normalizedName` — Lowercase searchable name
- `String? description` — Rule text (may be truncated for index)
- `String? publicationRef` — Publication reference (book, page)
- `String sourceFileId` — Provenance
- `NodeRef sourceNode` — Provenance

**Extraction Rules:**
- One RuleDoc per unique rule element encountered
- Deduplication by key (first occurrence wins, per shadowing policy)
- Description may be truncated if excessively long (>1000 chars)

---

### CharacteristicDoc
**File:** `models/characteristic_doc.dart`

Single characteristic name-value pair for indexing.

**Fields:**
- `String name` — Characteristic name (e.g., "M", "WS", "S")
- `String value` — Characteristic value (raw string, not parsed)

**Rules:**
- Preserves raw value as string (no numeric parsing in index)
- Order preserved from source profile

---

### KeywordDoc (Optional — may merge with categories)
**File:** `models/keyword_doc.dart`

Indexed keyword/faction/ability for faceted search.

**Fields:**
- `String key` — Canonical key (categoryId)
- `String name` — Display name
- `String? normalizedName` — Lowercase searchable name
- `String? keywordType` — Classification (Faction, Unit Type, Ability, etc.)

**Rules:**
- Derived from BoundCategory entries
- Enables faceted search ("show all Infantry", "show all IMPERIUM")

---

### IndexDiagnostic
**File:** `models/index_diagnostic.dart`

Non-fatal issue detected during index building.

**Fields:**
- `String code` — Diagnostic code (closed set)
- `String message` — Human-readable description
- `String sourceFileId` — File where issue occurred
- `NodeRef? sourceNode` — Node where issue occurred
- `String? key` — Key involved (if applicable)
- `String? name` — Name involved (if applicable)

**Diagnostic Codes:**

| Code | Condition | Behavior |
|------|-----------|----------|
| `MISSING_NAME` | Entry/profile has empty or missing name | Doc created with key as fallback name |
| `DUPLICATE_DOC_KEY` | Same key encountered twice | First wins, diagnostic emitted |
| `UNKNOWN_PROFILE_TYPE` | Profile typeName not recognized | Profile indexed as generic |
| `EMPTY_CHARACTERISTICS` | Unit/weapon has no characteristics | Doc created with empty list |
| `TRUNCATED_DESCRIPTION` | Rule description exceeded max length | Description truncated |

**Rules:**
- All diagnostics non-fatal
- Index building continues on all issues
- Diagnostics accumulated and returned in IndexBundle

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

**Behavior:**
1. Validate input (check BoundPackBundle integrity)
2. Traverse all BoundEntry roots
3. For each entry, determine doc type (unit, weapon, upgrade, etc.)
4. Extract characteristics from associated profiles
5. Build UnitDoc/WeaponDoc for qualifying entries
6. Traverse all rules, build RuleDoc for each unique rule
7. Build lookup maps (sorted for determinism)
8. Aggregate diagnostics

**Determinism Contract:**
- Same BoundPackBundle → identical IndexBundle (except indexedAt)
- Entry traversal order: boundBundle.rootEntries list order
- Profile traversal order: entry.profiles list order
- All maps sorted alphabetically by key

---

## Profile Type Classification

M9 must classify profiles to determine document type. Initial heuristics (configurable per game system):

| typeName Pattern | Document Type |
|------------------|---------------|
| "Unit", "Model" | UnitDoc (characteristics) |
| "Ranged Weapons", "Melee Weapons", "Weapon" | WeaponDoc |
| "Abilities", "Wargear", "Psychic Power" | Indexed as keywords/abilities |

**Unknown profile types:** Indexed generically, diagnostic emitted.

---

## Tokenization Rules

For search functionality, names are tokenized:

1. **Normalization:** lowercase, trim whitespace
2. **Token splitting:** split on whitespace and punctuation
3. **No stemming:** exact token matching (v1 simplicity)

Example: "Intercessor Squad" → tokens: ["intercessor", "squad"]

Tokenization is deterministic given same input.

---

## Deduplication Strategy

### Units
- Key = entryId
- Duplicate entryId: first wins (per file resolution order)

### Weapons
- Key = profileId (or entryId if profile nested)
- Duplicate key: first wins, DUPLICATE_DOC_KEY diagnostic

### Rules
- Key = ruleId or targetId of infoLink
- Duplicate key: first wins (same rule referenced multiple times)
- No diagnostic for rule deduplication (expected behavior)

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
- Emit diagnostics for indexing issues
- Provide lookup APIs

### M9 MUST NOT:
- Modify BoundPackBundle (read-only)
- Depend on M6/M7/M8 (no roster state)
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
- units list contains expected count
- weapons list contains expected count
- rules list contains expected count

### Determinism
- Calling buildIndex twice with same input yields equal output (except indexedAt)
- Lookup maps are sorted alphabetically

### Document Extraction
- UnitDoc characteristics match source profile
- WeaponDoc characteristics match source profile
- RuleDoc contains name and description

### Deduplication
- Duplicate entryId produces single UnitDoc + diagnostic
- Duplicate profileId produces single WeaponDoc + diagnostic
- Duplicate ruleId produces single RuleDoc (no diagnostic)

### Lookup Correctness
- unitsByKey returns correct UnitDoc
- unitsByName returns all matching units (case-insensitive)
- weaponsByKey returns correct WeaponDoc
- rulesByKey returns correct RuleDoc

### Edge Cases
- Entry with no profiles → UnitDoc with empty characteristics
- Profile with unknown typeName → generic indexing + diagnostic
- Rule with >1000 char description → truncated + diagnostic

---

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:

- **Index Bundle** — Complete search index for a pack containing unit/weapon/rule documents
- **Unit Doc** — Indexed document for a unit with characteristics and keywords
- **Weapon Doc** — Indexed document for a weapon with characteristics
- **Rule Doc** — Indexed document for a rule with description
- **Characteristic Doc** — Single characteristic name-value pair for indexing
- **Index Diagnostic** — Non-fatal issue detected during index building
- **Index Service** — Service that builds search index from BoundPackBundle

---

## Name Change Log Entries Required

Before implementation, add to `/docs/name_change_log.md`:

```
## 2026-02-12 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexBundle, UnitDoc, WeaponDoc, RuleDoc, CharacteristicDoc
- Reason: New M9 Index-Core document types for search index.
- Approval reference: M9 Index-Core names proposal Rev 1

## 2026-02-12 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexDiagnostic
- Reason: New M9 Index-Core diagnostic type.
- Approval reference: M9 Index-Core names proposal Rev 1

## 2026-02-12 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexService
- Reason: New M9 Index-Core service for building search index.
- Approval reference: M9 Index-Core names proposal Rev 1

## 2026-02-12 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: MISSING_NAME, DUPLICATE_DOC_KEY, UNKNOWN_PROFILE_TYPE, EMPTY_CHARACTERISTICS, TRUNCATED_DESCRIPTION
- Reason: New M9 Index-Core diagnostic codes (5 codes total).
- Approval reference: M9 Index-Core names proposal Rev 1
```

---

## Approval Checklist

- [ ] Module layout approved (lib/modules/m9_index/)
- [ ] Core model names approved (IndexBundle, UnitDoc, WeaponDoc, RuleDoc, CharacteristicDoc, IndexDiagnostic)
- [ ] Service name approved (IndexService)
- [ ] Service method approved (buildIndex)
- [ ] M5-only input approved (no M6/M7/M8 dependence for v1)
- [ ] Determinism contract approved
- [ ] Deduplication rules approved
- [ ] Diagnostic codes approved (5 codes)
- [ ] Glossary terms approved

**PROPOSED 2026-02-12. Awaiting approval.**

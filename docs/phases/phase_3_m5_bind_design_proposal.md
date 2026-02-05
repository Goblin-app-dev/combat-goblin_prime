# Phase 3 — M5 Bind Design Proposal

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **PROPOSAL** — awaiting approval

---

## Problem Statement

M4 Link produces a LinkedPackBundle containing:
- SymbolTable (cross-file ID registry)
- ResolvedRefs (link elements → targets)
- LinkDiagnostics (resolution issues)
- WrappedPackBundle (immutable node graph)

This is still a low-level XML-shaped representation. Downstream consumers (UI, army builder) need:
- Named entities they can query (entries, profiles, categories)
- Links already followed (no manual resolution)
- A stable query surface (lookup by ID, list by type, navigate relationships)

**M5 Bind** converts LinkedPackBundle into a bound, queryable representation where cross-file references are already resolved and entities are typed.

---

## Inputs

- `LinkedPackBundle` (from M4 Link)

## Outputs

- `BoundPackBundle` — complete M5 output containing:
  - Bound entities (entries, profiles, categories, costs)
  - Query surface for lookups
  - Bind diagnostics for semantic issues
  - Reference to source LinkedPackBundle

---

## Strict Non-Goals

M5 MUST NOT:

1. **No UI** — M5 produces data structures, not widgets or display logic
2. **No persistence** — M5 operates in-memory; storage remains in M1
3. **No network** — M5 is offline; network operations remain in M1
4. **No roster state** — M5 binds the data model; roster building is M6+
5. **No constraint evaluation** — M5 represents constraints; evaluation requires roster state
6. **No modifier evaluation** — M5 stores modifiers; evaluation requires roster context
7. **No XML re-parsing** — M5 reads WrappedNodes, never touches raw XML

---

## Initial Entity Scope (Minimal Slice)

M5 Phase 3 defines these entities. Additional entity types may be added in future phases.

### BoundEntry

Represents a selectionEntry (or resolved entryLink).

**Source tags:** `selectionEntry`, `selectionEntryGroup`, `entryLink` (when resolved)

**Contains:**
- Entry ID and name
- Resolved child entries (nested selectionEntries, resolved entryLinks)
- Resolved profiles (via infoLink or nested profile)
- Resolved categories (via categoryLink or nested categoryEntry)
- Costs (nested cost elements)
- Constraints (nested constraint elements, NOT evaluated)
- Source provenance (fileId, NodeRef)

### BoundProfile

Represents a profile definition with characteristics.

**Source tags:** `profile` (or resolved infoLink to profile)

**Contains:**
- Profile ID and name
- Profile type ID (links to profileType)
- Characteristics (list of name-value pairs)
- Source provenance (fileId, NodeRef)

### BoundCategory

Represents a category definition.

**Source tags:** `categoryEntry`, `categoryLink` (when resolved)

**Contains:**
- Category ID and name
- Primary flag (is this entry's primary category?)
- Source provenance (fileId, NodeRef)

### BoundCost

Represents a cost value.

**Source tags:** `cost`

**Contains:**
- Cost type ID (links to costType in gameSystem)
- Cost value (numeric)
- Source provenance (fileId, NodeRef)

### BoundConstraint

Represents a constraint (NOT evaluated).

**Source tags:** `constraint`

**Contains:**
- Constraint type (min, max, etc.)
- Field, scope, value
- Source provenance (fileId, NodeRef)

**M5 stores constraint data. M5 does NOT evaluate constraints.**

---

## Scope and Shadowing Policy

### File Precedence (Shadowing)

When the same ID appears in multiple files, M5 uses **first-match-wins** based on file resolution order:

1. **primaryCatalog** (highest precedence)
2. **dependencyCatalogs** (in list order)
3. **gameSystem** (lowest precedence)

**Rationale:** Catalogues extend/override gameSystem definitions. Primary catalogue is the user's chosen faction and takes precedence over shared dependencies.

### Duplicate ID Handling

M4 reports `DUPLICATE_ID_REFERENCE` when an ID resolves to multiple targets.

M5 behavior:
- Use **first target** from ResolvedRef.targets (already ordered by file precedence)
- Emit `SHADOWED_DEFINITION` diagnostic noting the shadowed targets
- Do NOT fail; binding continues with first match

---

## Unresolved Target Handling Policy

M4 reports `UNRESOLVED_TARGET` when a link's targetId is not found.

M5 behavior for each link type:

| Link Type | Unresolved Behavior |
|-----------|-------------------|
| `entryLink` | Emit `UNRESOLVED_ENTRY_LINK` diagnostic, omit from parent's children list |
| `infoLink` | Emit `UNRESOLVED_INFO_LINK` diagnostic, omit from profiles list |
| `categoryLink` | Emit `UNRESOLVED_CATEGORY_LINK` diagnostic, omit from categories list |
| `catalogueLink` | M4 already reported; M5 ignores (catalogueLinks are file-level, not entity-level) |

**Policy:** Unresolved links are skipped with a diagnostic. They do NOT cause binding failure. Downstream consumers see the diagnostic and can decide how to handle (degrade, warn user, etc.).

---

## Constraint Evaluation Boundary

**M5 represents constraints. M5 does NOT evaluate constraints.**

Constraints require roster state to evaluate:
- "min 1" requires knowing how many are selected
- "max 3" requires knowing current selection count
- Conditions check roster properties

M5 binds constraint definitions into `BoundConstraint` objects. Evaluation is deferred to the roster layer (M6+).

---

## Query Surface

BoundPackBundle provides these query methods:

```
// Lookup by ID
BoundEntry? entryById(String id)
BoundProfile? profileById(String id)
BoundCategory? categoryById(String id)

// List all
Iterable<BoundEntry> get allEntries
Iterable<BoundProfile> get allProfiles
Iterable<BoundCategory> get allCategories

// Relationship queries
Iterable<BoundEntry> entriesInCategory(String categoryId)
Iterable<BoundProfile> profilesForEntry(String entryId)
Iterable<BoundCategory> categoriesForEntry(String entryId)
Iterable<BoundCost> costsForEntry(String entryId)
```

**Query contracts:**
- Lookups return null if ID not found (no throwing)
- Relationship queries return empty iterable if source not found
- All queries are O(1) or O(n) in result size (indexed lookups)

---

## Determinism Contract

M5 guarantees:
- Same LinkedPackBundle → identical BoundPackBundle
- Query results are ordered deterministically (file order → node order)
- No dependence on runtime hash ordering
- Diagnostic ordering matches entity binding order

---

## Failure and Diagnostic Taxonomy

### BindDiagnostic (non-fatal)

Semantic issues that do not prevent binding.

**Diagnostic codes (initial set):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `UNRESOLVED_ENTRY_LINK` | entryLink target not found | Skip link, continue binding |
| `UNRESOLVED_INFO_LINK` | infoLink target not found | Skip link, continue binding |
| `UNRESOLVED_CATEGORY_LINK` | categoryLink target not found | Skip link, continue binding |
| `SHADOWED_DEFINITION` | ID matched multiple targets, using first | Log shadowed targets, use first |
| `INVALID_PROFILE_TYPE` | profile references unknown profileType | Bind profile without type info |
| `INVALID_COST_TYPE` | cost references unknown costType | Bind cost without type info |

### BindFailure (fatal)

Exception for corrupted input or internal bugs.

**BindFailure is thrown ONLY for:**
1. **Corrupted M4 input** — LinkedPackBundle violates frozen M4 contracts
2. **Internal invariant violation** — M5 implementation bug detected

**BindFailure is NOT thrown for:**
- Unresolved links → diagnostic
- Shadowed definitions → diagnostic
- Missing type references → diagnostic

**In normal operation, no BindFailure is thrown.**

---

## Module Layout

### Module
- Folder: `lib/modules/m5_bind/`
- Barrel: `lib/modules/m5_bind/m5_bind.dart`

### Public Exports (barrel only)
- `services/bind_service.dart`
- `models/bound_pack_bundle.dart`
- `models/bound_entry.dart`
- `models/bound_profile.dart`
- `models/bound_category.dart`
- `models/bound_cost.dart`
- `models/bound_constraint.dart`
- `models/bind_diagnostic.dart`
- `models/bind_failure.dart`

### File Layout
```
lib/modules/m5_bind/
├── m5_bind.dart
├── models/
│   ├── bound_pack_bundle.dart
│   ├── bound_entry.dart
│   ├── bound_profile.dart
│   ├── bound_category.dart
│   ├── bound_cost.dart
│   ├── bound_constraint.dart
│   ├── bind_diagnostic.dart
│   └── bind_failure.dart
└── services/
    └── bind_service.dart
```

---

## Open Questions for SME Review

1. **Entry grouping:** Should `selectionEntryGroup` become a distinct `BoundEntryGroup` type, or be treated as a special kind of `BoundEntry`?

2. **Rules and InfoGroups:** Should M5 bind `rule` elements and `infoGroup` containers, or defer to a later phase?

3. **ProfileType/CostType lookup:** These are defined in gameSystem. Should M5 build a type registry, or just store the type IDs and let consumers look them up?

4. **Shared entries:** Some entries are defined in shared catalogues (dependencies) and used by multiple primary catalogues. Should M5 track which primary catalogue an entry "belongs to", or just bind everything flat?

5. **Hidden entries:** Entries can have `hidden="true"`. Should M5 filter these out, or bind them with a hidden flag?

---

## Required Tests (when approved for implementation)

### Structural Invariants
- All selectionEntry nodes produce a BoundEntry
- All profile nodes produce a BoundProfile
- All categoryEntry nodes produce a BoundCategory
- Resolved entryLinks appear as BoundEntry in parent's children

### Query Contracts
- entryById returns correct entry or null
- allEntries includes all bound entries
- entriesInCategory returns entries with that category

### Diagnostic Invariants
- Unresolved entryLink → UNRESOLVED_ENTRY_LINK diagnostic
- Multi-target resolution → SHADOWED_DEFINITION diagnostic

### Determinism
- Binding same input twice yields identical output
- Query results ordered deterministically

### No-Failure Policy
- Unresolved links do not throw BindFailure
- Missing type references do not throw BindFailure

---

## Glossary Additions Required (if approved)

- **Bound Pack Bundle** — Complete M5 output with bound entities and query surface
- **Bound Entry** — Interpreted entry with resolved children, profiles, categories, costs
- **Bound Profile** — Profile definition with characteristics
- **Bound Category** — Category definition with primary flag
- **Bound Cost** — Cost value with type reference
- **Bound Constraint** — Constraint definition (not evaluated)
- **Bind Diagnostic** — Non-fatal semantic issue detected during binding
- **Bind Failure** — Fatal exception for M5 corruption
- **Bind Service** — Service converting LinkedPackBundle to BoundPackBundle

---

## Approval Checklist

- [ ] Problem statement approved
- [ ] Input/Output contract approved
- [ ] Non-goals approved
- [ ] Initial entity scope approved (BoundEntry, BoundProfile, BoundCategory, BoundCost, BoundConstraint)
- [ ] Shadowing policy approved (first-match-wins)
- [ ] Unresolved target handling approved (skip with diagnostic)
- [ ] Constraint boundary approved (represent, not evaluate)
- [ ] Query surface approved
- [ ] Diagnostic codes approved
- [ ] Module layout approved

**NO CODE UNTIL APPROVAL.**

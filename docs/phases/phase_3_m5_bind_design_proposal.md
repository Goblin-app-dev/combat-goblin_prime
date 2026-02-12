# Phase 3 — M5 Bind Design Proposal

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)

### Controlled Unfreeze History

| Date | Change | Reason |
|------|--------|--------|
| 2026-02-12 | Bugfix: characteristic extraction in `_bindProfileFromNode` | Contract promised `BoundProfile.characteristics` but extraction loop was empty. Fixed by passing `WrappedFile` instead of `fileId` string to resolve child NodeRefs. No new types, no semantic changes. |

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

**M5 does NOT expose EntryGroup as a first-class entity in the initial slice.** Group membership is represented via BoundEntry.isGroup flag and parent-child relationships.

**Rules are deferred.** M5 does not bind `rule` elements in the initial slice. If needed, add BoundRule in a future phase with explicit eligibility and query contract.

**InfoGroups are deferred.** M5 does not bind `infoGroup` containers (presentation/organization concern).

### Tag Eligibility (MANDATORY)

Each bound type binds ONLY nodes with specific tagNames. This prevents accidental binding of wrong element types that happen to share an ID.

| Bound Type | Eligible tagNames |
|------------|-------------------|
| BoundEntry | `selectionEntry`, `selectionEntryGroup` |
| BoundProfile | `profile` |
| BoundCategory | `categoryEntry` |
| BoundCost | `cost` |
| BoundConstraint | `constraint` |

**entryLink, infoLink, categoryLink** are NOT directly bound. They are followed to their resolved targets, and the target node is bound if its tagName is eligible.

### BoundEntry

Represents a selectionEntry or selectionEntryGroup.

**Eligible tagNames:** `selectionEntry`, `selectionEntryGroup`

**Contains:**
- Entry ID and name
- `isGroup` flag (true if tagName was `selectionEntryGroup`)
- `isHidden` flag (true if `hidden="true"` attribute present)
- Resolved child entries (nested selectionEntries, resolved entryLinks)
- Resolved profiles (via infoLink or nested profile)
- Resolved categories (via categoryLink or nested categoryEntry)
- Costs (nested cost elements)
- Constraints (nested constraint elements, NOT evaluated)
- Source provenance (fileId, NodeRef)

### BoundProfile

Represents a profile definition with characteristics.

**Eligible tagNames:** `profile`

**Contains:**
- Profile ID and name
- Profile type ID (string, stored as-is; no registry lookup)
- Profile type name (string, stored as-is if available)
- Characteristics (list of name-value pairs)
- Source provenance (fileId, NodeRef)

**M5 does NOT build a type registry for profileType. Type IDs are stored as strings for downstream consumption.**

### BoundCategory

Represents a category definition.

**Eligible tagNames:** `categoryEntry`

**Contains:**
- Category ID and name
- Primary flag (true if `primary="true"` attribute present)
- Source provenance (fileId, NodeRef)

### BoundCost

Represents a cost value.

**Eligible tagNames:** `cost`

**Contains:**
- Cost type ID (string, stored as-is; no registry lookup)
- Cost type name (string, stored as-is if available)
- Cost value (numeric)
- Source provenance (fileId, NodeRef)

**M5 does NOT build a type registry for costType. Type IDs are stored as strings for downstream consumption.**

### BoundConstraint

Represents a constraint (NOT evaluated).

**Eligible tagNames:** `constraint`

**Contains:**
- Constraint type (min, max, etc.)
- Field, scope, value
- Source provenance (fileId, NodeRef)

**BoundConstraint captures raw fields and linked targets only; no truth evaluation.**

---

## Scope and Shadowing Policy

### Definition of "Match"

A **match** for binding occurs when:
1. The node's `id` attribute equals the target ID being resolved
2. The node's `tagName` is in the eligible set for the binding type (see Tag Eligibility table)

**Both conditions must be true.** A node with matching ID but wrong tagName is NOT a match and is skipped.

### File Precedence (Shadowing)

When the same ID appears in multiple files, M5 uses **first-match-wins** based on file resolution order:

1. **primaryCatalog** (highest precedence)
2. **dependencyCatalogs** (in list order)
3. **gameSystem** (lowest precedence)

**Rationale:** Catalogues extend/override gameSystem definitions. Primary catalogue is the user's chosen faction and takes precedence over shared dependencies.

### Within-File Tie-Break

If `idIndex[id]` contains multiple NodeRefs within the same file (duplicates allowed by M3):
- **First in node order wins** — use the earliest NodeRef in `WrappedFile.nodes` order
- Emit `SHADOWED_DEFINITION` diagnostic noting the skipped duplicates

### Cross-File Resolution

M5 uses M4's ResolvedRef.targets list, which is already ordered:
1. By file resolution order (primaryCatalog → dependencyCatalogs → gameSystem)
2. Within each file: by `WrappedFile.nodes` index order

M5 iterates targets in order and selects the **first node where tagName is eligible** for the binding type.

### Duplicate ID Handling

M4 reports `DUPLICATE_ID_REFERENCE` when an ID resolves to multiple targets.

M5 behavior:
- Iterate ResolvedRef.targets in order
- Select **first node with eligible tagName** for the binding type
- Emit `SHADOWED_DEFINITION` diagnostic noting all skipped targets
- Do NOT fail; binding continues with first eligible match

**Important:** This can drop data when different files define the same ID. M5 does NOT merge definitions. Provenance (sourceFileId) on each bound entity enables debugging.

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

### Query Semantics on Missing/Partial Binding

| Query | ID not found | Source exists but relationship empty |
|-------|--------------|-------------------------------------|
| `entryById(id)` | Returns `null` | N/A |
| `profileById(id)` | Returns `null` | N/A |
| `categoryById(id)` | Returns `null` | N/A |
| `allEntries` | N/A | Returns empty iterable |
| `allProfiles` | N/A | Returns empty iterable |
| `allCategories` | N/A | Returns empty iterable |
| `entriesInCategory(id)` | Returns empty iterable | Returns empty iterable |
| `profilesForEntry(id)` | Returns empty iterable | Returns empty iterable |
| `categoriesForEntry(id)` | Returns empty iterable | Returns empty iterable |
| `costsForEntry(id)` | Returns empty iterable | Returns empty iterable |

**No query throws on missing data.** All return null or empty.

### Deterministic Ordering for List Queries

All list-returning queries return results in **binding order**:
1. File resolution order (primaryCatalog → dependencyCatalogs → gameSystem)
2. Within each file: node index order (pre-order depth-first traversal from M3)

| Query | Ordering |
|-------|----------|
| `allEntries` | Binding order |
| `allProfiles` | Binding order |
| `allCategories` | Binding order |
| `entriesInCategory(id)` | Binding order (filtered) |
| `profilesForEntry(id)` | Binding order (filtered) |
| `categoriesForEntry(id)` | Binding order (filtered) |
| `costsForEntry(id)` | Binding order (filtered) |

**No hash-map iteration order leaks.** Results are deterministic.

### Hidden Content Policy

Queries return **all bound content including hidden entries**.

M5 binds entries with `hidden="true"` and exposes `BoundEntry.isHidden` flag. Filtering hidden content is a UI/UX concern, not M5's responsibility.

### Query Performance

- ID lookups: O(1) via indexed maps
- List queries: O(n) in result size
- Relationship queries: O(n) in result size (may require index scan)

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

## SME Decisions (Resolved)

The following questions were raised in the initial proposal and resolved by SME review:

1. **Entry grouping:** Treat as `BoundEntry` with `isGroup` flag. Do NOT introduce `BoundEntryGroup` as a distinct type in the initial slice.

2. **Rules and InfoGroups:** Rules deferred to future phase. InfoGroups deferred (presentation concern). M5 initial slice does not bind `rule` or `infoGroup` elements.

3. **ProfileType/CostType lookup:** Store type IDs as strings. Do NOT build a type registry in M5. Downstream can look up types if needed.

4. **Shared entries:** Bind with provenance. Each bound entity includes `sourceFileId` to show which file it came from. Shadowing policy determines which definition "wins" for duplicate IDs.

5. **Hidden entries:** Bind with `isHidden` flag. Do NOT filter in M5. Filtering is UI/UX policy.

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
- [ ] Tag eligibility lists approved (per bound type)
- [ ] Match definition approved (id + tagName)
- [ ] Within-file tie-break approved (first in node order)
- [ ] Shadowing policy approved (first-match-wins with type gating)
- [ ] Unresolved target handling approved (skip with diagnostic)
- [ ] Constraint boundary approved (represent, not evaluate)
- [ ] Query surface approved
- [ ] Query semantics approved (null/empty on missing)
- [ ] Deterministic ordering approved (binding order)
- [ ] Hidden content policy approved (bind with flag, don't filter)
- [ ] Diagnostic codes approved
- [ ] Module layout approved

**NO CODE UNTIL APPROVAL.**

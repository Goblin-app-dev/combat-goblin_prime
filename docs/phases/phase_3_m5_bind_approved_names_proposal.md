# Phase 3 — M5 Bind Approved Names

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **PROPOSED** — awaiting approval

---

## Purpose

M5 Bind converts `LinkedPackBundle` (from M4) into a `BoundPackBundle` containing:

- Typed entities (entries, profiles, categories, costs, constraints)
- Resolved cross-file references (links already followed)
- Query surface for lookups and navigation
- Bind diagnostics for semantic issues

**M5 interprets structure into entities. M5 does NOT evaluate constraints or modifiers.**

---

## Scope Boundaries

### M5 MAY:
- Bind selectionEntry, selectionEntryGroup, entryLink into BoundEntry
- Bind profile elements into BoundProfile
- Bind categoryEntry, categoryLink into BoundCategory
- Bind cost elements into BoundCost
- Bind constraint elements into BoundConstraint (data only, not evaluated)
- Follow resolved links to assemble entity relationships
- Apply shadowing policy (first-match-wins by file order)
- Emit diagnostics for unresolved links and shadowed definitions
- Provide query methods for entity lookup

### M5 MUST NOT:
- Evaluate constraints (requires roster state)
- Evaluate modifiers or conditions (requires roster state)
- Touch raw XML (uses WrappedNode only)
- Persist data (storage is M1's domain)
- Make network calls (network is M1's domain)
- Produce UI elements (UI is downstream)
- Bind `rule` elements (deferred to future phase)
- Bind `infoGroup` containers (presentation concern, deferred)
- Build type registries for profileType/costType (store IDs as strings only)

---

## Tag Eligibility (MANDATORY)

Each bound type binds ONLY nodes with specific tagNames. This prevents accidental binding of wrong element types that happen to share an ID.

| Bound Type | Eligible tagNames |
|------------|-------------------|
| BoundEntry | `selectionEntry`, `selectionEntryGroup` |
| BoundProfile | `profile` |
| BoundCategory | `categoryEntry` |
| BoundCost | `cost` |
| BoundConstraint | `constraint` |

**Link elements (entryLink, infoLink, categoryLink)** are NOT directly bound. They are followed to their resolved targets, and the target node is bound if its tagName is eligible.

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

## Core Types

### BoundPackBundle
**File:** `models/bound_pack_bundle.dart`

Complete M5 output.

**Fields:**
- `String packId`
- `DateTime boundAt`
- `List<BoundEntry> entries` — all bound entries (flat list)
- `List<BoundProfile> profiles` — all bound profiles (flat list)
- `List<BoundCategory> categories` — all bound categories (flat list)
- `List<BindDiagnostic> diagnostics`
- `LinkedPackBundle linkedBundle` — reference to M4 input (immutable)

**Query methods:**
- `BoundEntry? entryById(String id)`
- `BoundProfile? profileById(String id)`
- `BoundCategory? categoryById(String id)`
- `Iterable<BoundEntry> get allEntries`
- `Iterable<BoundProfile> get allProfiles`
- `Iterable<BoundCategory> get allCategories`
- `Iterable<BoundEntry> entriesInCategory(String categoryId)`
- `Iterable<BoundProfile> profilesForEntry(String entryId)`
- `Iterable<BoundCategory> categoriesForEntry(String entryId)`
- `Iterable<BoundCost> costsForEntry(String entryId)`

**Query Semantics (Missing/Partial Binding):**

| Query | ID not found | Relationship empty |
|-------|--------------|-------------------|
| `*ById(id)` | Returns `null` | N/A |
| `all*` getters | N/A | Returns empty iterable |
| `*ForEntry(id)` | Returns empty iterable | Returns empty iterable |
| `entriesInCategory(id)` | Returns empty iterable | Returns empty iterable |

**No query throws on missing data.** All return null or empty.

**Deterministic Ordering:**
All list-returning queries return results in **binding order**:
1. File resolution order (primaryCatalog → dependencyCatalogs → gameSystem)
2. Within each file: node index order (pre-order depth-first from M3)

**Hidden Content:**
Queries return all bound content **including hidden entries**. Use `BoundEntry.isHidden` to filter.

**Rules:**
- One-to-one correspondence with input LinkedPackBundle
- Does not modify linked nodes
- Preserves provenance chain (M5 → M4 → M3 → M2 → M1)

---

### BoundEntry
**File:** `models/bound_entry.dart`

Interpreted entry (selectionEntry or selectionEntryGroup).

**Eligible tagNames:** `selectionEntry`, `selectionEntryGroup`

**Fields:**
- `String id`
- `String name`
- `bool isGroup` — true if source was selectionEntryGroup
- `bool isHidden` — true if source had hidden="true"
- `List<BoundEntry> children` — nested entries and resolved entryLinks
- `List<BoundProfile> profiles` — nested profiles and resolved infoLinks
- `List<BoundCategory> categories` — via categoryEntry and resolved categoryLinks
- `List<BoundCost> costs` — nested cost elements
- `List<BoundConstraint> constraints` — nested constraint elements
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- entryLinks are followed; target entry appears as child
- infoLinks to profiles are followed; target profile appears in profiles list
- categoryLinks are followed; target category appears in categories list
- Unresolved links are omitted (with diagnostic)

---

### BoundProfile
**File:** `models/bound_profile.dart`

Profile definition with characteristics.

**Eligible tagNames:** `profile`

**Fields:**
- `String id`
- `String name`
- `String? typeId` — references profileType (may be null if type not found)
- `String? typeName` — profileType name (may be null if type not found)
- `List<({String name, String value})> characteristics` — ordered name-value pairs
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- Characteristics are extracted from nested characteristic elements
- Order matches source document order
- Missing typeId emits INVALID_PROFILE_TYPE diagnostic

---

### BoundCategory
**File:** `models/bound_category.dart`

Category definition.

**Eligible tagNames:** `categoryEntry`

**Fields:**
- `String id`
- `String name`
- `bool isPrimary` — true if primary="true" on categoryEntry/categoryLink
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

---

### BoundCost
**File:** `models/bound_cost.dart`

Cost value.

**Eligible tagNames:** `cost`

**Fields:**
- `String typeId` — references costType
- `String? typeName` — costType name (may be null if type not found)
- `double value` — numeric cost value
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- Missing typeId emits INVALID_COST_TYPE diagnostic
- Value parsed from `value` attribute

---

### BoundConstraint
**File:** `models/bound_constraint.dart`

Constraint definition (not evaluated).

**Eligible tagNames:** `constraint`

**Fields:**
- `String type` — constraint type (min, max, etc.)
- `String field` — field being constrained
- `String scope` — scope of constraint
- `int value` — constraint value
- `String? id` — optional constraint ID
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- **BoundConstraint captures raw fields and linked targets only; no truth evaluation.**
- Constraint data is stored, NOT evaluated
- Evaluation requires roster state (deferred to M6+)

---

### BindDiagnostic
**File:** `models/bind_diagnostic.dart`

Non-fatal semantic issue.

**Fields:**
- `String code` — diagnostic code (closed set)
- `String message` — human-readable description
- `String sourceFileId` — file where issue occurred
- `NodeRef? sourceNode` — node where issue occurred (if applicable)
- `String? targetId` — the ID involved (if applicable)

**Diagnostic Codes (closed set):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `UNRESOLVED_ENTRY_LINK` | entryLink targetId not found | Skip link, omit from children |
| `UNRESOLVED_INFO_LINK` | infoLink targetId not found | Skip link, omit from profiles |
| `UNRESOLVED_CATEGORY_LINK` | categoryLink targetId not found | Skip link, omit from categories |
| `SHADOWED_DEFINITION` | ID matched multiple targets | Use first target, log shadowed |
| `INVALID_PROFILE_TYPE` | profile.typeId not found | Bind profile, typeId/typeName null |
| `INVALID_COST_TYPE` | cost.typeId not found | Bind cost, typeName null |

**Rules:**
- Diagnostics are accumulated, never thrown
- All diagnostics are non-fatal
- New diagnostic codes require doc + glossary update

---

### BindFailure
**File:** `models/bind_failure.dart`

Fatal exception for M5 failures.

**Fields:**
- `String message`
- `String? fileId`
- `String? details`

**Fatality Policy:**

BindFailure is thrown ONLY for:
1. Corrupted M4 input — LinkedPackBundle violates frozen M4 contracts
2. Internal invariant violation — M5 implementation bug

BindFailure is NOT thrown for:
- Unresolved links → diagnostic
- Shadowed definitions → diagnostic
- Missing type references → diagnostic

**In normal operation, no BindFailure is thrown.**

---

## Services

### BindService
**File:** `services/bind_service.dart`

**Method:**
```dart
Future<BoundPackBundle> bindBundle({
  required LinkedPackBundle linkedBundle,
}) async
```

**Behavior:**
1. Initialize entity collections and indices
2. Traverse all files in file resolution order (primary → deps → gamesystem)
3. For each selectionEntry, selectionEntryGroup: create BoundEntry
4. For each profile: create BoundProfile
5. For each categoryEntry: create BoundCategory
6. Resolve entryLinks, infoLinks, categoryLinks using M4's ResolvedRefs
7. Apply shadowing policy for duplicate IDs (first-match-wins)
8. Build query indices
9. Return BoundPackBundle with all entities and diagnostics

---

## Shadowing Policy

### Definition of "Match"

A **match** for binding occurs when:
1. The node's `id` attribute equals the target ID being resolved
2. The node's `tagName` is in the eligible set for the binding type (see Tag Eligibility)

**Both conditions must be true.** A node with matching ID but wrong tagName is NOT a match.

### File Precedence

**First-match-wins** based on file resolution order:

1. primaryCatalog (highest precedence)
2. dependencyCatalogs (in list order)
3. gameSystem (lowest precedence)

### Within-File Tie-Break

If multiple nodes with the same ID exist in one file:
- **First in node order wins** — earliest NodeRef in `WrappedFile.nodes` order
- Emit SHADOWED_DEFINITION diagnostic for skipped duplicates

### Cross-File Resolution

M5 iterates M4's ResolvedRef.targets in order and selects the **first node where tagName is eligible** for the binding type.

When M4's ResolvedRef contains multiple targets:
- Iterate targets in order (already sorted by file precedence → node order)
- Select first with eligible tagName
- Emit SHADOWED_DEFINITION diagnostic listing all skipped targets

**M5 does NOT merge definitions.** Provenance (sourceFileId) enables debugging when data is dropped.

---

## Determinism Contract

M5 guarantees:
- Same LinkedPackBundle → identical BoundPackBundle
- Entity ordering matches file resolution order → node order
- Query results ordered deterministically
- No hash-map iteration leaks
- Stable diagnostic ordering

---

## Required Tests

### Structural Invariants (MANDATORY)
- Every selectionEntry produces a BoundEntry
- Every profile produces a BoundProfile
- Every categoryEntry produces a BoundCategory
- Resolved entryLinks appear in parent's children list

### Query Contracts
- entryById returns correct entry or null
- allEntries contains all bound entries
- entriesInCategory returns correct subset

### Diagnostic Invariants
- Unresolved entryLink → UNRESOLVED_ENTRY_LINK diagnostic
- Multi-target in ResolvedRef → SHADOWED_DEFINITION diagnostic

### Determinism
- Binding same input twice yields identical output

### No-Failure Policy
- Unresolved links do not throw BindFailure
- Missing type references do not throw BindFailure

---

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:

- **Bound Pack Bundle** — Complete M5 output with bound entities and query surface
- **Bound Entry** — Entry with resolved children, profiles, categories, costs, constraints
- **Bound Profile** — Profile with characteristics and type reference
- **Bound Category** — Category with primary flag
- **Bound Cost** — Cost value with type reference
- **Bound Constraint** — Constraint data (not evaluated)
- **Bind Diagnostic** — Non-fatal semantic issue during binding
- **Bind Failure** — Fatal exception for M5 corruption
- **Bind Service** — Service converting LinkedPackBundle to BoundPackBundle

---

## Approval Checklist

- [ ] Module layout approved
- [ ] Core model names approved (BoundPackBundle, BoundEntry, BoundProfile, BoundCategory, BoundCost, BoundConstraint, BindDiagnostic, BindFailure)
- [ ] Service name approved (BindService)
- [ ] Tag eligibility lists approved (per bound type)
- [ ] Match definition approved (id + tagName)
- [ ] Within-file tie-break approved (first in node order)
- [ ] Field definitions approved
- [ ] Query surface approved
- [ ] Query semantics approved (null/empty on missing)
- [ ] Deterministic ordering approved (binding order)
- [ ] Hidden content policy approved (bind with flag, don't filter)
- [ ] Shadowing policy approved (first-match-wins with type gating)
- [ ] Diagnostic codes approved
- [ ] Determinism contract approved
- [ ] Glossary terms approved

**NO CODE UNTIL APPROVAL.**

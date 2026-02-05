# Phase 2 — M4 Link Approved Names

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **PROPOSED** — awaiting approval

---

## Purpose

M4 Link resolves cross-file `targetId` references across a `WrappedPackBundle` and produces a `LinkedPackBundle` containing:

- A unified `SymbolTable` (cross-file ID registry)
- `ResolvedRef` entries for each link element
- `LinkDiagnostic` entries for resolution issues

**M4 is structural only.** No semantic interpretation.

---

## Scope Boundaries

### M4 MAY:
- Build cross-file symbol table from aggregated `idIndex`
- Resolve `targetId` on link elements (`catalogueLink`, `entryLink`, `infoLink`, `categoryLink`)
- Record resolution outcomes (zero, one, or many targets)
- Emit diagnostics for unresolved or multi-hit cases
- Preserve provenance (fileId on every resolved target)

### M4 MUST NOT:
- Resolve `childId`, `typeId`, or other ID-bearing attributes (deferred)
- Evaluate constraints, conditions, or modifiers
- Merge or duplicate nodes
- Interpret game rules or profiles
- Perform roster/army construction
- Verify that `catalogueLink.targetId` resolves to a root node (`nodeIndex == 0`) — this is semantic validation, deferred to M5+

M4 resolves `targetId` for link elements without validating target element type or position.

---

## File Resolution Order (Contract)

M4 processes files in this exact order:

1. **primaryCatalog**
2. **dependencyCatalogs** (in `WrappedPackBundle.dependencyCatalogs` list order)
3. **gameSystem**

This order determines:
- Symbol table population order
- Multi-target list ordering in `ResolvedRef`
- Diagnostic emission order

**This order is mandatory and not configurable.**

---

## Module Layout

### Module
- Folder: `lib/modules/m4_link/`
- Barrel: `lib/modules/m4_link/m4_link.dart`

### Public Exports (barrel only)
- `services/link_service.dart`
- `models/linked_pack_bundle.dart`
- `models/symbol_table.dart`
- `models/resolved_ref.dart`
- `models/link_diagnostic.dart`
- `models/link_failure.dart`

### File Layout
```
lib/modules/m4_link/
├── m4_link.dart
├── models/
│   ├── linked_pack_bundle.dart
│   ├── symbol_table.dart
│   ├── resolved_ref.dart
│   ├── link_diagnostic.dart
│   └── link_failure.dart
└── services/
    └── link_service.dart
```

---

## Core Types

### LinkedPackBundle
**File:** `models/linked_pack_bundle.dart`

Complete M4 output.

**Fields:**
- `String packId`
- `DateTime linkedAt`
- `SymbolTable symbolTable`
- `List<ResolvedRef> resolvedRefs`
- `List<LinkDiagnostic> diagnostics`
- `WrappedPackBundle wrappedBundle` — reference to M3 input (immutable)

**Rules:**
- One-to-one correspondence with input `WrappedPackBundle`
- Does not modify wrapped nodes
- Preserves provenance chain (M4 → M3 → M2 → M1)

---

### SymbolTable
**File:** `models/symbol_table.dart`

Cross-file ID registry.

**Scope:** One `SymbolTable` per `LinkedPackBundle`.

**Construction:** `SymbolTable` is constructed by aggregating `WrappedFile.idIndex` in file resolution order: primaryCatalog, then dependencyCatalogs (list order), then gameSystem. Targets are stored in node order as provided by each file's `idIndex` (which is M3 traversal order). No re-traversal of nodes.

**Fields:**
- Internal storage mapping ID → list of (fileId, NodeRef) pairs

**Methods:**
- `List<(String fileId, NodeRef nodeRef)> lookup(String id)` — returns all nodes with that ID
- `Iterable<String> get allIds` — all indexed IDs
- `List<String> get duplicateIds` — IDs with >1 definition

**Rules:**
- Duplicate IDs are allowed and preserved
- All occurrences retained
- No throwing during construction
- Lookup returns results in file resolution order (primaryCatalog → dependencyCatalogs → gameSystem), then node order within file

---

### ResolvedRef
**File:** `models/resolved_ref.dart`

Result of resolving a single cross-file reference.

**Fields:**
- `String sourceFileId` — file containing the link element
- `NodeRef sourceNode` — the link element node
- `String targetId` — the `targetId` attribute value being resolved
- `List<(String fileId, NodeRef nodeRef)> targets` — resolved targets as (fileId, NodeRef) pairs

**Representation:** `targets` is a `List` of record/tuple pairs. Each pair contains:
- `fileId` (String) — file containing the target node
- `nodeRef` (NodeRef) — the target node reference

**Ordering Contract:** The `targets` list is ordered deterministically:
1. By file resolution order: primaryCatalog → dependencyCatalogs (in `WrappedPackBundle.dependencyCatalogs` list order) → gameSystem
2. Within each file: by `WrappedFile.nodes` index order (M3 pre-order depth-first traversal)

**Invariants:**
- `targets.isEmpty` ⇔ unresolved (UNRESOLVED_TARGET diagnostic emitted)
- `targets.length > 1` ⇔ multi-hit (DUPLICATE_ID_REFERENCE diagnostic emitted)
- `targets.length == 1` ⇔ unique resolution (no diagnostic)

`ResolvedRef` records outcomes; it does not enforce correctness.

---

### LinkDiagnostic
**File:** `models/link_diagnostic.dart`

Non-fatal resolution issue.

**Fields:**
- `String code` — diagnostic code (closed set)
- `String message` — human-readable description
- `String sourceFileId` — file where issue occurred
- `NodeRef? sourceNode` — node where issue occurred (if applicable)
- `String? targetId` — the ID involved (if applicable)

**Diagnostic Codes (closed set, mechanistic definitions):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `UNRESOLVED_TARGET` | `targetId` not found in SymbolTable (zero targets) | Emit diagnostic, `ResolvedRef.targets` is empty, continue processing |
| `DUPLICATE_ID_REFERENCE` | `targetId` found >1 time in SymbolTable | Emit diagnostic, keep ALL targets in `ResolvedRef.targets` list, continue processing |
| `INVALID_LINK_FORMAT` | Link element has no `targetId` attribute, or `targetId` is empty/whitespace after trimming | Emit diagnostic, no `ResolvedRef` created for this element, continue processing |

**Rules:**
- Diagnostics are accumulated, never thrown
- Diagnostics do not stop processing
- All diagnostics are non-fatal
- New diagnostic codes require doc + glossary update

---

### LinkFailure
**File:** `models/link_failure.dart`

Fatal exception for M4 failures.

**Fields:**
- `String message`
- `String? fileId`
- `String? details`

**Fatality Policy for Phase 2:**

Phase 2 (M4 Link) emits diagnostics only for all expected resolution outcomes. `LinkFailure` is thrown **only** for:

1. **Corrupted M3 input** — `WrappedPackBundle` violates frozen M3 contracts (e.g., `idIndex` references invalid `NodeRef`)
2. **Internal invariant violation** — M4 implementation bug detected

**LinkFailure is NOT thrown for:**
- Unresolved references → `UNRESOLVED_TARGET` diagnostic
- Duplicate IDs → `DUPLICATE_ID_REFERENCE` diagnostic
- Missing `targetId` attribute → `INVALID_LINK_FORMAT` diagnostic

**In normal operation, no `LinkFailure` is thrown.** All resolution issues produce diagnostics and processing continues to completion.

---

## Services

### LinkService
**File:** `services/link_service.dart`

**Method:**
```dart
Future<LinkedPackBundle> linkBundle({
  required WrappedPackBundle wrappedBundle,
}) async
```

**Behavior:**
1. Build `SymbolTable` by aggregating `idIndex` from each `WrappedFile`
2. For each link element (`catalogueLink`, `entryLink`, `infoLink`, `categoryLink`):
   - Extract `targetId` attribute
   - If missing, emit `INVALID_LINK_FORMAT` diagnostic
   - Look up in `SymbolTable`
   - Create `ResolvedRef` with targets (may be empty, one, or many)
   - If empty, emit `UNRESOLVED_TARGET` diagnostic
   - If >1, emit `DUPLICATE_ID_REFERENCE` diagnostic
3. Return `LinkedPackBundle` with all refs and diagnostics

---

## Determinism Contract

M4 guarantees:
- Same `WrappedPackBundle` → identical `LinkedPackBundle`
- No dependence on runtime ordering
- No hash-map iteration leaks
- Stable diagnostic ordering (file order → node order)

---

## Required Tests

### Structural Invariants (MANDATORY)
- All link elements produce a `ResolvedRef`
- `ResolvedRef.targets` is empty ⇔ `UNRESOLVED_TARGET` diagnostic exists
- `ResolvedRef.targets.length > 1` ⇔ `DUPLICATE_ID_REFERENCE` diagnostic exists
- SymbolTable contains all IDs from all files

### Determinism
- Linking same input twice yields identical output

### Provenance
- Every target pair's `fileId` identifies a valid file in the bundle
- Every target pair's `nodeRef` is valid within that file's `WrappedFile.nodes`

### No Structural Mutation
- `WrappedPackBundle` unchanged after linking
- Node indices stable

---

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:

- **Linked Pack Bundle** — Complete M4 output with symbol table and resolved references
- **Symbol Table** — Cross-file registry mapping IDs to their defining nodes
- **Resolved Ref** — A cross-file reference that has been matched to its target(s)
- **Link Diagnostic** — Non-fatal issue detected during cross-file linking
- **Link Failure** — Fatal exception for M4 structural corruption

---

## Approval Checklist

- [ ] Module layout approved
- [ ] Core model names approved (LinkedPackBundle, SymbolTable, ResolvedRef, LinkDiagnostic, LinkFailure)
- [ ] Service name approved (LinkService)
- [ ] File resolution order approved (primaryCatalog → dependencyCatalogs → gameSystem)
- [ ] Diagnostic codes approved (UNRESOLVED_TARGET, DUPLICATE_ID_REFERENCE, INVALID_LINK_FORMAT)
- [ ] Determinism contract approved
- [ ] Glossary terms approved

**NO CODE UNTIL APPROVAL.**

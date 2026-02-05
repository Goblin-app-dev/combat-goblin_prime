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

**Construction:** Aggregate `WrappedFile.idIndex` from each file. No re-traversal.

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
- `List<ResolvedTarget> targets` — zero, one, or many resolved targets

Where `ResolvedTarget` contains:
- `String fileId` — file containing the target
- `NodeRef nodeRef` — the target node

**Target Ordering:** When multiple targets exist, list order is:
1. File resolution order: primaryCatalog → dependencyCatalogs (list order) → gameSystem
2. Within each file: `WrappedFile.nodes` order (M3 traversal order)

**Rules:**
- Empty `targets` list = unresolved (produces `UNRESOLVED_TARGET` diagnostic)
- Multiple targets = multi-hit (produces `DUPLICATE_ID_REFERENCE` diagnostic)
- `ResolvedRef` records outcomes; it does not enforce correctness

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

**Diagnostic Codes (closed set):**

| Code | Meaning |
|------|---------|
| `UNRESOLVED_TARGET` | No targets found for `targetId` in SymbolTable |
| `DUPLICATE_ID_REFERENCE` | More than one target found for `targetId` |
| `INVALID_LINK_FORMAT` | Link element missing `targetId` attribute |

**Rules:**
- Diagnostics are accumulated, not thrown
- Diagnostics do not stop processing
- New diagnostic codes require doc + glossary update

---

### LinkFailure
**File:** `models/link_failure.dart`

Fatal exception for M4 failures.

**Fields:**
- `String message`
- `String? fileId`
- `String? details`

**Used only for:**
- Structural corruption detected
- Internal invariants violated
- Resolution cannot proceed deterministically

**NOT used for:**
- Unresolved references → diagnostic
- Duplicate IDs → diagnostic
- Missing `targetId` attribute → diagnostic

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
- Every `ResolvedTarget.fileId` matches source file
- Every `ResolvedTarget.nodeRef` is valid in that file

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

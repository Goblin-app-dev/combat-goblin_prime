# Phase 1C — M3 Wrap Approved Names

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **IMPLEMENTED** — tests pending, freeze pending

---

## Purpose

M3 converts `ParsedPackBundle` (M2 output) into a wrapped, navigable, lossless structural graph that:

- Preserves provenance (M3 → M2 → M1)
- Preserves document order deterministically
- Introduces stable node identity
- Enables safe traversal and lookup
- Does NOT interpret semantics
- Does NOT link across files
- Does NOT resolve references

**M3 is structural only.**

---

## Scope Boundaries

### M3 MAY:
- Wrap ElementDto into WrappedNode
- Assign deterministic node indices
- Track parent/child relationships
- Provide per-file lookup tables
- Preserve source provenance

### M3 MUST NOT:
- Resolve cross-file references
- Interpret IDs semantically
- Enforce rules or constraints
- Merge data across files
- Perform binding
- Persist data
- Delete files
- Touch update logic

---

## Deterministic Traversal & Indexing Contract

### Traversal Order
- Pre-order depth-first traversal
- Children visited strictly in `ElementDto.children` order
- Only element nodes are wrapped (no synthetic text nodes)

### Node Index Rules
- `root.nodeIndex == 0`
- nodeIndex increments by exactly +1 per visited node
- Index assignment must be purely deterministic
- Re-wrapping the same ParsedFile MUST produce identical indices

**This is a contract, not an optimization.**

---

## Module Layout

### Module
- Folder: `lib/modules/m3_wrap/`
- Barrel: `lib/modules/m3_wrap/m3_wrap.dart`

### Public Exports (barrel only)
- `services/wrap_service.dart`
- `models/wrapped_pack_bundle.dart`
- `models/wrapped_file.dart`
- `models/wrapped_node.dart`
- `models/node_ref.dart`
- `models/wrap_failure.dart`

### File Layout
```
lib/modules/m3_wrap/
├── m3_wrap.dart
├── models/
│   ├── node_ref.dart
│   ├── wrapped_node.dart
│   ├── wrapped_file.dart
│   ├── wrapped_pack_bundle.dart
│   └── wrap_failure.dart
└── services/
    └── wrap_service.dart
```

---

## Core Types

### NodeRef
**File:** `models/node_ref.dart`

A strongly-typed handle for referring to nodes without leaking raw integers.

**Fields:**
- `int nodeIndex`

**Rules:**
- NodeRef is the ONLY allowed way to refer to a node
- Raw int indices must not leak outside M3 internals

---

### WrappedNode
**File:** `models/wrapped_node.dart`

A wrapped, indexed representation of one XML element.

**Fields:**
- `NodeRef ref` — this node's own reference
- `String tagName`
- `Map<String, String> attributes`
- `String? textContent`
- `NodeRef? parent`
- `List<NodeRef> children`
- `int depth` — root=0, child of root=1, etc.
- `String fileId` — provenance from ParsedFile
- `SourceFileType fileType` — provenance from ParsedFile
- `int? sourceIndex` — copied from ElementDto (best-effort)

**Invariants (MUST HOLD):**
- `parent == null` ⇔ `depth == 0`
- If A.children contains B, then B.parent == A
- `depth == (parent == null ? 0 : parent.depth + 1)`
- children order matches traversal order

---

### WrappedFile
**File:** `models/wrapped_file.dart`

A parsed file wrapped into a node table + local lookup indexes.

**Fields:**
- `String fileId`
- `SourceFileType fileType`
- `List<WrappedNode> nodes`
- `Map<String, List<NodeRef>> idIndex`

**idIndex Contract:**
- Maps attribute `id` → `List<NodeRef>`
- Nodes without an `id` attribute are excluded
- Duplicate IDs are allowed and preserved (list contains all)
- No throwing for duplicate IDs
- Deterministic ordering (traversal order)

---

### WrappedPackBundle
**File:** `models/wrapped_pack_bundle.dart`

Complete wrapped output for a pack.

**Fields:**
- `String packId`
- `DateTime wrappedAt`
- `WrappedFile gameSystem`
- `WrappedFile primaryCatalog`
- `List<WrappedFile> dependencyCatalogs`

**Rules:**
- One-to-one correspondence with ParsedPackBundle
- No merging
- No linking
- No interpretation

---

### WrapFailure
**File:** `models/wrap_failure.dart`

Structured exception for M3 failures.

**Fields:**
- `String message`
- `String? fileId`
- `NodeRef? node`
- `String? details`

**Used only for:**
- Structural corruption
- Internal invariant violation
- Impossible traversal states

**Not used for:**
- Duplicate IDs
- Missing IDs
- Semantic issues

---

## Services

### WrapService
**File:** `services/wrap_service.dart`

**Method:**
```dart
Future<WrappedPackBundle> wrapBundle({required ParsedPackBundle parsedBundle})
```

**Behavior:**
1. For each ParsedFile, traverse ElementDto tree in pre-order depth-first
2. Build flat nodes list with deterministic nodeIndex (0, 1, 2, ...)
3. Assign parent, children, depth
4. Copy fileId, fileType to each node for provenance
5. Build idIndex map from `attributes['id']` (list-based, no throwing)
6. Produce WrappedPackBundle with same packId

---

## Text Preservation

- `textContent` is preserved exactly as provided by M2
- Mixed-content fidelity is limited by M2 design
- M3 must not invent or split text nodes

---

## Required Tests

### Structural Invariants (MANDATORY)
- Parent/child bidirectional consistency
- Depth correctness
- Deterministic nodeIndex assignment
- Root index == 0
- Stable traversal order

### Provenance
- `WrappedNode.fileId` matches source `ParsedFile.fileId`
- `SourceFileType` preserved

### Determinism
- Wrapping same ParsedPackBundle twice yields structurally equivalent graphs

**No schema assumptions. No cross-file assertions.**

---

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:
- **Node Ref** — Strongly-typed handle for node identity within a WrappedFile
- **Wrapped Node** — Indexed, navigable representation of an XML element with provenance
- **Wrapped File** — Per-file node table with local id lookup index
- **Wrapped Pack Bundle** — Complete M3 output for a pack
- **Wrap Failure** — Exception for structural corruption in M3

---

## Approval Checklist

- [x] File layout approved
- [x] Core model names approved (NodeRef, WrappedNode, WrappedFile, WrappedPackBundle, WrapFailure)
- [x] Service name approved (WrapService)
- [x] Traversal contract approved (pre-order depth-first, root=0)
- [x] idIndex collision policy approved (List-based, no throwing)
- [x] Provenance fields approved (fileId/fileType on every node)

**IMPLEMENTED.** Code landed in commit `88c6a77`. Tests pending before freeze.

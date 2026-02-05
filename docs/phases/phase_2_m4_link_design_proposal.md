# Phase 2 — M4 Link Design Proposal

**Status:** DESIGN ONLY — Awaiting SME approval. No code permitted until approval.

**Date:** 2026-02-04 (Revised: determinism clarifications)

---

## Phase State (Authoritative)

| Phase | Module | Status |
|-------|--------|--------|
| Phase 1A | M1 Acquire | **FROZEN** |
| Phase 1B | M2 Parse | **FROZEN** |
| Phase 1C | M3 Wrap | **FROZEN** (2026-02-04) |
| Phase 2 | M4 Link | **PROPOSED** |

M4 depends on the guarantees of M3 Wrap as frozen in `/docs/module_io_registry.md`.
M4 must not restate or reinterpret M3 behavior.

---

## Purpose of M4 (Problem Statement)

Phase 2 (M4 Link) resolves cross-file references across a wrapped pack while preserving:

- Determinism
- Provenance
- Structural separation
- Phase boundaries

**M4 introduces reference resolution only.**
It does not interpret semantics, rules, constraints, or modifiers.

### What M4 Must Solve

M4 is responsible for resolving references that span files, specifically:

- `catalogueLink`
- `entryLink`
- `infoLink`
- `categoryLink`

Resolution means:
- Mapping a reference to one or more concrete node targets
- Recording resolution results explicitly
- Emitting diagnostics for unresolved or ambiguous cases

### What M4 Explicitly Does NOT Do

**M4 MUST NOT:**
- Interpret game rules or profiles
- Evaluate constraints or conditions
- Apply modifiers
- Merge node trees
- Duplicate nodes
- Reorder nodes
- Infer meaning from tag names
- Perform roster or army construction

All of the above are deferred to M5+.

---

## Inputs

`WrappedPackBundle` (from M3 Wrap, frozen)

Guarantees assumed (not revalidated):
- Deterministic node indices
- Stable traversal order
- Per-file `idIndex`
- Preserved provenance

---

## Outputs

### LinkedPackBundle

The complete output of M4.

Characteristics:
- One-to-one correspondence with the input `WrappedPackBundle`
- Contains resolution results but does not modify wrapped nodes
- Preserves packId and provenance chain (M4 → M3 → M2 → M1)

---

## Resolution Targets (Phase 2 Scope)

**M4 resolves references only for the following link elements:**
- `catalogueLink`
- `entryLink`
- `infoLink`
- `categoryLink`

**For these elements, M4 resolves only the `targetId` attribute.**

Any other ID-bearing attributes (e.g., `childId`, `typeId`, `entryId`, etc.) are **explicitly deferred** to later phases.

---

## Resolution Order (MANDATORY, NOT CONFIGURABLE)

To ensure determinism, M4 uses a fixed file processing order:

1. **Primary Catalog**
2. **Dependency Catalogs** (in exact list order of `WrappedPackBundle.dependencyCatalogs`)
3. **Game System**

**This order is part of the Phase 2 contract.**

Clarifications:
- Dependency catalogs are processed in the exact list order of `WrappedPackBundle.dependencyCatalogs` (as produced by M3)
- **No recursive dependency expansion occurs in M4** (immediate dependencies only)
- Later phases may reinterpret shadowing, but M4 must follow this order exactly

---

## Core Types (No New Names)

### SymbolTable

A cross-file registry built from M3 output.

**Scope:** One `SymbolTable` is built per `LinkedPackBundle`. It indexes all `id` attributes across all `WrappedFile` instances (gameSystem, primaryCatalog, dependencyCatalogs).

**Construction:** `SymbolTable` is constructed by aggregating `WrappedFile.idIndex` from each file. M4 does not re-traverse nodes to rebuild indexes.

**Responsibilities:**
- Index all `id` attributes across all `WrappedFile` instances
- Preserve file boundaries
- Support deterministic lookup

**Rules:**
- Duplicate IDs are allowed
- All occurrences are retained
- No throwing during table construction

`SymbolTable` is a lookup structure, not a semantic authority.

### ResolvedRef

Represents the result of resolving a single cross-file reference.

**Properties:**
- Original reference location (fileId + node)
- Zero, one, or many resolved targets
- No semantic interpretation

**Target Ordering:** When a reference resolves to multiple targets, targets are stored as a `List` in deterministic order:
1. File resolution order: primaryCatalog → dependencyCatalogs (list order) → gameSystem
2. Within each file: node order matches `WrappedFile.nodes` order (M3 traversal order)

`ResolvedRef` does not enforce correctness — it records outcomes.

### LinkDiagnostic

Represents non-fatal resolution issues.

**This is a closed set.** New diagnostic kinds require doc + glossary updates.

**Diagnostics used in M4:**

| Code | Meaning |
|------|---------|
| `UNRESOLVED_TARGET` | No targets found for `targetId` in SymbolTable |
| `DUPLICATE_ID_REFERENCE` | More than one target found for `targetId` across the pack |
| `INVALID_LINK_FORMAT` | Link element missing `targetId` attribute (structural) |

Diagnostics:
- Are accumulated
- Do not stop processing
- Are attached to the `LinkedPackBundle`

### LinkFailure

A fatal exception.

**Used only when:**
- Structural corruption is detected
- Internal invariants are violated
- Resolution cannot proceed deterministically

**LinkFailure is NOT used for:**
- Missing references
- Ambiguity
- Duplicate IDs

Those produce diagnostics, not failures.

---

## catalogueLink.importRootEntries Handling

M4 behavior is strictly limited:

- `importRootEntries` relationships are recorded as `ResolvedRef` entries
- No nodes are duplicated
- No implicit traversal is performed
- No children are auto-included

**M4 records relationships only. Traversal behavior is deferred.**

---

## Semantic Deferral (Explicit)

**M4 MUST NOT introduce semantic typing.**

All resolution is:
- Structural
- ID-based
- Provenance-preserving

Meaning is assigned only in Phase 3+ (M5 and beyond).

**This is non-negotiable.**

---

## Determinism Guarantees

M4 must guarantee:
- Same `WrappedPackBundle` → identical `LinkedPackBundle`
- No dependence on runtime ordering
- No hash-map iteration leaks
- Stable diagnostic ordering

---

## BSD File Structure Reference

### File Hierarchy

```
.gst (Game System) ← root, defines gameSystemId
  └── .cat (Catalogues) ← reference the gst via gameSystemId attribute
        └── .ros (Rosters) ← output format, actual army lists (out of scope)
```

### Catalogue Tree Structure

```
Catalogue (root element)
├── costTypes (pts, PL, etc.)
├── profileTypes → characteristicTypes (stat column definitions)
├── categoryEntries (Infantry, HQ, etc.)
├── forceEntries (Detachments)
├── sharedSelectionEntries (SSE)
├── sharedSelectionEntryGroups (SSEG)
├── sharedProfiles (SP)
├── sharedRules (SR)
├── selectionEntries (root-level entries)
├── entryLinks (references to shared entries)
└── catalogueLinks (dependencies on other catalogues)
```

### Core Entity Types (from BSD schema)

| Entity | Purpose | Has `id`? | Referenced via |
|--------|---------|-----------|----------------|
| `selectionEntry` | Units, models, upgrades — fundamental building block | Yes | `entryLink.targetId` |
| `selectionEntryGroup` | Groups SEs with shared constraints | Yes | `entryLink.targetId` |
| `profile` | Stat block (row of characteristics) | Yes | `infoLink.targetId` |
| `rule` | Multi-line text, preserves line breaks | Yes | `infoLink.targetId` |
| `categoryEntry` | Tags/categories (Infantry, HQ) | Yes | `categoryLink.targetId` |
| `costType` | Point system definition (pts, PL) | Yes | `cost.typeId` (DEFERRED) |
| `profileType` | Stat line schema (Unit, Ranged Weapons) | Yes | `profile.typeId` (DEFERRED) |
| `forceEntry` | Detachment structure | Yes | — |

### Cross-File Reference Mechanisms (for context)

**1. catalogueLink** (file-level import)
```xml
<catalogueLink id="..." name="Library - Titans" targetId="7481-280e-b55e-7867" importRootEntries="true"/>
```
- `targetId` references another catalogue's root `id`
- `importRootEntries` controls whether root entries are imported (behavior deferred)

**2. entryLink** (selection entry reference)
```xml
<entryLink id="..." name="Detachment" type="selectionEntry" targetId="82cb-ba1-1aae-3b1d" import="true"/>
```
- `targetId` references a `selectionEntry` or `selectionEntryGroup`

**3. infoLink** (profile/rule reference)
```xml
<infoLink id="..." name="Unit Stats" type="profile" targetId="abc-123"/>
```
- `targetId` references a `profile`, `rule`, or `infoGroup`

**4. categoryLink** (category assignment)
```xml
<categoryLink id="..." name="Infantry" targetId="4ac9-fd30-1e3d-b249" primary="true"/>
```
- `targetId` references a `categoryEntry`

**5. Constraint/Condition references (DEFERRED)**
```xml
<condition field="selections" scope="roster" childId="abc-123" .../>
```
- `childId` references another entry for conditional logic — **NOT resolved in M4**
- `scope` defines query context — **NOT resolved in M4**

---

## Existing Types Referenced (from frozen modules)

### From M1 Acquire
- `SourceFileType` (enum: `gst`, `cat`)
- `ImportDependency` (contains `targetId: String`)
- `PreflightScanResult` (contains `importDependencies: List<ImportDependency>`)

### From M2 Parse
- `ElementDto` (generic XML element)
- `ParsedFile` (contains `fileId`, `fileType`, `rootId`, `root: ElementDto`)

### From M3 Wrap
- `NodeRef` (strongly-typed node handle: `nodeIndex: int`)
- `WrappedNode` (contains `ref`, `tagName`, `attributes`, `parent`, `children`, `depth`, `fileId`, `fileType`)
- `WrappedFile` (contains `fileId`, `fileType`, `nodes: List<WrappedNode>`, `idIndex: Map<String, List<NodeRef>>`)
- `WrappedPackBundle` (contains `packId`, `gameSystem`, `primaryCatalog`, `dependencyCatalogs`)

---

## Proposed Module Layout

```
lib/modules/m4_link/
├── m4_link.dart                      (barrel)
├── models/
│   ├── linked_pack_bundle.dart       (PROPOSED)
│   ├── symbol_table.dart             (PROPOSED)
│   ├── resolved_ref.dart             (PROPOSED)
│   ├── link_diagnostic.dart          (PROPOSED)
│   └── link_failure.dart             (PROPOSED)
└── services/
    └── link_service.dart             (PROPOSED)
```

---

## Required Tests (When Implemented)

Tests must verify:

### Resolution Shape
- All references produce a `ResolvedRef`
- Zero targets is allowed (with diagnostic)

### Determinism
- Running M4 twice yields identical results

### Provenance
- Resolved targets trace back to correct fileId + node

### No Structural Mutation
- Wrapped nodes are unchanged
- Node indices remain stable

**NO semantic assertions. NO rule evaluation. NO cross-phase leakage.**

---

## Glossary Updates Required (Before Code)

The following terms must exist in `/docs/glossary.md` before implementation:

- **Linked Pack Bundle** — Complete M4 output with symbol table and resolved references
- **Symbol Table** — Cross-file registry mapping IDs to their defining nodes
- **Resolved Ref** — A cross-file reference that has been matched to its target(s)
- **Link Diagnostic** — Non-fatal issue detected during cross-file linking
- **Link Failure** — Fatal exception for M4 structural corruption

**No additional terms are permitted.**

---

## Approval Checklist (Blocking)

- [ ] Core types approved (LinkedPackBundle, SymbolTable, ResolvedRef, LinkDiagnostic, LinkFailure)
- [ ] Resolution order approved (primaryCatalog → dependencyCatalogs list order → gameSystem)
- [ ] Resolution targets approved (`targetId` only on link elements; childId/typeId deferred)
- [ ] Diagnostic taxonomy approved as closed set (UNRESOLVED_TARGET, DUPLICATE_ID_REFERENCE, INVALID_LINK_FORMAT)
- [ ] Semantic deferral confirmed
- [ ] `catalogueLink.importRootEntries` handling approved (record only, no traversal)
- [ ] SymbolTable construction approved (aggregate idIndex, no re-traversal)
- [ ] Glossary updated
- [ ] module_io_registry updated (M4 marked PROPOSED)

**NO CODE UNTIL ALL CHECKS ARE COMPLETE.**

---

## References

- `/docs/module_io_registry.md` — M1/M2/M3 contracts
- `/docs/glossary.md` — Established terminology
- `/docs/phases/phase_1c_m3_approved_names_proposal.md` — M3 design
- BSD Schema Wiki — Entity definitions (external)

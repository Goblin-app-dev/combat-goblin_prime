# Phase 2 — M4 Link Design Proposal

**Status:** PROPOSAL — Awaiting SME review. No code until approved.

**Date:** 2026-02-04

---

## Executive Summary

Phase 2 (M4 Link) resolves cross-file references and builds a unified, navigable semantic graph from the per-file `WrappedFile` structures produced by M3. This document proposes the design for SME review.

---

## Prior Art (Frozen Modules)

| Module | Output | Status |
|--------|--------|--------|
| M1 Acquire | `RawPackBundle` | FROZEN |
| M2 Parse | `ParsedPackBundle` | FROZEN |
| M3 Wrap | `WrappedPackBundle` | FROZEN |

M4 consumes `WrappedPackBundle` and produces a linked semantic graph.

---

## Problem Statement

M3 provides:
- Per-file `WrappedFile` with flat node tables
- Per-file `idIndex: Map<String, List<NodeRef>>` for local ID lookup
- No cross-file resolution
- No semantic interpretation

Phase 2 must:
1. Resolve `targetId` references across all files in the bundle
2. Build a unified symbol table spanning gameSystem + primaryCatalog + dependencyCatalogs
3. Interpret semantic types (selection entries, profiles, rules, categories, etc.)
4. Track provenance (which file contributed which node)
5. Support queries like "find all units" or "what does this targetId resolve to?"

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
| `costType` | Point system definition (pts, PL) | Yes | `cost.typeId` |
| `profileType` | Stat line schema (Unit, Ranged Weapons) | Yes | `profile.typeId` |
| `forceEntry` | Detachment structure | Yes | — |

### Cross-File Reference Mechanisms

**1. catalogueLink** (file-level import)
```xml
<catalogueLink id="..." name="Library - Titans" targetId="7481-280e-b55e-7867" importRootEntries="true"/>
```
- `targetId` references another catalogue's root `id`
- `importRootEntries` controls whether root entries are imported

**2. entryLink** (selection entry reference)
```xml
<entryLink id="..." name="Detachment" type="selectionEntry" targetId="82cb-ba1-1aae-3b1d" import="true"/>
```
- `targetId` references a `selectionEntry` or `selectionEntryGroup`
- Can reference entries in imported catalogues

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

**5. Constraint/Condition references**
```xml
<condition field="selections" scope="roster" childId="abc-123" .../>
```
- `childId` references another entry for conditional logic
- `scope` defines query context (parent, roster, force, primary-catalogue, ancestor)

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

## Proposed M4 Design

### Purpose

M4 Link resolves all `targetId` references across files and builds a unified symbol table with semantic type awareness.

### Scope Boundaries

**M4 MAY:**
- Build cross-file symbol table mapping IDs to their defining nodes
- Resolve `targetId`, `childId`, `typeId` references
- Track which file each symbol originates from
- Report unresolved references as diagnostics
- Provide lookup: given any `targetId`, return the referenced node(s)

**M4 MUST NOT:**
- Evaluate constraints or modifiers (deferred to M5+)
- Compute effective values (deferred to M5+)
- Build roster/army list structures (out of scope)
- Modify M3 output (read-only consumption)
- Persist data
- Touch M1/M2/M3 code

### Proposed Module Layout

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

## Proposed Types (Awaiting Approval)

### 1. ResolvedRef (PROPOSED)

A resolved cross-file reference.

```
ResolvedRef
├── sourceFileId: String       // file containing the reference
├── sourceNode: NodeRef        // node containing targetId attribute
├── targetId: String           // the ID being resolved
├── targetFileId: String?      // file containing the target (null if unresolved)
├── targetNode: NodeRef?       // resolved target node (null if unresolved)
├── resolved: bool             // true if target found
```

**Design question for SME:**
- Should `ResolvedRef` include the attribute name (e.g., "targetId" vs "childId" vs "typeId")?

### 2. SymbolTable (PROPOSED)

Cross-file ID registry.

```
SymbolTable
├── entries: Map<String, List<SymbolEntry>>  // ID → all nodes with that ID
├── lookup(String id): List<SymbolEntry>
├── lookupUnique(String id): SymbolEntry?    // returns null if 0 or >1 matches
├── allIds: Iterable<String>
├── duplicateIds: List<String>               // IDs with >1 definition
```

Where `SymbolEntry` is:
```
SymbolEntry
├── id: String
├── fileId: String
├── nodeRef: NodeRef
├── tagName: String           // e.g., "selectionEntry", "profile", "categoryEntry"
├── nameAttribute: String?    // value of name attribute, if present
```

**Design question for SME:**
- Should `SymbolTable` be a separate type or a field on `LinkedPackBundle`?
- Should we track semantic type (selectionEntry vs profile) at this level or defer?

### 3. LinkDiagnostic (PROPOSED)

Non-fatal issue detected during linking.

```
LinkDiagnostic
├── severity: LinkSeverity     // warning, error
├── code: String               // e.g., "UNRESOLVED_TARGET", "DUPLICATE_ID"
├── message: String
├── sourceFileId: String
├── sourceNode: NodeRef?
├── targetId: String?
├── details: String?
```

Diagnostic codes (proposed):
- `UNRESOLVED_TARGET` — targetId not found in any file
- `DUPLICATE_ID` — same ID defined in multiple places (warning, not error)
- `CIRCULAR_IMPORT` — catalogueLink cycle detected
- `GAME_SYSTEM_MISMATCH` — catalogue's gameSystemId doesn't match

### 4. LinkedPackBundle (PROPOSED)

Complete M4 output.

```
LinkedPackBundle
├── packId: String
├── linkedAt: DateTime
├── symbolTable: SymbolTable
├── resolvedRefs: List<ResolvedRef>
├── diagnostics: List<LinkDiagnostic>
├── wrappedBundle: WrappedPackBundle       // reference to M3 input (immutable)
```

**Design question for SME:**
- Should `LinkedPackBundle` contain the full `WrappedPackBundle` or just reference it?
- Should we store only unresolved refs (errors) or all refs (for debugging)?

### 5. LinkFailure (PROPOSED)

Fatal exception for M4 failures.

```
LinkFailure implements Exception
├── message: String
├── fileId: String?
├── details: String?
```

Used only for:
- Internal invariant violation
- Corrupted M3 input

NOT used for:
- Unresolved references (diagnostic)
- Duplicate IDs (diagnostic)

---

## Proposed LinkService API

```dart
class LinkService {
  Future<LinkedPackBundle> linkBundle({
    required WrappedPackBundle wrappedBundle,
  }) async { ... }
}
```

### Algorithm Sketch

1. **Build symbol table** — iterate all files, collect all nodes with `id` attribute
2. **Detect duplicates** — IDs appearing in multiple files (warning diagnostic)
3. **Resolve references** — for each node with `targetId`/`childId`/`typeId`:
   - Look up in symbol table
   - Record as `ResolvedRef`
   - If not found, emit `UNRESOLVED_TARGET` diagnostic
4. **Validate catalogue links** — ensure all `catalogueLink.targetId` resolve to actual catalogue roots
5. **Check game system consistency** — all catalogues reference same `gameSystemId`

### Reference Attributes to Resolve

| Attribute | Found in | References |
|-----------|----------|------------|
| `targetId` | entryLink, infoLink, categoryLink, catalogueLink | Various entry types |
| `childId` | condition, constraint | Entry for conditional logic |
| `typeId` | profile, cost | profileType, costType |
| `scope` | condition, constraint | Query context (not an ID reference) |
| `gameSystemId` | catalogue root | Game system root ID |

---

## Import Resolution Order

Catalogues form a dependency graph via `catalogueLink` elements.

**Proposed resolution order:**
1. Game system (always first, no dependencies)
2. Dependency catalogues (topologically sorted by catalogueLink graph)
3. Primary catalogue (may depend on any dependency)

**Cycle detection:**
- If catalogueLink graph contains cycles, emit `CIRCULAR_IMPORT` diagnostic
- Continue linking with best-effort (all files still processed)

---

## Duplicate ID Policy

BSD files commonly have duplicate IDs across files (shared libraries redefine things).

**Proposed policy:**
- Duplicate IDs within same file: preserve all (M3 already does this)
- Duplicate IDs across files: preserve all, emit `DUPLICATE_ID` warning
- Resolution priority (if we need to pick one):
  1. Game system definition
  2. Primary catalogue definition
  3. Dependency catalogue definition (in topological order)

**Design question for SME:**
- Should we support "shadowing" (primary catalogue overrides dependency)?
- Or should all duplicates be preserved and caller decides?

---

## Constraints, Modifiers, Conditions (DEFERRED)

M4 does NOT evaluate:
- Constraints (min/max limits with scope queries)
- Modifiers (increment/decrement/set/append on properties)
- Conditions (prerequisites for modifiers)
- Repeats (iteration patterns)

These require runtime context (roster state) and are deferred to M5+.

M4 DOES:
- Record that constraint/modifier/condition nodes exist
- Resolve any `targetId`/`childId` references within them
- Make them navigable via the symbol table

---

## Test Strategy

### Structural Invariants (MANDATORY)
- Every `ResolvedRef` with `resolved=true` has valid `targetNode`
- Every `ResolvedRef` with `resolved=false` has `targetNode=null`
- SymbolTable contains all nodes with `id` attribute from all files
- No `LinkFailure` for valid M3 input

### Cross-File Resolution
- `catalogueLink.targetId` resolves to catalogue root
- `entryLink.targetId` resolves to selectionEntry/selectionEntryGroup
- `categoryLink.targetId` resolves to categoryEntry
- Unresolved references produce diagnostics, not failures

### Provenance
- Every `SymbolEntry.fileId` matches the source file
- Game system symbols distinguishable from catalogue symbols

### Determinism
- Linking same `WrappedPackBundle` twice yields identical `LinkedPackBundle`

---

## Glossary Additions (Proposed)

| Term | Definition |
|------|------------|
| **Symbol Table** | Cross-file registry mapping IDs to their defining nodes |
| **Resolved Ref** | A cross-file reference that has been matched to its target |
| **Link Diagnostic** | Non-fatal issue detected during cross-file linking |
| **Linked Pack Bundle** | Complete M4 output with symbol table and resolved references |
| **Link Failure** | Fatal exception for M4 structural corruption |

---

## Open Questions for SME

1. **Shadowing policy**: Should primary catalogue definitions override dependency definitions for the same ID?

2. **Reference completeness**: Should `ResolvedRef` track ALL reference attributes (targetId, childId, typeId, entryId, etc.) or just the primary ones?

3. **Semantic typing**: Should M4 assign semantic types (SelectionEntry, Profile, Rule) or defer to M5?

4. **SymbolTable scope**: Per-bundle or per-file secondary indexes?

5. **Diagnostic severity**: Which issues are warnings vs errors?
   - Unresolved targetId in entryLink: error?
   - Unresolved targetId in condition: warning?
   - Duplicate ID: warning always?

6. **catalogueLink.importRootEntries**: Does M4 need to track this flag for later phases?

---

## Approval Checklist

- [ ] Module layout approved
- [ ] Core model names approved (LinkedPackBundle, SymbolTable, ResolvedRef, LinkDiagnostic, LinkFailure)
- [ ] Service name approved (LinkService)
- [ ] Duplicate ID policy approved
- [ ] Import resolution order approved
- [ ] Diagnostic codes approved
- [ ] Glossary terms approved

**NO CODE UNTIL APPROVAL.**

---

## References

- `/docs/module_io_registry.md` — M1/M2/M3 contracts
- `/docs/glossary.md` — Established terminology
- `/docs/phases/phase_1c_m3_approved_names_proposal.md` — M3 design
- BSD Schema Wiki — Entity definitions (external)

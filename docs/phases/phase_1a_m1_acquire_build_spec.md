# Phase 1A — M1 Acquire (Build Spec)

## Purpose
M1 Acquire is responsible for selecting, validating, persisting, and assembling the external file set needed for downstream parsing.

It produces a deterministic “raw bundle” containing:
- exactly one gamesystem file (`.gst`)
- one primary catalog file (`.cat`)
- zero or more dependent catalog files (`.cat`) required by the primary catalog

Phase 1A defines **file picking + storage + dependency prompting + raw bundle outputs**.

This module MUST NOT:
- resolve any cross-file references beyond import dependency detection
- interpret semantic meaning of nodes
- merge files
- build symbols
- do query logic

It MAY:
- perform a lightweight XML preflight scan for root attributes and import dependency declarations
- compute hashes and store metadata
- emit acquisition diagnostics (not binding diagnostics)

---

## Platform Scope
This build spec targets **iOS and Android**.

Implications:
- file picker must work on both platforms
- imported files must be copied into app-controlled storage
- access to original external paths must not be required after import
- deterministic behavior must be consistent across platforms

---

## Governing Rules (must comply)
- Naming rules are governed by `/docs/naming_contract.md`
- Prohibited IP terms must not appear in authored strings (UI, logs, docs, code). External filenames may be displayed verbatim.
- Any new internal names beyond those explicitly approved in the Phase 0/Phase 1 docs require user permission.
- Full-file output rule applies to code changes (later), not to this build spec.

---

## Scope
### In scope
- UI file selection flow for gamesystem + catalog
- Persistence of selected files to app-controlled storage
- Cached gamesystem behavior (unless deleted/replaced by user)
- Lightweight import dependency detection for catalog dependencies via `catalogueLinks/catalogueLink`
- Prompting user to provide missing dependent catalogs
- Output: deterministic raw bundle object containing bytes + metadata

### Out of scope (explicitly deferred)
- Network download of missing dependencies
- Automatic searching user storage for dependencies
- Deep import dependency chains beyond a configurable depth (default: 1 level for Phase 1A)
- Any binding/link resolution of `targetId` references beyond import dependency detection

---

## IMPORTANT CLARIFICATION — Dependency Detection Scope
Phase 1A detects **catalog import dependencies only**, specifically those declared by:
- `catalogue/catalogueLinks/catalogueLink`

Phase 1A does NOT attempt to infer additional required files from other `targetId` references in the document.

As a result:
- It is possible for Phase 2 binding to report unresolved references even when all `catalogueLinks` are satisfied.
- This is expected and correct. Phase 1A guarantees only that explicitly declared import dependencies are collected.

This must be communicated in UX and documentation so users do not assume “all needed files are present” after import.

---

## Definitions
- **Gamesystem file**: a `.gst` file whose root element is `gameSystem`.
- **Catalog file**: a `.cat` file whose root element is `catalogue`.
- **Import dependency**: a catalog reference declared in a `.cat` file under:
  - `catalogue/catalogueLinks/catalogueLink`
  where each `catalogueLink` includes at minimum:
  - `targetId` (string)
  and may include:
  - `importRootEntries="true|false"`

---

## User Experience Contract (M1 Acquire)

### Entry points
M1 Acquire has two user-facing entry points:

1) **Import Catalog**
- User selects a primary `.cat`
- M1 ensures a cached `.gst` exists; if not, it must prompt to select one

2) **Manage Gamesystem**
- User can:
  - view cached gamesystem status (name/id if available)
  - replace cached gamesystem by selecting a new `.gst`
  - delete cached gamesystem

> Phase 1A requires the functional behavior. The exact UI surfaces can be minimal (single screen with buttons is sufficient).

### Cached gamesystem rule (locked decision)
- The app maintains exactly one cached `.gst` at a time.
- The cached `.gst` is reused for all imports until:
  - user explicitly replaces it, OR
  - user deletes it

If no cached `.gst` exists and the user tries to import a `.cat`, the app must prompt for `.gst` selection.

### Flow Overview (Import Catalog)
1. Ensure a cached `.gst` exists:
   - if not, prompt user to pick `.gst`
2. User selects a primary `.cat`
3. Acquire preflight scans:
   - cached `.gst` (root identity)
   - primary `.cat` (root identity + import dependency list)
4. If import dependencies are declared and missing:
   - prompt user to import required dependent `.cat` files
   - validate imported `.cat` matches a required dependency `targetId`
5. Persist all files to app storage (cached `.gst` already persisted)
6. Return a Raw Bundle output object

---

## Storage Contract (M1 Acquire)

### Storage location
All imported files must be copied into app-controlled storage using a deterministic layout.

Recommended conceptual layout:

- `appDataRoot/`
  - `gamesystem_cache/`
    - `{gamesystemRootId}/`
      - `{fileId}.gst`
      - `gamesystem_metadata.json`
  - `packs/`
    - `{packId}/`
      - `catalogs/`
        - `{catalogRootId}/`
          - `{fileId}.cat`
      - `pack_metadata.json`

Notes:
- Gamesystem cache is stored separately from packs.
- Packs do not duplicate `.gst` bytes (they reference the cached `.gst` identity in metadata).
- All names shown here are conceptual; exact directory/file naming must comply with the naming contract.

### File identity (locked for Phase 1A)
Every imported file must have stable identity metadata:

- `fileId`: SHA-256 hash of raw bytes (hex string)
- `byteLength`: integer
- `importedAt`: ISO-8601 timestamp (local time or UTC, but be consistent)

Also store:
- `externalFileName`: verbatim original filename as supplied by picker (for user display)
- `storedPath`: internal path in app storage

This is required for:
- deterministic caching
- rebuild-only-what-changed behavior later
- clean debugging (“this output came from fileId …”)

### Deterministic IDs
- **Gamesystem cache key**:
  - derived from gamesystem root `id` and `fileId`
- **Pack ID**:
  - derived deterministically from:
    - cached gamesystem root `id`
    - primary catalog root `id`
    - primary catalog `fileId`
  (exact algorithm must be documented and stable)

### Overwrite/version rules
Gamesystem cache:
- If the selected `.gst` has the same gamesystem root `id`:
  - if `fileId` matches cached: idempotent
  - if `fileId` differs: it is a replacement only if the user explicitly chose “Replace gamesystem”

Catalog storage:
- If an imported `.cat` shares the same catalog root `id`:
  - if `fileId` matches existing: idempotent
  - if `fileId` differs: store alongside under its `fileId` and record versions in metadata
  - the “active” one for the current pack is the one imported during this session (deterministic and recorded)

No silent overwrites.

---

## Preflight Scan (Lightweight XML inspection)

### Purpose
Preflight scan exists to detect:
- correct root element type (`gameSystem` vs `catalogue`)
- required root attributes: `id` (mandatory)
- optional root attributes: `name`, `revision`, `battleScribeVersion`, `type` (names shown as raw attribute keys; do not normalize)
- compatibility:
  - catalog root contains `gameSystemId` and optionally `gameSystemRevision`
- import dependency declarations from primary catalog:
  - `catalogueLinks/catalogueLink` → collect `targetId`, `importRootEntries`

### Requirements
- Preflight scan must be safe on large files.
- It must not build full semantic models in Phase 1A.
- It must not reorder, normalize, or “clean up” attribute values.

### Output of preflight scan
Preflight scan produces a small structure per file.

For `.gst`:
- `rootTag` (must be `gameSystem`)
- `rootId` (string, required; from `id`)
- `rootName` (string, optional; from `name`)
- `rootRevision` (string, optional; from `revision`)
- `rootType` (string, optional; from `type`)

For `.cat`:
- `rootTag` (must be `catalogue`)
- `rootId` (string, required; from `id`)
- `rootName` (string, optional; from `name`)
- `declaredGameSystemId` (string, optional; from `gameSystemId`)
- `declaredGameSystemRevision` (string, optional; from `gameSystemRevision`)
- `libraryFlag` (string, optional; from `library`)
- `rootType` (string, optional; from `type`)
- `importDependencies[]` each containing:
  - `targetId` (string, required)
  - `importRootEntries` (bool, default false if absent)

---

## Dependency Detection & Prompting

### What counts as an import dependency
An import dependency is any `catalogueLink` with a `targetId`.

### Depth (locked for Phase 1A)
Phase 1A supports:
- **Depth 1** only: primary catalog → direct import dependencies

If an imported dependency catalog itself declares import dependencies, Phase 1A does not chase them automatically.
This is deferred to a later phase.

### Missing dependency detection
Given:
- primary catalog import dependency list (targetIds)
- currently selected/imported catalogs (by catalog root id)

A dependency is “missing” if no imported catalog has `rootId == targetId`.

### Prompt UX (minimum contract)
When missing dependencies are detected:
- Show a prompt listing missing dependency IDs.
- Provide actions:
  - “Import dependency” (opens picker for `.cat`)
  - “Cancel import” (aborts acquisition)

Validation of dependency import:
- When user selects a `.cat`, preflight scan its `rootId`.
- If it does not match any currently missing `targetId`, show a message and allow retry.

### Multiple dependencies
Phase 1A default: prompt sequentially for each missing dependency in deterministic order:
- sort missing dependency `targetId` ascending, prompt in that order.

---

## Validation Rules (Acquire-level)

### Root element validation
- `.gst` must have root tag `gameSystem`
- `.cat` must have root tag `catalogue`
If mismatch: acquisition fails with diagnostic and user-visible message.

### Compatibility validation (locked behavior)
If primary catalog has `declaredGameSystemId` and it does not match cached gamesystem `rootId`:
- acquisition must fail deterministically with an Acquire diagnostic.

This is not a parse diagnostic. It is a bundle consistency failure and belongs to M1.

### Duplicate catalog IDs within a pack
If two imported `.cat` files share the same catalog `rootId`:
- if `fileId` matches: treat as the same file
- if `fileId` differs:
  - store both versions and record in metadata
  - choose the “active” one deterministically for this pack:
    - Phase 1A default: most recently imported in this session

---

## Output Contract (Raw Bundle)

### Output shape (conceptual; exact type names require approval)
Acquire returns a single object containing:

- `cachedGameSystem`:
  - `fileId`
  - `byteLength`
  - `importedAt`
  - `storedPath`
  - `externalFileName` (verbatim)
  - `preflight` (rootTag, rootId, optional rootName, etc.)

- `catalogs[]` (ordered deterministically):
  - primary catalog first
  - then import dependencies sorted by `targetId` ascending
  For each:
  - `fileId`
  - `byteLength`
  - `importedAt`
  - `storedPath`
  - `externalFileName` (verbatim)
  - `preflight` (rootTag, rootId, optional fields, plus importDependencies for primary)

- `bundleMetadata`:
  - `packId`
  - `createdAt`
  - `acquireDiagnostics[]` (deterministic ordering)

### Deterministic ordering (mandatory)
Ordering MUST NOT depend on:
- selection order
- filesystem enumeration order
- platform differences

---

## Acquisition Diagnostics (allowed in M1)
M1 may emit diagnostics for:
- invalid file type/extension
- wrong root tag
- missing required attributes (`id`)
- compatibility mismatch (catalog declared gamesystem id != cached gamesystem id)
- missing dependency not provided (user cancels)
- IO errors copying to app storage

These diagnostics are Acquire-only and must not be confused with binding diagnostics (Phase 2).

Diagnostics must be:
- structured (severity + code + message)
- deterministic in ordering and content

---

## Cross-Module Invariants (locked for Phase 1)
These invariants must be true at the end of Phase 1 and are required to make Phase 2 binding deterministic.

### Invariant A — File identity is always available
For every Node produced in Phase 1 (M3), it must be possible to report:
- `sourceFileId` (from M1 fileId)
- `sourceFileType` (`gst` or `cat`)
- `sourceRootId` (root `id` attribute from preflight)
- `xmlTagName` for the node
- if the element has an `id` attribute, it must be retrievable as `elementIdAttribute` (string)

### Invariant B — Document order is preserved
- DTO children are stored in encounter order (list order == document order)
- Node children must iterate in that same order
- No reordering is allowed in Phase 1

### Invariant C — Node identity/key is deterministic
Phase 1 must define and implement a stable node identity strategy.

Minimum acceptable (Phase 1A):
- “Wrapper stability”: the same DTO instance maps to the same Node wrapper instance during a single run.

Recommended (stronger; preferred for Phase 2 determinism and future caching):
- a stable `NodeKey` that is reproducible from:
  - `sourceFileId`
  - element `id` attribute if present
  - otherwise a structural path + occurrence index
  (exact representation finalized in Phase 1B/M3 spec, but Phase 1A requires planning for it)

M1 must supply the file identity fields that make this possible (`fileId`, etc.).

---

## Required Verification (Phase 1A)

1. **Happy path**
- cached gamesystem exists
- user imports a catalog with no import dependencies
- output bundle contains cached `.gst` + 1 `.cat`

2. **First run**
- no cached gamesystem exists
- user attempts import → prompted for `.gst` → then picks `.cat`
- output bundle contains cached `.gst` + 1 `.cat`

3. **Import dependency path**
- primary catalog declares at least one `catalogueLink targetId`
- prompt occurs for missing dependency
- after importing dependency `.cat`, output bundle contains both

4. **Mismatch rejection**
- primary catalog declared gamesystem id differs from cached gamesystem root id
- acquisition fails deterministically with diagnostic

5. **Deterministic ordering**
- importing dependencies in different orders produces the same output ordering

6. **Metadata completeness**
- every stored file has `fileId`, `byteLength`, `importedAt`, `externalFileName`, `storedPath` in metadata

---

## Phase 1A Freeze Gate Checklist (M1 Acquire)
M1 Acquire can be frozen only when:
- [ ] Cached gamesystem behavior implemented (reuse unless replaced/deleted by user)
- [ ] Flow supports selecting `.gst` when cache missing
- [ ] Flow supports selecting primary `.cat`
- [ ] Files are persisted to app storage deterministically on iOS and Android
- [ ] Preflight scan detects import dependencies via `catalogueLinks/catalogueLink targetId`
- [ ] Missing import dependencies prompt user and are incorporated into bundle
- [ ] Dependency detection scope clarification is documented (Phase 1 detects import dependencies only)
- [ ] Output raw bundle contract is documented in `/docs/module_io_registry.md`
- [ ] Any new internal names were approved and logged
- [ ] Name audit checklist is completed for the change set

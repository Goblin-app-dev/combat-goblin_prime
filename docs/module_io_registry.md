# Module IO Registry

## Purpose
Defines explicit inputs and outputs for every module.
Required for phase freeze validation.

---

## M1 Acquire (Phase 1A) — FROZEN

**Status:** Frozen (2026-02-03). No behavior changes; only bug fixes with explicit approval.

### Inputs
- User-selected file bytes (gameSystem .gst, primaryCatalog .cat)
- Dependency catalog bytes (via requestDependencyBytes callback)
- SourceLocator (upstream source identification)
- Cached gamesystem state

### Outputs
- RawPackBundle containing:
  - Raw bytes for all files (lossless)
  - Preflight scan results (metadata)
  - Storage metadata (paths, fileIds)
  - PackManifest (for update checking)

### Storage Contracts
- AcquireStorage.storeFile(..., packId)

### Error Contracts
- AcquireFailure with missingTargetIds list (actionable for UI)

---

## M2 Parse (Phase 1B) — FROZEN

Converts raw XML bytes into generic DTO trees preserving structure and document order.

**Status:** Frozen (2026-02-03). No behavior changes; only bug fixes with explicit approval.

### Inputs
- RawPackBundle (from M1 Acquire)

### Outputs
- ParsedPackBundle containing:
  - ParsedFile for gameSystem (ElementDto tree + provenance)
  - ParsedFile for primaryCatalog
  - List<ParsedFile> for dependencyCatalogs
  - packId and parsedAt timestamp

### Behavior
- Parses XML bytes into ElementDto trees
- Preserves all attributes, children, text content
- Preserves document order (element sequence as declared)
- Links each ParsedFile to source via fileId
- No cross-link resolution (deferred to M3)
- No semantic validation (deferred to later phases)

### Error Contracts
- ParseFailure with fileId, sourceIndex, and diagnostic message

### Design Decision
Generic ElementDto approach chosen over typed DTOs:
- Truly lossless (any XML structure preserved)
- No premature schema commitment
- Cross-link resolution is M3/Phase 2 concern

---

## M3 Wrap (Phase 1C) — FROZEN

Converts parsed DTO trees into wrapped, indexed, navigable node graphs.

**Status:** FROZEN (2026-02-04). Bug fixes only with explicit approval.

### Inputs
- ParsedPackBundle (from M2 Parse)

### Outputs
- WrappedPackBundle containing:
  - WrappedFile for gameSystem (flat node table + idIndex)
  - WrappedFile for primaryCatalog
  - List<WrappedFile> for dependencyCatalogs
  - packId and wrappedAt timestamp

### Behavior
- Pre-order depth-first traversal of ElementDto trees
- Deterministic nodeIndex assignment (root=0, +1 per node)
- Builds parent/child relationships with NodeRef handles
- Computes depth for each node
- Builds per-file idIndex: `Map<String, List<NodeRef>>`
- Preserves provenance (fileId/fileType on every node)
- No cross-file linking
- No semantic interpretation

### Traversal Contract
- Pre-order depth-first
- Children visited in ElementDto.children order
- root.nodeIndex == 0
- Re-wrapping same input yields identical indices

### idIndex Contract
- Maps `id` attribute → List<NodeRef>
- Duplicate IDs preserved (list contains all occurrences)
- No throwing for duplicates

### Error Contracts
- WrapFailure for structural corruption only
- Not used for duplicate IDs or semantic issues

### Design Decision
Flat node table with NodeRef handles chosen over recursive structures:
- Stack-safe traversal
- Deterministic indexing
- O(1) node lookup by index
- Explicit provenance per node

---

## M4 Link (Phase 2) — FROZEN

Resolves cross-file references by building a global symbol table and linking targetId attributes on link elements.

**Status:** FROZEN (2026-02-05). Bug fixes only with explicit approval.

### Inputs
- WrappedPackBundle (from M3 Wrap)

### Outputs
- LinkedPackBundle containing:
  - SymbolTable (cross-file ID registry)
  - List<ResolvedRef> (resolution results for each link element)
  - List<LinkDiagnostic> (non-fatal diagnostics)
  - wrappedBundle reference (unchanged)
  - packId and linkedAt timestamp

### Behavior
- Builds SymbolTable by aggregating idIndex from all files in resolution order
- File resolution order: primaryCatalog → dependencyCatalogs (list order) → gameSystem
- Resolves ONLY `targetId` attribute on link elements: catalogueLink, entryLink, infoLink, categoryLink
- Does NOT resolve childId, typeId, or other ID-bearing attributes
- Does NOT verify catalogueLink resolves to root node (deferred to M5+)
- Target ordering: file resolution order, then node index within file

### Diagnostic Codes
- UNRESOLVED_TARGET: targetId not found in any file
- DUPLICATE_ID_REFERENCE: targetId found in multiple locations
- INVALID_LINK_FORMAT: missing or empty targetId (including whitespace-only)

### Error Contracts
- LinkDiagnostic for resolution issues (non-fatal, always emitted)
- LinkFailure only for corrupted M3 input or internal bugs
- In normal operation, no LinkFailure is thrown

### Design Decision
Non-fatal diagnostics chosen over throwing:
- Complete resolution even with some failures
- Downstream phases decide what to do with diagnostics
- Deterministic ordering enables reproducible debugging

---

## M5 Bind (Phase 3) — PROPOSAL

Converts LinkedPackBundle into typed, queryable entities with resolved cross-file references.

**Status:** PROPOSAL — awaiting approval. No implementation until approved.

### Inputs
- LinkedPackBundle (from M4 Link)

### Outputs
- BoundPackBundle containing:
  - List<BoundEntry> (all bound entries)
  - List<BoundProfile> (all bound profiles)
  - List<BoundCategory> (all bound categories)
  - List<BindDiagnostic> (semantic issues)
  - Query surface for lookups
  - linkedBundle reference (unchanged)
  - packId and boundAt timestamp

### Entity Types (Initial Slice)
- BoundEntry: selectionEntry, selectionEntryGroup, resolved entryLink
- BoundProfile: profile with characteristics
- BoundCategory: categoryEntry, resolved categoryLink
- BoundCost: cost value with type reference
- BoundConstraint: constraint data (NOT evaluated)

### Behavior
- Traverses all files in file resolution order
- Binds selectionEntry/selectionEntryGroup → BoundEntry
- Binds profile → BoundProfile
- Binds categoryEntry → BoundCategory
- Follows entryLinks, infoLinks, categoryLinks using M4's ResolvedRefs
- Applies shadowing policy: first-match-wins by file order
- Builds query indices for O(1) lookups

### Query Surface
- entryById(id), profileById(id), categoryById(id)
- allEntries, allProfiles, allCategories
- entriesInCategory(categoryId)
- profilesForEntry(entryId)
- categoriesForEntry(entryId)
- costsForEntry(entryId)

### Shadowing Policy
First-match-wins based on file resolution order:
1. primaryCatalog (highest precedence)
2. dependencyCatalogs (in list order)
3. gameSystem (lowest precedence)

When ID matches multiple targets: use first, emit SHADOWED_DEFINITION diagnostic.

### Diagnostic Codes (Proposed)
- UNRESOLVED_ENTRY_LINK: entryLink target not found
- UNRESOLVED_INFO_LINK: infoLink target not found
- UNRESOLVED_CATEGORY_LINK: categoryLink target not found
- SHADOWED_DEFINITION: ID matched multiple targets, using first
- INVALID_PROFILE_TYPE: profile references unknown profileType
- INVALID_COST_TYPE: cost references unknown costType

### Error Contracts
- BindDiagnostic for semantic issues (non-fatal)
- BindFailure only for corrupted M4 input or internal bugs
- In normal operation, no BindFailure is thrown

### Constraint Boundary
M5 represents constraints. M5 does NOT evaluate constraints.
Constraint evaluation requires roster state (deferred to M6+).

---

## Index Reader (Future — Phase 1B+)

Reads and caches the upstream repository index for dependency resolution and update checking.

### Inputs
- SourceLocator (repo URL, branch)
- Cached index state (if available)

### Outputs
- Mapping: rootId → { downloadUrl, versionToken }
- Cache metadata (lastRefreshed, httpETag)

### Behavior
- Parses index.bsi / index.xml from BSData repository
- Provides lookup: given rootId, returns download URL and version token
- Caches parsed index locally with HTTP caching tokens (ETag/Last-Modified)
- Refresh strategy: conditional request (returns "not modified" if unchanged)

### Side Effects
- Writes cached index to local storage

### Stored Artifacts
- Cached index file with timestamp and caching tokens

---

## Downloader (Future — Phase 1B+)

Fetches file bytes from remote URLs.

### Inputs
- Download URL (from Index Reader lookup)

### Outputs
- Raw bytes (List<int>)
- HTTP response metadata (status, headers)

### Behavior
- Performs HTTP GET request
- Returns bytes on success, structured error on failure
- No interpretation of content; bytes passed to M1 Acquire

### Side Effects
- Network I/O only; no local storage

---

## Orchestrator (Future — Phase 1B+)

Coordinates the full acquire → parse → bind workflow and manages attempt state.

### Inputs
- User selection (primary catalog rootId)
- SourceLocator
- Cached game system state

### Outputs
- Workflow completion status
- Persisted PackManifest (only after downstream success)

### Responsibilities
- Calls M1 Acquire with user-selected files
- When M1 throws AcquireFailure(missingTargetIds):
  - Returns structured result to UI with complete list of missing dependencies
  - Does NOT fail silently on first missing dependency
- After dependencies downloaded:
  - Re-calls M1 Acquire until RawPackBundle produced
- After downstream parse/bind success:
  - Persists PackManifest (installed record)
  - Triggers cleanup of raw dependency files
- Maintains attempt status wrapper for crash-resume UX

### Attempt Status Wrapper
Conceptual workflow state (not necessarily a separate type):
- in_progress: M1 succeeded, downstream pending
- failed: downstream failed, resumable
- completed: manifest persisted, cleanup done
- cancelled: user cancelled

This is distinct from PackManifest, which is content identity + provenance.

### Side Effects
- Persists installed PackManifest
- Deletes raw dependency files after success

---

## Cleanup (Future — Phase 1B+)

Deletes raw dependency files after downstream success.

### Inputs
- packId
- List of dependency file paths

### Outputs
- Confirmation of deletion

### Behavior
- Only executes after:
  - Parse succeeded
  - Bind succeeded
  - PackManifest persisted
- Deletes only dependency catalog raw files scoped to packId
- Primary catalog and game system files may be retained (configurable)

### Constraints
- NEVER deletes anything until install success confirmed
- Deletion narrowly scoped to packId-owned paths

---

## Update Checker (Future — Phase 1B+)

Detects upstream changes and orchestrates re-acquisition.

### Inputs
- Persisted PackManifest records
- Refreshed index from Index Reader

### Outputs
- List of packs with updates available
- Update execution status

### Boot-time Behavior
- On boot: conditional refresh of index (ETag/Last-Modified)
- If offline/unavailable: use cached index, surface "update check unavailable" state
- Compare remote version tokens against stored PackManifest values for:
  - Game system
  - Primary catalog
  - Each dependency catalog
- If any changed: mark pack "update available"

### Update Execution
When user accepts update:
1. Delete all pack-associated data (storage + derived)
2. Re-acquire using stored selection (primary rootId) + SourceLocator
3. Run downstream parse/bind pipeline
4. Persist new PackManifest
5. Cleanup raw dependency files

### Definition of "Update"
Update = delete all derived data + reacquire all files fresh.
No incremental reconciliation in initial implementation.

### Version Token Strategy
- Tier 1 (check): index version token for cheap comparison
- Tier 2 (verify): SHA-256 fileId after download

---

Modules may not access data outside their declared IO.

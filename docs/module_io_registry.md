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

## M5 Bind (Phase 3) — FROZEN

Converts LinkedPackBundle into typed, queryable entities with resolved cross-file references.

**Status:** FROZEN (2026-02-10). Bug fixes only with explicit approval.

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
- Entry-root detection: binds entries whose parent is not an entry tag (container-agnostic)
- Profile/category-root detection: binds those without entry ancestor
- Follows entryLinks, infoLinks, categoryLinks using M4's ResolvedRefs
- Applies shadowing policy: first-match-wins by file order
- Uses linkedBundle.linkedAt for deterministic boundAt timestamp
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

### Diagnostic Codes
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

## M6 Evaluate (Phase 4) — FROZEN

Evaluates constraints against selection snapshot to determine satisfaction/violation.

**Status:** FROZEN (2026-02-11). Bug fixes only with explicit approval.

### Inputs
- BoundPackBundle (from M5 Bind)
- SelectionSnapshot (contract interface defining roster state)

### Outputs
- EvaluationReport containing:
  - List<ConstraintEvaluation> (all boundary evaluations)
  - EvaluationSummary (aggregate counts)
  - List<EvaluationWarning> (non-fatal issues)
  - List<EvaluationNotice> (informational messages)
  - boundBundle reference (unchanged)
  - packId and evaluatedAt timestamp
- EvaluationTelemetry (optional, non-deterministic instrumentation)

### SelectionSnapshot Contract
Abstract interface defining roster state operations:
- orderedSelections() → List<String>
- entryIdFor(selectionId) → String
- parentOf(selectionId) → String?
- childrenOf(selectionId) → List<String>
- countFor(selectionId) → int
- isForceRoot(selectionId) → bool

M6 does NOT define a concrete roster model.

### Behavior
- Validates invariants (cycles, duplicate children, unknown children)
- Builds precomputed count tables for O(1) lookup
- Evaluates constraints in deterministic order (root-first DFS for selections, stored order for constraints)
- Computes actual values based on scope (self, parent, force, roster)
- Determines outcome (satisfied, violated, notApplicable, error)
- Uses boundBundle.boundAt for deterministic evaluatedAt timestamp

### Counting Semantics
For field=selections: actualValue counts only selections whose entryId equals the constrained entry's ID.

### Boundary Evaluation Model
Same constraint evaluated once per (constraint, boundary instance) pair.
- self scope: one evaluation per selection of the entry
- parent scope: one evaluation per selection's parent boundary
- force scope: one evaluation per force root
- roster scope: one evaluation total

### Warning Codes
- UNKNOWN_CONSTRAINT_TYPE: constraint type not recognized
- UNKNOWN_CONSTRAINT_FIELD: constraint field not recognized
- UNKNOWN_CONSTRAINT_SCOPE: constraint scope not recognized
- UNDEFINED_FORCE_BOUNDARY: force scope requested but no force root found
- MISSING_ENTRY_REFERENCE: selection references entry not in bundle

### Notice Codes
- CONSTRAINT_SKIPPED: constraint skipped (condition not met, deferred)
- EMPTY_SNAPSHOT: snapshot has no selections

### Error Contracts
- EvaluationWarning/EvaluationNotice for non-fatal issues
- EvaluateFailure only for invariant violations:
  - NULL_PROVENANCE: required provenance pointers missing
  - CYCLE_DETECTED: cycle in selection hierarchy
  - INVALID_CHILDREN_TYPE: childrenOf must return List
  - DUPLICATE_CHILD_ID: childrenOf contains duplicate IDs
  - UNKNOWN_CHILD_ID: childrenOf references unknown selection
  - INTERNAL_ASSERTION: M6 implementation bug
- In normal operation, no EvaluateFailure is thrown

### Determinism Contract
Same BoundPackBundle + same SelectionSnapshot → identical EvaluationReport.
EvaluationTelemetry.evaluationDuration is explicitly excluded from determinism.

### Scope Boundaries
M6 MAY evaluate constraints. M6 MUST NOT evaluate rules (deferred to M7+).

---

## M7 Applicability (Phase 5) — FROZEN

Evaluates conditions to determine whether constraints, modifiers, and other conditional elements apply to the current roster state. Returns tri-state applicability (applies/skipped/unknown).

**Status:** FROZEN (2026-02-12). Bug fixes only with explicit approval.

### Inputs
- BoundPackBundle (from M5 Bind)
- SelectionSnapshot (same contract as M6)
- WrappedNode conditionSource (node containing conditions)
- String sourceFileId (provenance, index-ready)
- NodeRef sourceNode (provenance, index-ready)
- String contextSelectionId (scope resolution anchor)

### Outputs
- ApplicabilityResult containing:
  - ApplicabilityState state (tri-state: applies, skipped, unknown)
  - String? reason (human-readable explanation, deterministic)
  - List<ConditionEvaluation> conditionResults (leaf evaluations in XML order)
  - ConditionGroupEvaluation? groupResult (if conditions grouped)
  - List<ApplicabilityDiagnostic> diagnostics (per-result, for voice/search)
  - Provenance identity (sourceFileId, sourceNode, targetId)

### Behavior
- Finds `<conditions>` or `<conditionGroups>` children of source node
- If no conditions found → return state=applies
- Evaluates each condition against snapshot (tri-state per leaf)
- Applies AND/OR logic for condition groups (unknown-aware)
- Returns ApplicabilityResult with all evaluations

### Condition Types (Fixture-aligned)
- atLeast: actual >= required
- atMost: actual <= required
- greaterThan: actual > required
- lessThan: actual < required
- equalTo: actual == required
- notEqualTo: actual != required
- instanceOf: membership/type test
- notInstanceOf: negated membership/type test

### Scope Resolution (Keyword OR ID)
**Keywords:** self, parent, ancestor, roster, force
**ID-like:** categoryId (evaluate within category boundary), entryId (deferred semantics)
Unknown scope → state=unknown with diagnostic

### Field Resolution (Keyword OR ID)
**Keywords:** selections, forces
**ID-like:** costTypeId (sum costs of that type, if snapshot supports)
Unknown field → state=unknown with diagnostic

### Child Inclusion Semantics
- includeChildSelections: true=subtree, false=direct-only
- includeChildForces: true=nested forces, false=direct-only
If snapshot cannot compute distinction → state=unknown

### Diagnostic Codes
- UNKNOWN_CONDITION_TYPE
- UNKNOWN_CONDITION_SCOPE_KEYWORD
- UNKNOWN_CONDITION_FIELD_KEYWORD
- UNRESOLVED_CONDITION_SCOPE_ID
- UNRESOLVED_CONDITION_FIELD_ID
- UNRESOLVED_CHILD_ID
- SNAPSHOT_DATA_GAP_COSTS
- SNAPSHOT_DATA_GAP_CHILD_SEMANTICS
- SNAPSHOT_DATA_GAP_CATEGORIES
- SNAPSHOT_DATA_GAP_FORCE_BOUNDARY

### Group Logic (Unknown-aware)
**AND:** any skipped → skipped; else any unknown → unknown; else applies
**OR:** any applies → applies; else any unknown → unknown; else skipped

### Error Contracts
- ApplicabilityDiagnostic for semantic issues (non-fatal)
- ApplicabilityFailure only for corrupted M5 input or internal bugs
- Unknown type/scope/field → state=unknown with diagnostic, NOT exception
- In normal operation, no ApplicabilityFailure is thrown

### Service Methods
- evaluate(): single-source evaluation
- evaluateMany(): bulk evaluation preserving input order

### Determinism Contract
Same inputs → identical ApplicabilityResult.
Condition evaluation order matches XML traversal.
evaluateMany preserves input order.

### Scope Boundaries
M7 MAY evaluate conditions. M7 MUST NOT evaluate constraints (M6's job) or apply modifiers (M8+ concern).

---

## M8 Modifiers (Phase 6) — FROZEN

Applies modifier operations to produce effective values for entry characteristics, costs, constraints, and other modifiable fields.

**Status:** FROZEN (2026-02-12). All 18 invariant tests pass.

### Inputs
- BoundPackBundle (from M5 Bind)
- SelectionSnapshot (same contract as M6/M7)
- WrappedNode modifierSource (node containing modifiers)
- String sourceFileId (provenance, index-ready)
- NodeRef sourceNode (provenance, index-ready)
- String contextSelectionId (context for condition evaluation)
- ApplicabilityService (M7 service for condition evaluation)

### Outputs
- ModifierResult containing:
  - ModifierTargetRef target (what was modified)
  - ModifierValue? baseValue (value before modifiers)
  - ModifierValue? effectiveValue (value after modifiers)
  - List<ModifierOperation> appliedOperations (operations that were applied)
  - List<ModifierOperation> skippedOperations (operations skipped, not applicable)
  - List<ModifierDiagnostic> diagnostics (issues encountered)
  - Provenance identity (sourceFileId, sourceNode)

### Behavior
- Finds `<modifier>` or `<modifiers>` children of source node
- For each modifier, checks applicability via M7
- If applicable, applies operation to target
- Returns ModifierResult with all operations

### Modifier Types (Initial Set)
- set: Replace value with modifier value
- increment: Add modifier value to current value
- decrement: Subtract modifier value from current value
- append: Append string to current value

### Field Kind Disambiguation
ModifierTargetRef includes FieldKind enum to resolve ambiguity:
- characteristic: Profile characteristic field
- cost: Cost type field
- constraint: Constraint value field
- metadata: Entry metadata (name, hidden, etc.)

### Diagnostic Codes
- UNKNOWN_MODIFIER_TYPE: Modifier type not recognized
- UNKNOWN_MODIFIER_FIELD: Field not recognized
- UNKNOWN_MODIFIER_SCOPE: Scope keyword not recognized
- UNRESOLVED_MODIFIER_TARGET: Target ID not found in bundle
- INCOMPATIBLE_VALUE_TYPE: Value type incompatible with field
- UNSUPPORTED_TARGET_KIND: Target kind not supported for operation
- UNSUPPORTED_TARGET_SCOPE: Scope not supported for target kind

### Error Contracts
- ModifierDiagnostic for semantic issues (non-fatal)
- ModifierFailure only for corrupted M5 input or internal bugs
- Unknown type/field/scope → diagnostic, operation skipped (NOT exception)
- In normal operation, no ModifierFailure is thrown

### Service Methods
- applyModifiers(): single-target application
- applyModifiersMany(): bulk application preserving input order

### Determinism Contract
Same inputs → identical ModifierResult.
Modifier application order matches XML traversal.
applyModifiersMany preserves input order.

### Scope Boundaries
M8 MAY apply modifiers. M8 MUST NOT evaluate constraints (M6's job) or evaluate conditions (M7's job).

---

## Orchestrator v1 — FROZEN

Single deterministic entrypoint that coordinates M6/M7/M8 evaluation to produce a unified ViewBundle.

**Status:** FROZEN (2026-02-12). All 12 smoke tests pass.

### Design Pattern
Orchestrator is a **coordinator** (not pure composer):
- Takes frozen inputs (BoundPackBundle + SelectionSnapshot)
- Internally calls M6 → M7 → M8 in fixed order
- Returns complete ViewBundle with all results

### Inputs
- OrchestratorRequest containing:
  - BoundPackBundle (from M5 Bind, read-only)
  - SelectionSnapshot (current roster state, read-only)
  - OrchestratorOptions (output configuration)

### Outputs
- ViewBundle containing:
  - List<ViewSelection> selections (computed views)
  - EvaluationReport (M6, preserved)
  - List<ApplicabilityResult> (M7, preserved)
  - List<ModifierResult> (M8, preserved)
  - List<OrchestratorDiagnostic> (merged diagnostics)
  - BoundPackBundle reference (for downstream lookups)

### Behavior
1. Validate inputs (check BoundPackBundle integrity)
2. Call M6 evaluateConstraints() with snapshot
3. For each selection in snapshot.orderedSelections():
   a. Call M7 evaluate() for applicable conditions
   b. Call M8 applyModifiers() for applicable modifiers
   c. Build ViewSelection with computed values
4. Aggregate all results into ViewBundle
5. Merge diagnostics from M6/M7/M8

### Diagnostic Codes
- SELECTION_NOT_IN_BUNDLE: Selection references entry not in bundle
- EVALUATION_ORDER_VIOLATION: Internal ordering invariant violated (fatal)

### Error Contracts
- OrchestratorDiagnostic for non-fatal issues
- OrchestratorFailure only for corrupted M5 input or internal bugs
- In normal operation, no OrchestratorFailure is thrown

### Service Methods
- buildViewBundle(OrchestratorRequest): returns ViewBundle

### Determinism Contract
- Same OrchestratorRequest → identical ViewBundle (except evaluatedAt)
- Evaluation order: M6 → M7 → M8 (fixed)
- Selection order: matches snapshot.orderedSelections() exactly
- Diagnostic order: M6, then M7, then M8, then Orchestrator

### Scope Boundaries
Orchestrator MAY coordinate M6/M7/M8 calls. Orchestrator MUST NOT add semantic interpretation, modify inputs, persist data, or produce UI elements.

---

## M9 Index-Core — PROPOSED

Builds search index for player-facing queries (find unit, find weapon, what does rule X do).

**Status:** PROPOSED (2026-02-13, Rev 2). Awaiting approval.

### Inputs
- BoundPackBundle (from M5 Bind, read-only)

### Outputs
- IndexBundle containing:
  - List<UnitDoc> (indexed units with characteristics as fields)
  - List<WeaponDoc> (indexed weapons with characteristics as fields)
  - List<RuleDoc> (indexed rules with descriptions)
  - Lookup maps (unitsByKey, unitsByName, weaponsByKey, etc.)
  - Map<String, List<String>> byCharacteristicNameToken (inverted index facet)
  - List<IndexDiagnostic> (issues encountered, sorted)
  - boundBundle reference (for provenance chain)
  - packId and indexedAt timestamp

### Document Kinds (v1)
- UnitDoc, WeaponDoc, RuleDoc only
- Characteristics are List<IndexedCharacteristic> fields (NOT standalone docs)
- IndexedCharacteristic: (name, typeId, valueText, normalizedToken)

### Behavior
- Traverses BoundEntry roots and profiles
- Classifies profiles by typeName to determine doc type
- Build order: RuleDoc first (for linking), then WeaponDoc, then UnitDoc
- Builds inverted index facets (byCharacteristicNameToken)
- All doc emission and lookups sorted by stable keys (no unordered iteration)
- Uses lowercase normalization for name searches

### RuleDoc Sources (v1)
- BoundRule entities (if M5 provides them)
- BoundProfile where typeName = "Abilities" with description
- Weapon keywords that resolve to rule entries

### Diagnostic Codes (7 codes)
- MISSING_NAME: Entry/profile has empty or missing name
- DUPLICATE_DOC_KEY: Same unit/weapon key encountered twice
- DUPLICATE_RULE_CANONICAL_KEY: Same rule canonical key encountered twice
- UNKNOWN_PROFILE_TYPE: Profile typeName not recognized
- EMPTY_CHARACTERISTICS: Unit/weapon has no characteristics
- TRUNCATED_DESCRIPTION: Rule description exceeded max length (>1000 chars)
- LINK_TARGET_MISSING: Unit→weapon, weapon→rule, or keyword→rule link cannot resolve

### Error Contracts
- IndexDiagnostic for indexing issues (non-fatal)
- IndexFailure only for corrupted M5 input or internal bugs
- In normal operation, no IndexFailure is thrown

### Service Methods
- buildIndex(BoundPackBundle): returns IndexBundle

### Determinism Contract
- Same BoundPackBundle → identical IndexBundle (except indexedAt)
- All doc lists sorted alphabetically by key
- All lookup maps sorted alphabetically by key
- Diagnostics sorted by (sourceFileId, nodeIndex)
- No unordered iteration anywhere

### Scope Boundaries
M9 MAY build search indices and inverted index facets. M9 MUST NOT depend on M6/M7/M8 (v1), modify BoundPackBundle, persist index, or make network calls.

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

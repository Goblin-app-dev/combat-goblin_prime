# Glossary

This glossary defines all public concepts used in the system.
No implied or informal terminology is allowed.

---

## Gamesystem
A `.gst` file representing the root ruleset context.

## Catalog
A `.cat` file representing a modular data pack loaded under a gamesystem.

## Pack ID
Deterministic identifier for a stored pack directory.

## Raw Pack Bundle
The lossless collection of source files and metadata produced by M1 Acquire.

## Diagnostic
Structured acquisition diagnostics surface; Phase 1A uses empty list by default.

## Import Dependency
A catalog-to-catalog reference declared via `<catalogueLink targetId="...">` in XML. Represents a required dependency that must be acquired before the referencing catalog can be fully processed.

## Update
The operation of refreshing an installed pack when upstream changes are detected. Definition: delete all pack-associated data (storage + derived) → reacquire all files fresh → reparse → rebind. No incremental reconciliation; always a full reinstall.

## Dependency Record
Version information for a single dependency catalog; survives raw file deletion for update checking.

## Source Locator
Identifies the upstream source (repo URL, branch) for update checking.

## Pack Manifest
Persisted record of an installed pack containing version tokens for all files; enables update detection after dependency cleanup. Represents content identity and provenance.

## Attempt Status Wrapper
Conceptual workflow state tracking an install attempt (not necessarily a separate type). Distinct from PackManifest. States include: in_progress (M1 succeeded, downstream pending), failed (downstream failed, resumable), completed (manifest persisted, cleanup done), cancelled (user cancelled). Enables crash-resume UX without polluting M1.

## Index (BSData)
Upstream repository manifest (index.bsi / index.xml) that lists available files, versions, and download URLs. Used for dependency resolution and update detection.

## Version Token
Identifier used to detect file changes. Tier 1: index-provided version for cheap checks. Tier 2: SHA-256 fileId for verification after download.

## Element DTO
Generic representation of any XML element preserving tag name, attributes, child elements, and text content. Document order preserved via ordered child lists.

## Parsed File
A single XML file converted to Element DTO form with source provenance (fileId linking back to raw bytes).

## Parsed Pack Bundle
The complete DTO output for a pack: parsed game system + primary catalog + dependency catalogs. Produced by M2 Parse.

## Parse Failure
Exception thrown when XML parsing fails, with diagnostic context (fileId, sourceIndex, message).

## Node Ref
Strongly-typed handle for node identity within a WrappedFile. Contains nodeIndex. Prevents raw integer indices from leaking outside M3 internals.

## Wrapped Node
Indexed, navigable representation of an XML element with explicit provenance. Contains tag, attributes, text, parent/child references (as NodeRef), depth, and source fileId/fileType. Part of a flat node table in WrappedFile.

## Wrapped File
Per-file node table produced by M3 Wrap. Contains flat list of WrappedNode plus idIndex mapping `id` attribute to List<NodeRef>. No cross-file linking.

## Wrapped Pack Bundle
Complete M3 output for a pack: wrapped game system + primary catalog + dependency catalogs. One-to-one correspondence with ParsedPackBundle. Produced by M3 Wrap.

## Wrap Failure
Exception thrown for structural corruption during M3 wrapping. Not used for duplicate IDs or semantic issues.

## Symbol Table
Cross-file ID registry built by M4 Link. Aggregates idIndex from all WrappedFiles in file resolution order (primaryCatalog → dependencyCatalogs → gameSystem). Maps ID string to list of (fileId, NodeRef) pairs. Lookup returns targets in deterministic order.

## Resolved Ref
Resolution result for a single cross-file reference. Contains sourceFileId, sourceNode (NodeRef), targetId, and list of resolved targets as (fileId, NodeRef) pairs. Targets ordered by file resolution order, then node index within file.

## Link Diagnostic
Non-fatal issue detected during M4 Link resolution. Closed code set: UNRESOLVED_TARGET (targetId not found), DUPLICATE_ID_REFERENCE (targetId found multiple times), INVALID_LINK_FORMAT (missing or empty targetId). Always emitted; never thrown.

## Link Failure
Exception thrown by M4 Link only for corrupted M3 input or internal bugs. In normal operation, no LinkFailure is thrown. Resolution issues are reported via LinkDiagnostic instead.

## Linked Pack Bundle
Complete M4 output for a pack: SymbolTable + resolved references + diagnostics + unchanged WrappedPackBundle reference. Produced by M4 Link (LinkService).

## Link Service
Service that performs cross-file reference resolution. Converts WrappedPackBundle to LinkedPackBundle. Resolves only targetId on link elements (catalogueLink, entryLink, infoLink, categoryLink).

## Bound Pack Bundle
Complete M5 output containing bound entities (entries, profiles, categories) with query surface for lookups and navigation. Preserves provenance chain (M5 → M4 → M3 → M2 → M1). Produced by M5 Bind (BindService).

## Bound Entry
Entry with resolved children, profiles, categories, costs, and constraints. Represents selectionEntry or selectionEntryGroup with all links followed. Includes isGroup and isHidden flags, plus sourceFileId/sourceNode for provenance.

## Bound Profile
Profile with characteristics and type reference. Extracted from profile elements with ordered name-value characteristic pairs. Includes typeId/typeName (may be null if type not found) and provenance.

## Bound Category
Category definition with primary flag. Represents categoryEntry or resolved categoryLink. Includes isPrimary flag and provenance.

## Bound Cost
Cost value with type reference. Extracted from cost elements. Contains typeId, typeName (may be null), numeric value, and provenance.

## Bound Constraint
Constraint data (NOT evaluated). Captures raw constraint fields (type, field, scope, value) without evaluation. Evaluation requires roster state (deferred to M6+).

## Bind Diagnostic
Non-fatal semantic issue detected during M5 Bind. Closed code set: UNRESOLVED_ENTRY_LINK, UNRESOLVED_INFO_LINK, UNRESOLVED_CATEGORY_LINK, SHADOWED_DEFINITION. Always accumulated; never thrown.

## Bind Failure
Exception thrown by M5 Bind only for corrupted M4 input or internal bugs. In normal operation, no BindFailure is thrown. Semantic issues are reported via BindDiagnostic instead.

## Bind Service
Service that performs entity binding. Converts LinkedPackBundle to BoundPackBundle. Uses entry-root detection (container-agnostic) to identify top-level entries.

## Entry-Root Detection
M5 binding strategy where an entry is considered a "root" if its parent node is not an eligible entry tag. Container-agnostic: works with any schema variant without maintaining container tag lists.

## Evaluate Failure
Exception thrown by M6 Evaluate only for enumerated invariant violations (NULL_PROVENANCE, CYCLE_DETECTED, INVALID_CHILDREN_TYPE, DUPLICATE_CHILD_ID, UNKNOWN_CHILD_ID, INTERNAL_ASSERTION). In normal operation, no EvaluateFailure is thrown. Semantic issues are reported via warnings/notices instead. Parallels BindFailure/LinkFailure pattern.

## Evaluation Report
Strictly deterministic top-level M6 output containing evaluated constraint state. Preserves provenance chain (M6 → M5 → M4 → M3 → M2 → M1). Excludes telemetry data. Renamed from EvaluationResult for clarity.

## Rule Evaluation (RESERVED — M7+)
Result of evaluating a single rule against roster state. Contains outcome (RuleEvaluationOutcome) and any violations detected. **Reserved for M7+; M6 does NOT produce this type.**

## Rule Evaluation Outcome (RESERVED — M7+)
Enum representing the result of a rule evaluation: PASSED, FAILED, SKIPPED (not applicable), ERROR (evaluation failed). **Reserved for M7+; M6 does NOT produce this type.**

## Rule Violation (RESERVED — M7+)
Specific violation of a rule. Contains violation details, severity, affected entities, and remediation hints. **Reserved for M7+; M6 does NOT produce this type.**

## Constraint Evaluation
Result of evaluating a single (constraint, boundary instance) pair. Emitted per boundary instance, so the same constraint may produce multiple evaluations. Contains outcome (ConstraintEvaluationOutcome), actualValue, requiredValue, and violation details if violated.

## Constraint Evaluation Outcome
Enum representing the result of a constraint evaluation: SATISFIED, VIOLATED, NOT_APPLICABLE, ERROR.

## Constraint Violation
Specific violation of a constraint. Contains violation details, current value, required value, and affected entities.

## Evaluation Summary
Aggregate summary of all evaluations for a roster. Contains pass/fail counts (totalEvaluations, satisfiedCount, violatedCount, notApplicableCount, errorCount) and hasViolations boolean (mechanical check: violatedCount > 0). Does NOT imply roster legality.

## Evaluation Telemetry
Non-deterministic instrumentation data from evaluation. Contains evaluationDuration (runtime measurement). Explicitly excluded from determinism contract and equality comparisons. Renamed from EvaluationStatistics.

## Evaluation Notice
Informational message from evaluation that does not affect validity. Used for deprecation warnings, optimization hints, etc.

## Evaluation Warning
Non-fatal issue detected during evaluation that may affect roster validity but does not block processing.

## Evaluation Scope
Defines the boundary of what is being evaluated: full roster, specific selection, or subset. Controls evaluation depth and breadth.

## Evaluation Applicability (RESERVED — M7+)
Determines whether a rule or constraint applies to a given context. Based on scope, conditions, and selection state. **Reserved for M7+; M6 does NOT produce this type.**

## Evaluation Source Ref
Reference to the source definition (rule, constraint, modifier) that produced an evaluation result. Enables traceability from result to source.

## Evaluation Context (RESERVED — M7+)
Runtime state available during evaluation: roster selections, active modifiers, resolved values, parent context. **Reserved for M7+; M6 does NOT produce this type.**

## Selection Snapshot
Contract interface for roster state input to M6. Defines required operations (orderedSelections, entryIdFor, parentOf, childrenOf, countFor, isForceRoot) but not concrete types. Implementation is outside M6 scope.

## Bound Rule (PROPOSAL — M7)
Game rule definition with name, description, and provenance. Represents `rule` elements from BSData. Contains id, name, description text, publicationId, page, hidden flag, and source provenance. **Proposed for M7 Rules; not yet approved.**

## Extended Bound Pack Bundle (PROPOSAL — M7)
M7 output extending M5's BoundPackBundle with bound rules. Maintains M5 output unchanged while adding rule-specific content. Contains rule list, query surface, and rule diagnostics. **Proposed for M7 Rules; not yet approved.**

## Rules Diagnostic (PROPOSAL — M7)
Non-fatal semantic issue during M7 rule binding. Closed code set: UNRESOLVED_RULE_LINK, SHADOWED_RULE_DEFINITION, EMPTY_RULE_DESCRIPTION. Always accumulated; never thrown. **Proposed for M7 Rules; not yet approved.**

## Rules Failure (PROPOSAL — M7)
Exception thrown by M7 Rules only for corrupted M5 input or internal bugs. In normal operation, no RulesFailure is thrown. Semantic issues are reported via RulesDiagnostic instead. **Proposed for M7 Rules; not yet approved.**

## Rules Service (PROPOSAL — M7)
Service that binds rule elements. Converts BoundPackBundle to ExtendedBoundPackBundle. Uses same shadowing policy as M5. **Proposed for M7 Rules; not yet approved.**

## Applicability State (M7 Applicability)
Tri-state enum representing condition evaluation outcome: `applies` (conditions true or no conditions), `skipped` (conditions evaluated false), `unknown` (cannot determine due to missing data, unsupported operator, or unresolved reference). Replaces boolean applicability.

## Applicability Result (M7 Applicability)
M7 output containing tri-state applicability, deterministic reason, leaf condition results, optional group result, per-result diagnostics, and index-ready provenance (sourceFileId, sourceNode). Diagnostics attached to result (not mutable service state) for voice/search context. Deterministic given same inputs.

## Condition Evaluation (M7 Applicability)
Result of evaluating a single condition element against roster state. Contains condition type, field (keyword or costTypeId), scope (keyword or categoryId/entryId), required/actual values, tri-state result, includeChildSelections/Forces flags, reasonCode, and provenance. Unknown field/scope/type produces state=unknown, not skipped.

## Condition Group Evaluation (M7 Applicability)
Result of evaluating an AND/OR condition group with unknown-aware logic. AND: any skipped → skipped, else any unknown → unknown, else applies. OR: any applies → applies, else any unknown → unknown, else skipped. Prevents "unknown treated as false" errors.

## Applicability Diagnostic (M7 Applicability)
Non-fatal issue detected during M7 Applicability evaluation. Closed code set: UNKNOWN_CONDITION_TYPE, UNKNOWN_CONDITION_SCOPE_KEYWORD, UNKNOWN_CONDITION_FIELD_KEYWORD, UNRESOLVED_CONDITION_SCOPE_ID, UNRESOLVED_CONDITION_FIELD_ID, UNRESOLVED_CHILD_ID, SNAPSHOT_DATA_GAP_COSTS, SNAPSHOT_DATA_GAP_CHILD_SEMANTICS, SNAPSHOT_DATA_GAP_CATEGORIES, SNAPSHOT_DATA_GAP_FORCE_BOUNDARY. Always accumulated; never thrown.

## Applicability Failure (M7 Applicability)
Exception thrown by M7 Applicability only for corrupted M5 input or internal bugs. In normal operation, no ApplicabilityFailure is thrown. Unknown types/scopes/fields produce state=unknown with diagnostics, not exceptions.

## Applicability Service (M7 Applicability)
Service that evaluates conditions against roster state. Provides evaluate() for single-source and evaluateMany() for bulk evaluation. Takes conditionSource node, sourceFileId, sourceNode, SelectionSnapshot, BoundPackBundle, and contextSelectionId. Returns ApplicabilityResult with tri-state outcome. Does not modify M6.

## Modifier Value (M8 Modifiers)
Type-safe variant wrapper for modifier values. Sealed class with subtypes: IntModifierValue, DoubleModifierValue, StringModifierValue, BoolModifierValue. Replaces `dynamic` with explicit type discrimination.

## Field Kind (M8 Modifiers)
Enum disambiguating field namespace for modifier targets: `characteristic` (profile field), `cost` (cost type field), `constraint` (constraint value field), `metadata` (entry metadata). Resolves ambiguity when field strings could belong to multiple namespaces.

## Modifier Target Ref (M8 Modifiers)
Reference to a modifier target with field namespace disambiguation. Contains targetId, field, fieldKind, optional scope, and provenance (sourceFileId, sourceNode). Combines targetId + field + fieldKind for unambiguous reference.

## Modifier Operation (M8 Modifiers)
Single modifier operation with parsed data. Contains operationType (set, increment, decrement, append), target (ModifierTargetRef), value (ModifierValue), isApplicable flag (derived from M7), reasonSkipped, and provenance. Operations with isApplicable=false are recorded but not applied.

## Modifier Result (M8 Modifiers)
M8 output containing base value, effective value, applied operations, skipped operations, diagnostics, and provenance. Deterministic: same inputs yield identical result. Operations applied in XML traversal order. Skipped operations preserved for transparency.

## Modifier Diagnostic (M8 Modifiers)
Non-fatal issue during M8 Modifiers processing. Closed code set: UNKNOWN_MODIFIER_TYPE, UNKNOWN_MODIFIER_FIELD, UNKNOWN_MODIFIER_SCOPE, UNRESOLVED_MODIFIER_TARGET, INCOMPATIBLE_VALUE_TYPE, UNSUPPORTED_TARGET_KIND, UNSUPPORTED_TARGET_SCOPE. Always accumulated; never thrown.

## Modifier Failure (M8 Modifiers)
Exception thrown by M8 Modifiers only for corrupted M5 input or internal bugs. In normal operation, no ModifierFailure is thrown. Unknown types/fields/scopes produce diagnostics and skip operations, not exceptions.

## Modifier Service (M8 Modifiers)
Service that applies modifiers to produce effective values. Provides applyModifiers() for single-target and applyModifiersMany() for bulk application. Takes modifierSource node, BoundPackBundle, SelectionSnapshot, contextSelectionId, and ApplicabilityService. Returns ModifierResult with base/effective values and operations.

## Orchestrator Request (Orchestrator)
Input bundle for orchestration containing BoundPackBundle, SelectionSnapshot, and OrchestratorOptions. Immutable input contract for OrchestratorService.buildViewBundle().

## Orchestrator Options (Orchestrator)
Configuration for orchestration output verbosity. Controls whether skipped operations and all diagnostics are included. Does not change evaluation semantics.

## View Bundle (Orchestrator)
Complete orchestrated output containing ViewSelections, EvaluationReport (M6), ApplicabilityResults (M7), ModifierResults (M8), and merged diagnostics. Deterministic: same inputs yield identical result. Selections ordered by snapshot.orderedSelections(). Diagnostic architecture uses structured separation: ViewBundle.diagnostics contains M6/M7/M8/Orchestrator diagnostics; M5 diagnostics accessible via boundBundle.diagnostics.

## View Selection (Orchestrator)
Computed view of single selection with all evaluations applied. Contains selectionId, entryId, boundEntry reference, appliedModifiers, applicabilityResults, effectiveValues map, and provenance. effectiveValues keyed by field name, sorted alphabetically for determinism.

## Orchestrator Diagnostic (Orchestrator)
Unified diagnostic wrapper with source module attribution (M6, M7, M8, or ORCHESTRATOR). Preserves original diagnostic codes unchanged. Orchestrator-specific codes: SELECTION_NOT_IN_BUNDLE, EVALUATION_ORDER_VIOLATION.

## Orchestrator Service (Orchestrator)
Coordinator service that calls M6/M7/M8 and produces ViewBundle. Single deterministic entrypoint. Evaluation order fixed: M6 → M7 → M8. Takes OrchestratorRequest, returns ViewBundle.

## Index Bundle (PROPOSED — M9 Index-Core)
Complete search index for a pack containing unit/weapon/rule documents with inverted index facets (byCharacteristicNameToken). Produced by M9 Index-Core (IndexService). Deterministic given same BoundPackBundle input (except indexedAt timestamp). All doc lists and lookups sorted by stable keys. **Proposed for M9 Index-Core; not yet approved.**

## Unit Doc (PROPOSED — M9 Index-Core)
Indexed document for a unit with characteristics as fields (not docs), keywords, and provenance. One UnitDoc per BoundEntry representing a unit/model with appropriate profile type. Contains key (entryId), name, characteristics (List<IndexedCharacteristic>), keywords, and references to weapons/rules. **Proposed for M9 Index-Core; not yet approved.**

## Weapon Doc (PROPOSED — M9 Index-Core)
Indexed document for a weapon with characteristics as fields (Range, Type, S, AP, D). One WeaponDoc per BoundProfile with weapon-type typeName. Contains key (profileId), name, characteristics (List<IndexedCharacteristic>), weapon type, ruleKeys, and provenance. **Proposed for M9 Index-Core; not yet approved.**

## Rule Doc (PROPOSED — M9 Index-Core)
Indexed document for a rule with name and description text. One RuleDoc per unique rule element, deduplicated by canonical key (first occurrence wins). Sources: BoundRule, ability profiles, weapon keywords. May have truncated description if source text exceeds 1000 chars. **Proposed for M9 Index-Core; not yet approved.**

## Indexed Characteristic (PROPOSED — M9 Index-Core)
Single characteristic name-value-token tuple as a **field** on UnitDoc/WeaponDoc (NOT a standalone doc). Fields: name, typeId, valueText, normalizedToken. Characteristics are fields to avoid scope trap (huge doc set, ambiguity, linking complexity). Use IndexBundle.byCharacteristicNameToken for characteristic-based queries. **Proposed for M9 Index-Core; not yet approved.**

## Index Diagnostic (PROPOSED — M9 Index-Core)
Non-fatal issue detected during M9 index building. Closed code set (7 codes): MISSING_NAME, DUPLICATE_DOC_KEY, DUPLICATE_RULE_CANONICAL_KEY, UNKNOWN_PROFILE_TYPE, EMPTY_CHARACTERISTICS, TRUNCATED_DESCRIPTION, LINK_TARGET_MISSING. Always accumulated; never thrown. Sorted by (sourceFileId, nodeIndex) for determinism. **Proposed for M9 Index-Core; not yet approved.**

## Index Service (PROPOSED — M9 Index-Core)
Service that builds search index from BoundPackBundle. Provides buildIndex() method returning IndexBundle. Takes M5 output only (no M6/M7/M8 dependence for v1). Implementation sequence: rules first (for linking), then weapons, then units. **Proposed for M9 Index-Core; not yet approved.**

---

## Tracked File (Phase 11B — GitHub Sync)
Tracked file entry in GitHub sync state. Stores both GitHub blob SHA (for update detection) and local storage metadata (localStoredPath, localFileId). Contains repoPath, fileType ('gst'/'cat'), rootId, blobSha, localStoredPath, localFileId, lastCheckedAt. Part of GitHubSyncState, not M1 engine metadata.

## Session Pack State (Phase 11B — GitHub Sync)
Session pack state tracking user's selected primary catalogs and their resolved dependencies. Contains selectedPrimaryRootIds (max 3), dependencyRootIds (auto-resolved closure), indexBuiltAt timestamp. Used for session persistence and update detection.

## Repo Sync State (Phase 11B — GitHub Sync)
Per-repository GitHub sync state. Contains repoUrl, branch, trackedFiles map (keyed by repoPath), lastTreeFetchAt. Part of GitHubSyncState.

## GitHub Sync State (Phase 11B — GitHub Sync)
Complete GitHub sync state across all repositories. Contains repos map (keyed by sourceKey) and sessionPack. Stored in `appDataRoot/github_sync_state.json`. This is UI-feature metadata, separate from M1 engine storage metadata.

## GitHub Sync State Service (Phase 11B — GitHub Sync)
Persistence service for GitHubSyncState. Provides loadState(), saveState(), updateRepoState(), updateTrackedFile(), updateSessionPack(), clearState(), getFilesNeedingUpdate() methods. File location: `appDataRoot/github_sync_state.json`.

## Multi-Pack Search Hit (Phase 11B — Multi-Catalog)
Extended search hit that includes source pack attribution. Wraps M10 SearchHit with sourcePackKey and sourcePackIndex for deterministic tie-breaking and deduplication during multi-bundle search.

## Multi-Pack Search Result (Phase 11B — Multi-Catalog)
Result of searching across multiple IndexBundles. Contains merged hits (deduplicated), merged diagnostics, resultLimitApplied flag, totalHitsBeforeLimit. Produced by MultiPackSearchService.

## Multi-Pack Search Service (Phase 11B — Multi-Catalog)
Stateless service for searching across multiple IndexBundles. Implements deterministic merge algorithm: run M10 per bundle → merge hits → stable sort (docType → canonicalKey → docId → sourcePackKey) → deduplicate by docId → apply limit → emit single resultLimitApplied diagnostic.

## Max Selected Catalogs (Phase 11B → 11C — Multi-Catalog)
Constant `kMaxSelectedCatalogs = 2`. Maximum number of user-selected primary catalogs. **Demo limitation: 2 primaries in initial release.** The per-slot architecture supports arbitrary N; this constant is intentionally low for testing. Dependencies (library catalogs) are auto-resolved and do NOT count toward this limit.

## Selected Catalogs (Phase 11B — Multi-Catalog)
List of user-selected primary catalog files in ImportSessionController. Max 2 per kMaxSelectedCatalogs (reduced from 3 in Phase 11C). Each runs M1-M9 pipeline independently, producing separate IndexBundle. Replaces deprecated single `primaryCatalogFile`.

## Slot Status (Phase 11C — Per-Slot Model)
Enum `SlotStatus` tracking per-slot lifecycle in ImportSessionController. Values: `empty` (no catalog assigned), `fetching` (downloading bytes from GitHub), `ready` (bytes in memory, pipeline not yet run), `building` (M2-M9 pipeline running), `loaded` (IndexBundle available for search), `error` (download or pipeline failed).

## Slot State (Phase 11C — Per-Slot Model)
Immutable data class `SlotState` carrying the full state of a single catalog slot. Fields: `status`, `catalogPath`, `catalogName`, `sourceLocator`, `fetchedBytes`, `errorMessage`, `missingTargetIds` (sorted, non-empty only on error), `indexBundle`. Produced by `assignCatalogToSlot()`, `loadSlot()`, `clearSlot()`. Exposed via `ImportSessionController.slotState(index)` and `.slots`.

## Update Check Status (Phase 11C — Update Detection)
Enum `UpdateCheckStatus` representing the result of the non-blocking update check. Values: `unknown` (check has not run, startup state), `upToDate` (check completed, no blob SHA differences found), `updatesAvailable` (check completed, at least one tracked file has changed SHA), `failed` (check could not complete — network error, no sync state, or no tracked repo). UI must not imply "up to date" when status is `unknown` or `failed`.

## Index Bundles (Phase 11B — Multi-Catalog)
Map of IndexBundle instances keyed by catalog identifier (rootId or index). Produced by running M1-M9 independently for each selected catalog. Used by SearchScreen and MultiPackSearchService for cross-bundle search.

## Repo Tree Entry (Phase 11B — BsdResolver Extension)
Single file entry from GitHub Trees API response. Contains path, blobSha, size. Used for building blob SHA mapping during fetchRepoTree().

## Repo Tree Result (Phase 11B — BsdResolver Extension)
Complete result of fetching GitHub repository tree. Contains entries list, pathToBlobSha map, targetIdToBlobSha map. Extends BsdResolverService capabilities for update detection.

## GitHub Catalog Picker View (Phase 11B — GitHub Import UI)
Widget replacing FilePickerView as the primary import entry point. Presents a GitHub URL field (prepopulated with BSData/wh40k-10e), fetches repository tree, auto-selects the .gst if exactly one exists, shows a .cat checkbox list (max 3 selectable), then triggers importFromGitHub(). Does not import HTTP or storage classes; delegates to controller only.

## fetchAndSetGameSystem (Phase 11C — ImportSessionController)
Controller method. Downloads a `.gst` file from GitHub via `fetchFileByPath()` and sets it as `gameSystemFile`. Returns `true` on success, `false` on failure (sets `resolverError`, transitions to `ImportStatus.failed`). On success, demotes any loaded/building/error slots that have fetched bytes back to `ready` so they can be re-run against the new game system.

## assignCatalogToSlot (Phase 11C — ImportSessionController)
Controller method. Assigns a catalog `.cat` path + locator to a slot and immediately fetches its bytes (fetch-on-select). Transitions: empty/error/ready → fetching → ready (on success) or error (on failure). Slot 0 and slot 1 are independent.

## loadSlot (Phase 11C — ImportSessionController)
Controller method. Runs the M2-M9 pipeline for a slot in `SlotStatus.ready`. Requires `gameSystemFile` to be set. On success: `SlotStatus.loaded` with `indexBundle`. On `AcquireFailure` with `missingTargetIds`: stores sorted missing list in `SlotState.missingTargetIds`, calls `_autoResolveSlotDeps()`. On other failure: `SlotStatus.error` with `errorMessage`.

## loadRepoCatalogTree (Phase 11B — ImportSessionController)
Controller method on ImportSessionController. Wraps _bsdResolver.fetchRepoTree() for view use. Returns RepoTreeResult? with .gst and .cat lists sorted lexicographically. Does not change ImportStatus; tree browsing is view-local state. Sets resolverError on failure. Idempotent: no duplicate fetch side effects.

## importFromGitHub (Phase 11B — ImportSessionController)
Controller method on ImportSessionController. Downloads selected .gst + .cat files (and auto-resolves dependencies) in one pass via fetchFileByPath(), then calls attemptBuild(). Enforces max 3 primary catalogs (kMaxSelectedCatalogs). Processes catalogs in deterministic order. On any download failure, sets ImportStatus.failed immediately with no partial state. Dependency failures transition to ImportStatus.resolvingDeps with missing list stable-sorted.

## fetchFileByPath (Phase 11B — BsdResolverService)
Public method on BsdResolverService. Returns raw Uint8List bytes for a repository file path. No storage side effects; does not write, cache, or log beyond setting lastError on failure. Delegates to internal _fetchFileContent(). Used by importFromGitHub() to download .gst and .cat files by path.

---

Any concept used in code must appear here first.

## Repo Search Query (PROPOSED — GitHub Repository Search)
Feature-level request object for GitHub repository search. Contains free text, sort/order, pageSize, mode, and fallback selector. Deterministic intent: same fields produce same request query and params.

## Repo Search Page (PROPOSED — GitHub Repository Search)
Paginated feature output containing normalized RepoSummary items, nextPageToken, isLastPage, optional totalCount, and diagnostics.

## Repo Summary (PROPOSED — GitHub Repository Search)
Normalized repository summary for UI consumption. Fields: fullName (owner/name canonical), htmlUrl, description (trimmed/null-safe), language, stargazersCount, forksCount, updatedAt.

## Repo Search Diagnostics (PROPOSED — GitHub Repository Search)
Per-response diagnostics for GitHub search requests, including statusCode and optional rate-limit/request metadata.

## Repo Search Error (PROPOSED — GitHub Repository Search)
Closed feature error set: unauthorized, rateLimited, forbidden, invalidQuery, networkFailure, invalidResponse, serverFailure.

## GitHub Query Builder (PROPOSED — GitHub Repository Search)
Deterministic query builder for GitHub repository search. Freezes canonical payloads and qualifier ordering rules.

## GitHub Repository Search Service (PROPOSED — GitHub Repository Search)
Feature service contract exposing `search({required RepoSearchQuery query, String? pageCursor})` for GitHub repository discovery.

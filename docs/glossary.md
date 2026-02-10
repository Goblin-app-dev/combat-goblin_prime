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
Exception thrown by M6 Evaluate only for corrupted M5 input or internal bugs. In normal operation, no EvaluateFailure is thrown. Semantic issues are reported via diagnostics instead. Parallels BindFailure/LinkFailure pattern.

## Evaluation Result
Top-level M6 output containing evaluated roster state with all rules and constraints processed. Preserves provenance chain (M6 → M5 → M4 → M3 → M2 → M1). Produced by M6 Evaluate.

## Rule Evaluation
Result of evaluating a single rule against roster state. Contains outcome (RuleEvaluationOutcome) and any violations detected.

## Rule Evaluation Outcome
Enum representing the result of a rule evaluation: PASSED, FAILED, SKIPPED (not applicable), ERROR (evaluation failed).

## Rule Violation
Specific violation of a rule. Contains violation details, severity, affected entities, and remediation hints.

## Constraint Evaluation
Result of evaluating a single constraint against roster state. Contains outcome (ConstraintEvaluationOutcome) and any violations detected.

## Constraint Evaluation Outcome
Enum representing the result of a constraint evaluation: SATISFIED, VIOLATED, NOT_APPLICABLE, ERROR.

## Constraint Violation
Specific violation of a constraint. Contains violation details, current value, required value, and affected entities.

## Evaluation Summary
Aggregate summary of all evaluations for a roster. Contains pass/fail counts, severity breakdown, and overall validity status.

## Evaluation Statistics
Quantitative metrics from evaluation: total rules evaluated, constraints checked, violations found, evaluation time, etc.

## Evaluation Notice
Informational message from evaluation that does not affect validity. Used for deprecation warnings, optimization hints, etc.

## Evaluation Warning
Non-fatal issue detected during evaluation that may affect roster validity but does not block processing.

## Evaluation Scope
Defines the boundary of what is being evaluated: full roster, specific selection, or subset. Controls evaluation depth and breadth.

## Evaluation Applicability
Determines whether a rule or constraint applies to a given context. Based on scope, conditions, and selection state.

## Evaluation Source Ref
Reference to the source definition (rule, constraint, modifier) that produced an evaluation result. Enables traceability from result to source.

## Evaluation Context
Runtime state available during evaluation: roster selections, active modifiers, resolved values, parent context.

---

Any concept used in code must appear here first.

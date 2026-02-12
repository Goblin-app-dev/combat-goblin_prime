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

## Modifier Value (M8 Modifiers — PROPOSED)
Type-safe variant wrapper for modifier values. Sealed class with subtypes: IntModifierValue, DoubleModifierValue, StringModifierValue, BoolModifierValue. Replaces `dynamic` with explicit type discrimination. **Proposed for M8 Modifiers; not yet approved.**

## Field Kind (M8 Modifiers — PROPOSED)
Enum disambiguating field namespace for modifier targets: `characteristic` (profile field), `cost` (cost type field), `constraint` (constraint value field), `metadata` (entry metadata). Resolves ambiguity when field strings could belong to multiple namespaces. **Proposed for M8 Modifiers; not yet approved.**

## Modifier Target Ref (M8 Modifiers — PROPOSED)
Reference to a modifier target with field namespace disambiguation. Contains targetId, field, fieldKind, optional scope, and provenance (sourceFileId, sourceNode). Combines targetId + field + fieldKind for unambiguous reference. **Proposed for M8 Modifiers; not yet approved.**

## Modifier Operation (M8 Modifiers — PROPOSED)
Single modifier operation with parsed data. Contains operationType (set, increment, decrement, append), target (ModifierTargetRef), value (ModifierValue), isApplicable flag (derived from M7), reasonSkipped, and provenance. Operations with isApplicable=false are recorded but not applied. **Proposed for M8 Modifiers; not yet approved.**

## Modifier Result (M8 Modifiers — PROPOSED)
M8 output containing base value, effective value, applied operations, skipped operations, diagnostics, and provenance. Deterministic: same inputs yield identical result. Operations applied in XML traversal order. Skipped operations preserved for transparency. **Proposed for M8 Modifiers; not yet approved.**

## Modifier Diagnostic (M8 Modifiers — PROPOSED)
Non-fatal issue during M8 Modifiers processing. Closed code set: UNKNOWN_MODIFIER_TYPE, UNKNOWN_MODIFIER_FIELD, UNKNOWN_MODIFIER_SCOPE, UNRESOLVED_MODIFIER_TARGET, INCOMPATIBLE_VALUE_TYPE, UNSUPPORTED_TARGET_KIND, UNSUPPORTED_TARGET_SCOPE. Always accumulated; never thrown. **Proposed for M8 Modifiers; not yet approved.**

## Modifier Failure (M8 Modifiers — PROPOSED)
Exception thrown by M8 Modifiers only for corrupted M5 input or internal bugs. In normal operation, no ModifierFailure is thrown. Unknown types/fields/scopes produce diagnostics and skip operations, not exceptions. **Proposed for M8 Modifiers; not yet approved.**

## Modifier Service (M8 Modifiers — PROPOSED)
Service that applies modifiers to produce effective values. Provides applyModifiers() for single-target and applyModifiersMany() for bulk application. Takes modifierSource node, BoundPackBundle, SelectionSnapshot, contextSelectionId, and ApplicabilityService. Returns ModifierResult with base/effective values and operations. **Proposed for M8 Modifiers; not yet approved.**

---

Any concept used in code must appear here first.

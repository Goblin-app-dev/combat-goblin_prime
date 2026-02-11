# Phase 4 — M6 Evaluate Design Proposal (Revised)

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **PROPOSAL** — revision 3, awaiting approval

---

## Revision History

| Rev | Date | Changes |
|-----|------|---------|
| 1 | 2026-02-10 | Initial proposal |
| 2 | 2026-02-10 | Addressed senior review: removed concrete roster types, fixed determinism, clarified boundaries |
| 3 | 2026-02-11 | Final review fixes: enforceable invariants, counting semantics, subtree traversal, emission ordering |

---

## Problem Statement

M5 Bind produces a BoundPackBundle containing:
- Typed entities (BoundEntry, BoundProfile, BoundCategory, BoundCost, BoundConstraint)
- Query surface for lookups
- Reference targets identified by M4/M5 where possible; unresolved remains diagnostic
- BindDiagnostics for semantic issues

M5 explicitly **stores but does NOT evaluate** constraints. Constraint evaluation requires roster state:
- "min 1" requires knowing how many units are selected
- "max 3" requires knowing current selection count
- Scope-based constraints require traversing the selection hierarchy

**M6 Evaluate** is a pure, deterministic evaluator that consumes:
- (A) A bound definition graph (BoundPackBundle from M5)
- (B) A minimal selection snapshot (roster state via contract, not concrete type)

And produces:
- (1) A stable evaluation report (strictly deterministic)
- (2) Optional runtime telemetry (non-deterministic, explicitly excluded from equality)

---

## Inputs

### Input A: BoundPackBundle (from M5 Bind)

Frozen M5 output. M6 reads but never modifies.

### Input B: Selection Snapshot Contract

M6 requires a roster snapshot that can answer specific operations. **The concrete roster model is NOT defined here** — that belongs to a separate module or downstream phase.

**SelectionSnapshot** is a **contract interface**, not a concrete type. It defines the operations M6 requires, but the implementation is outside M6 scope. Any type that satisfies this contract can be used.

**Required Operations (contract interface):**

| Operation | Returns | Purpose |
|-----------|---------|---------|
| `orderedSelections()` | Ordered list of selection instances | Root-first DFS traversal |
| `entryIdFor(selectionId)` | Entry ID | Map selection to bound entry |
| `parentOf(selectionId)` | Parent selection ID or null | Hierarchy traversal |
| `childrenOf(selectionId)` | Ordered list of child selection IDs | Subtree traversal |
| `countFor(selectionId)` | Integer count | How many of this entry selected |
| `isForceRoot(selectionId)` | Boolean | Force boundary detection |

**Why contract, not concrete types:**
- Keeps M6 isolated from UX and persistence decisions
- Prevents names drift when roster modeling changes
- Still deterministic if snapshot provides ordered children
- Follows names-first discipline (input names not approved in this phase)

**Determinism requirement:** The snapshot MUST provide children in a stable, deterministic order.

---

## Outputs

### Output Layer 1: EvaluationReport (Strictly Deterministic)

The primary output. Two evaluations of the same inputs MUST produce identical reports.

Contains:
- All boundary evaluations with outcomes
- All violations detected
- Summary counts
- Warnings and notices
- Reference to source BoundPackBundle
- Provenance chain preserved (M6 → M5 → M4 → M3 → M2 → M1)

### Output Layer 2: EvaluationTelemetry (Non-Deterministic, Excluded)

Optional instrumentation data. **Explicitly excluded from determinism contract.**

Contains:
- `evaluationDuration` — runtime measurement
- Memory usage (if tracked)
- Other performance metrics

**Rule:** EvaluationTelemetry MUST NOT be included in equality checks or determinism comparisons.

---

## Strict Non-Goals

M6 MUST NOT:

1. **No UI** — M6 produces data structures, not widgets or display logic
2. **No persistence** — M6 operates in-memory; storage remains in M1
3. **No network** — M6 is offline; network operations remain in M1
4. **No roster mutation** — M6 evaluates roster state; it does NOT modify it
5. **No modifier evaluation** — M6 evaluates constraints; modifier logic is separate (M7+)
6. **No condition evaluation** — Conditional constraints deferred (M7+)
7. **No list building** — M6 evaluates; army construction UX is downstream
8. **No cost calculation** — M6 reads costs; cost aggregation is separate
9. **No XML access** — M6 reads BoundPackBundle, never touches WrappedNode/XML
10. **No roster model definition** — M6 consumes a snapshot contract, not a concrete model

---

## Boundary Evaluation Model

### Core Concept: Evaluation Unit

The evaluation unit is:

**(constraint, boundary instance)**

This means the same constraint can legitimately produce multiple evaluations if there are multiple boundary instances.

### Scope Definitions (Mandatory)

| Scope | Boundary Instance | Definition |
|-------|-------------------|------------|
| `self` | Current selection instance | The single selection being evaluated |
| `parent` | Parent selection instance | `parentOf(selectionId)` — immediate parent |
| `force` | Force-root selection instance | Nearest ancestor where `isForceRoot(selectionId) == true` |
| `roster` | Roster-root boundary (single) | The entire snapshot — one boundary instance |

### Force Scope Handling

If `isForceRoot` cannot be determined from the snapshot (operation returns false for all):
- Emit warning: `UNDEFINED_FORCE_BOUNDARY`
- Set outcome: `notApplicable`
- Do NOT throw EvaluateFailure

### Multiplicity Rule (Mandatory)

**ConstraintEvaluation is emitted per (constraint, boundary instance).**

Example: If a constraint has scope=`self` and the user has 3 instances of the same entry in different parents:
- M6 produces 3 ConstraintEvaluation records (one per selection instance)
- Each has its own `affectedSelectionId`
- Each has its own `actualValue` (the count for that instance)

If you want aggregated evaluation, that is a different scope (e.g., `roster`).

---

## Precomputed Count Tables

### Concept

Instead of computing counts repeatedly during constraint traversal, M6 builds deterministic count tables in a single traversal pass.

### Algorithm

```
For each selection instance (in orderedSelections order):
  increment count in SELF boundary (this selection)
  increment count in PARENT boundary (if parent exists)
  increment count in FORCE boundary (if force root exists)
  increment count in ROSTER boundary
```

### Benefits

- **Speed:** O(1) lookup for any constraint evaluation
- **Determinism:** Tables built in single traversal order
- **Simplicity:** Constraint evaluation becomes pure comparison

### Deferred: Conditions and Modifiers

Condition and modifier logic would affect:
- Whether a selection is included in a count table
- What the `requiredValue` becomes after modification

These are explicitly deferred to M7+.

---

## Deterministic Evaluation Ordering (Mandatory)

### Traversal Order

1. **Selection traversal:** Root-first DFS following `childrenOf(selectionId)` in list order
2. **Constraint traversal:** Within a selection, constraints evaluated in stored order (as they appear in BoundEntry.constraints)
3. **Emission order:** Boundary evaluations emitted in traversal order

### Map Iteration Rule

**Never iterate a Map without sorting keys.**

If any map is used internally, keys MUST be sorted before iteration to ensure deterministic output.

### Warning/Notice Ordering

Warnings and notices are appended in **strict emission order** (simple list). No grouping or reordering. The order matches the order they were encountered during traversal.

---

## Constraint Evaluation Model

### Constraint Types

| Type | Meaning | Evaluation |
|------|---------|------------|
| `min` | Minimum count required | `actualCount >= value` → SATISFIED |
| `max` | Maximum count allowed | `actualCount <= value` → SATISFIED |

### Constraint Fields

| Field | What is counted |
|-------|----------------|
| `selections` | Number of this entry selected in boundary |
| `forces` | Number of force selections in boundary |

### Counting Semantics (Mandatory)

For `field=selections`, **actualValue counts only selections whose `entryId` equals the constrained entry's ID**, aggregated within the boundary instance.

Example: If a constraint on entry "E1" has scope=`parent`, actualValue is the count of selections with `entryId="E1"` under that parent boundary — NOT the total count of all selections under the parent.

### Evaluation Outcomes

```dart
enum ConstraintEvaluationOutcome {
  /// Constraint requirements are met.
  satisfied,

  /// Constraint requirements are NOT met.
  violated,

  /// Constraint does not apply in current context.
  notApplicable,

  /// Evaluation failed due to error (unknown type, etc).
  error,
}
```

---

## Core Types

### EvaluationReport
**File:** `models/evaluation_report.dart`

Strictly deterministic M6 output.

**Fields:**
- `String packId`
- `DateTime evaluatedAt` — derived from `boundBundle.boundAt` (deterministic)
- `List<ConstraintEvaluation> constraintEvaluations` — all boundary evaluations
- `EvaluationSummary summary` — aggregate counts
- `List<EvaluationWarning> warnings` — non-fatal issues
- `List<EvaluationNotice> notices` — informational messages
- `BoundPackBundle boundBundle` — reference to M5 input (immutable)

**Excluded from this type:** Any telemetry/timing data.

---

### EvaluationTelemetry
**File:** `models/evaluation_telemetry.dart`

Non-deterministic instrumentation data.

**Fields:**
- `Duration evaluationDuration` — runtime measurement

**Rule:** This type is explicitly excluded from equality/determinism checks. It is optional instrumentation only.

---

### ConstraintEvaluation
**File:** `models/constraint_evaluation.dart`

Result of evaluating a single (constraint, boundary instance) pair.

**Fields:**
- `String? constraintId` — ID of the BoundConstraint (if present)
- `ConstraintEvaluationOutcome outcome` — evaluation result
- `ConstraintViolation? violation` — details if violated
- `EvaluationScope scope` — boundary used for evaluation
- `String boundarySelectionId` — the selection instance defining the boundary
- `EvaluationSourceRef sourceRef` — reference to source constraint
- `int actualValue` — the computed value from count table
- `int requiredValue` — the constraint's required value
- `String constraintType` — min, max, etc.

---

### ConstraintEvaluationOutcome
**File:** `models/constraint_evaluation_outcome.dart`

Enum representing constraint evaluation result.

**Values:**
- `satisfied` — constraint requirements met
- `violated` — constraint requirements NOT met
- `notApplicable` — constraint does not apply in context
- `error` — evaluation failed (unknown type, etc.)

---

### ConstraintViolation
**File:** `models/constraint_violation.dart`

Details of a constraint violation.

**Fields:**
- `String constraintType` — min, max, etc.
- `int actualValue` — current count from boundary
- `int requiredValue` — constraint's required value
- `String affectedEntryId` — the entry with the violation
- `String boundarySelectionId` — the boundary instance
- `EvaluationScope scope` — boundary where violation occurred
- `String message` — human-readable violation description

---

### EvaluationSummary
**File:** `models/evaluation_summary.dart`

Aggregate summary of all evaluations.

**Fields:**
- `int totalEvaluations` — total boundary evaluations performed
- `int satisfiedCount` — evaluations that passed
- `int violatedCount` — evaluations that failed
- `int notApplicableCount` — evaluations that didn't apply
- `int errorCount` — evaluations that failed to evaluate
- `bool hasViolations` — true if violatedCount > 0

**Note on `hasViolations`:** This is a mechanical check (`violatedCount > 0`). It does NOT imply roster legality; only constraint violation presence. The name avoids "valid/invalid" judgment vocabulary.

---

### EvaluationWarning
**File:** `models/evaluation_warning.dart`

Non-fatal issue detected during evaluation.

**Fields:**
- `String code` — warning code
- `String message` — human-readable description
- `EvaluationSourceRef? sourceRef` — source of warning

**Warning Codes (closed set):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `UNKNOWN_CONSTRAINT_TYPE` | Constraint type not recognized | outcome = error |
| `UNKNOWN_CONSTRAINT_FIELD` | Constraint field not recognized | outcome = error |
| `UNKNOWN_CONSTRAINT_SCOPE` | Constraint scope not recognized | outcome = error |
| `UNDEFINED_FORCE_BOUNDARY` | Force scope requested but no force root found | outcome = notApplicable |
| `MISSING_ENTRY_REFERENCE` | Selection references entry not in bundle | Skip selection's constraints, still traverse children |

### Subtree Traversal on Missing Entry (Mandatory)

When a selection has `MISSING_ENTRY_REFERENCE`:
1. Emit warning
2. Skip constraint evaluation for that selection (no BoundEntry to evaluate)
3. **Still traverse children** — they may reference valid entries
4. Children are evaluated normally if their entries exist

This prevents partial corruption from hiding downstream evaluations.

---

### EvaluationNotice
**File:** `models/evaluation_notice.dart`

Informational message from evaluation.

**Fields:**
- `String code` — notice code
- `String message` — human-readable description
- `EvaluationSourceRef? sourceRef` — source of notice

**Notice Codes (closed set):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `CONSTRAINT_SKIPPED` | Constraint skipped (condition not met, deferred) | outcome = notApplicable |
| `EMPTY_SNAPSHOT` | Snapshot has no selections | No evaluations performed |

---

### EvaluationScope
**File:** `models/evaluation_scope.dart`

Defines the boundary of evaluation.

**Fields:**
- `String scopeType` — self, parent, force, roster
- `String? boundarySelectionId` — the selection defining the boundary (null for roster)

---

### EvaluationSourceRef
**File:** `models/evaluation_source_ref.dart`

Reference to source definition for traceability.

**Fields:**
- `String sourceFileId` — file containing source
- `String? entryId` — entry containing constraint
- `String? constraintId` — the constraint ID (if present)
- `NodeRef? sourceNode` — node reference for traceability

---

### EvaluateFailure
**File:** `models/evaluate_failure.dart`

Fatal exception for M6 failures.

**Fields:**
- `String message`
- `String? entryId`
- `String? details`

### EvaluateFailure Invariants (Enumerated)

EvaluateFailure is thrown ONLY for these specific invariant violations:

| Invariant | Condition |
|-----------|-----------|
| `NULL_PROVENANCE` | Required provenance pointers missing (boundBundle.linkedBundle, etc.) |
| `CYCLE_DETECTED` | Cycle in selection hierarchy (parentOf chain) |
| `INVALID_CHILDREN_TYPE` | childrenOf must return a List (not Set or other unordered type) |
| `DUPLICATE_CHILD_ID` | childrenOf contains duplicate selection IDs |
| `UNKNOWN_CHILD_ID` | childrenOf references a selection ID not in orderedSelections |
| `INTERNAL_ASSERTION` | M6 implementation bug (defensive checks) |

**Note:** All invariants are enforceable and testable at runtime.

**EvaluateFailure is NOT thrown for:**
- Unknown constraint types → warning, outcome = error
- Missing entry references → warning, skip selection
- Undefined force boundary → warning, outcome = notApplicable
- Any expected data gap from upstream

**In normal operation, no EvaluateFailure is thrown.**

---

## Reserved Types (M7+)

The following types were approved in vocabulary but are **reserved for future phases**:

| Type | Phase | Reason |
|------|-------|--------|
| `RuleEvaluation` | M7+ | Rule evaluation deferred |
| `RuleEvaluationOutcome` | M7+ | Rule evaluation deferred |
| `RuleViolation` | M7+ | Rule evaluation deferred |
| `EvaluationApplicability` | M7+ | Condition evaluation deferred |
| `EvaluationContext` | M7+ | Complex context deferred |

These names are reserved. M6 does NOT produce these types.

---

## Phase Isolation Rules (Mandatory)

### Terminology Isolation

M6 uses **warnings/notices**, NOT "diagnostics":

| Module | Terminology |
|--------|-------------|
| M5 Bind | BindDiagnostic |
| M6 Evaluate | EvaluationWarning, EvaluationNotice |

### Code Pattern Isolation

| Module | Code Patterns |
|--------|---------------|
| M5 Bind | `UNRESOLVED_*`, `SHADOWED_*`, `INVALID_*` |
| M6 Evaluate | `UNKNOWN_*`, `UNDEFINED_*`, `MISSING_*`, `CONSTRAINT_*`, `EMPTY_*` |

### Failure Type Isolation

| Module | Failure Type |
|--------|-------------|
| M4 Link | LinkFailure |
| M5 Bind | BindFailure |
| M6 Evaluate | EvaluateFailure |

---

## Module Layout

### Module
- Folder: `lib/modules/m6_evaluate/`
- Barrel: `lib/modules/m6_evaluate/m6_evaluate.dart`

### Public Exports (barrel only)
- `services/evaluate_service.dart`
- `models/evaluation_report.dart`
- `models/evaluation_telemetry.dart`
- `models/constraint_evaluation.dart`
- `models/constraint_evaluation_outcome.dart`
- `models/constraint_violation.dart`
- `models/evaluation_summary.dart`
- `models/evaluation_warning.dart`
- `models/evaluation_notice.dart`
- `models/evaluation_scope.dart`
- `models/evaluation_source_ref.dart`
- `models/evaluate_failure.dart`

### File Layout
```
lib/modules/m6_evaluate/
├── m6_evaluate.dart
├── models/
│   ├── evaluation_report.dart
│   ├── evaluation_telemetry.dart
│   ├── constraint_evaluation.dart
│   ├── constraint_evaluation_outcome.dart
│   ├── constraint_violation.dart
│   ├── evaluation_summary.dart
│   ├── evaluation_warning.dart
│   ├── evaluation_notice.dart
│   ├── evaluation_scope.dart
│   ├── evaluation_source_ref.dart
│   └── evaluate_failure.dart
└── services/
    └── evaluate_service.dart
```

---

## Services

### EvaluateService
**File:** `services/evaluate_service.dart`

**Method:**
```dart
/// Evaluates constraints against a selection snapshot.
///
/// Returns (EvaluationReport, EvaluationTelemetry?) where:
/// - EvaluationReport is strictly deterministic
/// - EvaluationTelemetry is optional, non-deterministic instrumentation
(EvaluationReport, EvaluationTelemetry?) evaluateConstraints({
  required BoundPackBundle boundBundle,
  required SelectionSnapshot snapshot,
})
```

**Algorithm:**
1. Validate invariants (throw EvaluateFailure if violated)
2. Build count tables in single traversal pass
3. For each selection in `snapshot.orderedSelections()`:
   a. Find corresponding BoundEntry via `snapshot.entryIdFor(selectionId)`
   b. For each constraint on the entry (in stored order):
      - Determine scope boundary
      - Lookup actualValue from count table
      - Compare against requiredValue
      - Emit ConstraintEvaluation
4. Build EvaluationSummary from all evaluations
5. Return (EvaluationReport, optional telemetry)

---

## Determinism Contract (Enforceable)

### Strict Guarantee

Same `BoundPackBundle` + same `SelectionSnapshot` → identical `EvaluationReport`

### What is Deterministic

- `evaluatedAt` timestamp (derived from `boundBundle.boundAt`)
- All `constraintEvaluations` (order and content)
- `summary` counts
- `warnings` and `notices` (order and content)

### What is NOT Deterministic (Explicitly Excluded)

- `EvaluationTelemetry.evaluationDuration`
- Any future instrumentation metrics

### Enforcement

`EvaluationTelemetry` is a separate type. It MUST NOT be included in:
- `EvaluationReport` fields
- Equality comparisons
- Hash code calculations
- Serialization for determinism tests

**Determinism tests compare only the deterministic report; telemetry is ignored.**

---

## Required Tests (when approved for implementation)

### Constraint Evaluation
- min constraint with count < value → violated
- min constraint with count >= value → satisfied
- max constraint with count > value → violated
- max constraint with count <= value → satisfied

### Boundary Evaluation (Multiplicity)
- Same entry selected 3 times with scope=self → 3 evaluations
- Scope=roster with multiple selections → 1 evaluation
- Scope=force with 2 force roots → 2 evaluations

### Scope Resolution
- self scope: counts only current selection
- parent scope: counts in parent boundary
- force scope: counts in force-root boundary
- roster scope: counts across all selections
- undefined force root → warning + notApplicable

### Summary Accuracy
- hasViolations == true when violatedCount > 0
- Counts match individual evaluations

### Warning Generation
- Unknown constraint type → UNKNOWN_CONSTRAINT_TYPE warning
- Missing entry reference → MISSING_ENTRY_REFERENCE warning
- Undefined force boundary → UNDEFINED_FORCE_BOUNDARY warning

### Determinism
- Evaluating same input twice yields identical EvaluationReport
- EvaluationTelemetry may differ (explicitly allowed)

### No-Failure Policy
- Unknown constraint type does NOT throw EvaluateFailure
- Missing entry reference does NOT throw EvaluateFailure
- Undefined force boundary does NOT throw EvaluateFailure

### EvaluateFailure Invariants
- Null provenance → EvaluateFailure with NULL_PROVENANCE
- Cycle in selection hierarchy → EvaluateFailure with CYCLE_DETECTED
- childrenOf returns Set instead of List → EvaluateFailure with INVALID_CHILDREN_TYPE
- Duplicate child ID in childrenOf → EvaluateFailure with DUPLICATE_CHILD_ID
- Unknown child ID in childrenOf → EvaluateFailure with UNKNOWN_CHILD_ID

---

## Resolved Questions

| Question | Resolution |
|----------|------------|
| Rule evaluation? | Deferred to M7. RuleEvaluation types reserved, not produced. |
| Condition evaluation? | Deferred to M7. Conditional constraints get outcome=notApplicable. |
| Modifier application? | Deferred to M7. M6 uses raw constraint values. |
| Roster model? | M6 defines contract (operations), not concrete types. |
| evaluationTime? | Moved to separate EvaluationTelemetry, excluded from determinism. |
| isValid naming? | Renamed to hasViolations, defined mechanically. |

---

## Approval Checklist

- [ ] Problem statement approved
- [ ] Input contract approved (snapshot operations, not concrete types)
- [ ] Output layering approved (deterministic report + optional telemetry)
- [ ] Non-goals approved
- [ ] Boundary evaluation model approved (constraint, boundary instance)
- [ ] Scope definitions approved (self, parent, force, roster)
- [ ] Multiplicity rule approved
- [ ] Precomputed count tables approved
- [ ] Deterministic ordering rules approved
- [ ] Core type names approved
- [ ] EvaluateFailure invariants approved (enumerated list)
- [ ] Phase isolation rules approved (warnings/notices, not diagnostics)
- [ ] Reserved types acknowledged (RuleEvaluation, etc. → M7)
- [ ] EvaluateService signature approved
- [ ] Determinism contract approved (telemetry excluded)
- [ ] Warning codes approved
- [ ] Notice codes approved
- [ ] Required tests approved

**NO CODE UNTIL APPROVAL.**

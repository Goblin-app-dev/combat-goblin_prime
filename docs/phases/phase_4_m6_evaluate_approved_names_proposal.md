# Phase 4 — M6 Evaluate Approved Names (Revised)

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **FROZEN** (2026-02-11)

---

## Revision History

| Rev | Date | Changes |
|-----|------|---------|
| 1 | 2026-02-10 | Initial proposal |
| 2 | 2026-02-10 | Addressed review: EvaluationResult→EvaluationReport, added EvaluationTelemetry, isValid→hasViolations, rule types reserved for M7 |
| 3 | 2026-02-11 | Final review: enforceable invariants, counting semantics, subtree traversal, emission ordering, SelectionSnapshot as contract interface |

---

## Purpose

M6 Evaluate is a pure, deterministic evaluator that consumes:
- (A) `BoundPackBundle` (from M5)
- (B) Selection snapshot (contract, not concrete type)

And produces:
- (1) `EvaluationReport` — strictly deterministic
- (2) `EvaluationTelemetry` — optional, non-deterministic instrumentation

**M6 evaluates constraints against roster state. M6 does NOT modify roster or bound data.**

---

## Scope Boundaries

### M6 MAY:
- Evaluate constraint elements against selection snapshot
- Compute actual values from snapshot (counts by boundary)
- Compare actual values against constraint requirements
- Determine constraint satisfaction/violation
- Emit warnings for unknown constraint types/fields/scopes
- Emit notices for skipped constraints or empty snapshots
- Provide evaluation summary

### M6 MUST NOT:
- Modify BoundPackBundle (read-only)
- Modify selection snapshot (read-only)
- Evaluate rules (deferred to M7)
- Evaluate conditions on constraints (deferred to M7)
- Apply modifiers to constraint values (deferred to M7)
- Define concrete roster model (contract only)
- Persist evaluation results (downstream concern)
- Produce UI elements (UI is downstream)
- Touch WrappedNode/XML (uses BoundPackBundle only)

---

## Module Layout

### Module
- Folder: `lib/modules/m6_evaluate/`
- Barrel: `lib/modules/m6_evaluate/m6_evaluate.dart`

### Public Exports (barrel only)
- `contracts/selection_snapshot.dart`
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
├── contracts/
│   └── selection_snapshot.dart
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

## Core Types (M6 Produces)

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

---

### EvaluationTelemetry
**File:** `models/evaluation_telemetry.dart`

Non-deterministic instrumentation data. **Excluded from determinism contract.**

**Fields:**
- `Duration evaluationDuration` — runtime measurement

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
- `bool hasViolations` — mechanical check: `violatedCount > 0`

**Note:** `hasViolations` does NOT imply roster legality; only constraint violation presence.

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
| `MISSING_ENTRY_REFERENCE` | Selection references entry not in bundle | Skip selection |

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

**EvaluateFailure Invariants (enumerated, all enforceable):**

| Invariant | Condition |
|-----------|-----------|
| `NULL_PROVENANCE` | Required provenance pointers missing |
| `CYCLE_DETECTED` | Cycle in selection hierarchy |
| `INVALID_CHILDREN_TYPE` | childrenOf must return a List (not Set) |
| `DUPLICATE_CHILD_ID` | childrenOf contains duplicate selection IDs |
| `UNKNOWN_CHILD_ID` | childrenOf references unknown selection ID |
| `INTERNAL_ASSERTION` | M6 implementation bug |

**In normal operation, no EvaluateFailure is thrown.**

---

## Reserved Types (M7+)

These names are approved but **reserved for future phases**:

| Type | Phase | Reason |
|------|-------|--------|
| `RuleEvaluation` | M7+ | Rule evaluation deferred |
| `RuleEvaluationOutcome` | M7+ | Rule evaluation deferred |
| `RuleViolation` | M7+ | Rule evaluation deferred |
| `EvaluationApplicability` | M7+ | Condition evaluation deferred |
| `EvaluationContext` | M7+ | Complex context deferred |

M6 does NOT produce these types.

---

## Services

### EvaluateService
**File:** `services/evaluate_service.dart`

**Method:**
```dart
(EvaluationReport, EvaluationTelemetry?) evaluateConstraints({
  required BoundPackBundle boundBundle,
  required SelectionSnapshot snapshot,
})
```

---

## Phase Isolation Rules (Mandatory)

### Terminology Isolation

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

## Determinism Contract

### Strict Guarantee

Same `BoundPackBundle` + same `SelectionSnapshot` → identical `EvaluationReport`

### Deterministic
- `evaluatedAt` (derived from `boundBundle.boundAt`)
- All `constraintEvaluations`
- `summary` counts
- `warnings` and `notices`

### NOT Deterministic (Excluded)
- `EvaluationTelemetry.evaluationDuration`

---

## Glossary Terms

Updated in `/docs/glossary.md` (2026-02-11):
- `EvaluationResult` → renamed to `EvaluationReport` ✓
- `EvaluationStatistics` → renamed to `EvaluationTelemetry` ✓
- `isValid` → renamed to `hasViolations` ✓
- Rule types marked as RESERVED for M7+ ✓
- Added `SelectionSnapshot` (contract interface) ✓
- Updated EvaluateFailure invariants ✓

---

## Approval Checklist

- [ ] Module layout approved
- [ ] Core model names approved (EvaluationReport, not EvaluationResult)
- [ ] EvaluationTelemetry separation approved
- [ ] Service signature approved (returns tuple)
- [ ] ConstraintEvaluationOutcome enum values approved
- [ ] Field definitions approved
- [ ] Warning codes approved
- [ ] Notice codes approved
- [ ] EvaluateFailure invariants approved
- [ ] Phase isolation rules approved
- [ ] Reserved types (M7) acknowledged
- [ ] Determinism contract approved
- [ ] Glossary updates identified

**NO CODE UNTIL APPROVAL.**

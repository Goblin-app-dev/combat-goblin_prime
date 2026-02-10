# Phase 4 — M6 Evaluate Approved Names

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **PROPOSAL** — awaiting approval

---

## Purpose

M6 Evaluate takes `BoundPackBundle` (from M5) and `RosterState` and produces an `EvaluationResult` containing:

- Evaluated constraints with outcomes (satisfied/violated)
- Violations with details (actual vs required values)
- Summary statistics (pass/fail counts)
- Evaluation diagnostics for non-fatal issues

**M6 evaluates constraints against roster state. M6 does NOT modify roster or bound data.**

---

## Scope Boundaries

### M6 MAY:
- Evaluate constraint elements against roster selections
- Compute actual values from roster state (counts, totals)
- Compare actual values against constraint requirements
- Determine constraint satisfaction/violation
- Emit warnings for unknown constraint types/fields/scopes
- Emit notices for skipped constraints or empty rosters
- Provide evaluation summary and statistics

### M6 MUST NOT:
- Modify BoundPackBundle (read-only)
- Modify RosterState (read-only)
- Evaluate rules (deferred to future phase)
- Evaluate conditions on constraints (deferred)
- Apply modifiers to constraint values (deferred)
- Persist evaluation results (downstream concern)
- Produce UI elements (UI is downstream)
- Touch WrappedNode/XML (uses BoundPackBundle only)

---

## Module Layout

### Module
- Folder: `lib/modules/m6_evaluate/`
- Barrel: `lib/modules/m6_evaluate/m6_evaluate.dart`

### Public Exports (barrel only)
- `services/evaluate_service.dart`
- `models/evaluation_result.dart`
- `models/constraint_evaluation.dart`
- `models/constraint_evaluation_outcome.dart`
- `models/constraint_violation.dart`
- `models/evaluation_summary.dart`
- `models/evaluation_statistics.dart`
- `models/evaluation_warning.dart`
- `models/evaluation_notice.dart`
- `models/evaluation_scope.dart`
- `models/evaluation_applicability.dart`
- `models/evaluation_source_ref.dart`
- `models/evaluation_context.dart`
- `models/evaluate_failure.dart`

### File Layout
```
lib/modules/m6_evaluate/
├── m6_evaluate.dart
├── models/
│   ├── evaluation_result.dart
│   ├── constraint_evaluation.dart
│   ├── constraint_evaluation_outcome.dart
│   ├── constraint_violation.dart
│   ├── evaluation_summary.dart
│   ├── evaluation_statistics.dart
│   ├── evaluation_warning.dart
│   ├── evaluation_notice.dart
│   ├── evaluation_scope.dart
│   ├── evaluation_applicability.dart
│   ├── evaluation_source_ref.dart
│   ├── evaluation_context.dart
│   └── evaluate_failure.dart
└── services/
    └── evaluate_service.dart
```

---

## Core Types

### EvaluationResult
**File:** `models/evaluation_result.dart`

Complete M6 output.

**Fields:**
- `String packId`
- `DateTime evaluatedAt` — derived from `boundBundle.boundAt` (deterministic)
- `List<ConstraintEvaluation> constraintEvaluations` — all evaluated constraints
- `EvaluationSummary summary` — aggregate pass/fail counts
- `EvaluationStatistics statistics` — quantitative metrics
- `List<EvaluationWarning> warnings` — non-fatal issues
- `BoundPackBundle boundBundle` — reference to M5 input (immutable)

**Rules:**
- Preserves provenance chain (M6 → M5 → M4 → M3 → M2 → M1)
- Does not modify bound entities or roster state

---

### ConstraintEvaluation
**File:** `models/constraint_evaluation.dart`

Result of evaluating a single constraint.

**Fields:**
- `String? constraintId` — ID of the BoundConstraint (if present)
- `ConstraintEvaluationOutcome outcome` — evaluation result
- `ConstraintViolation? violation` — details if violated
- `EvaluationScope scope` — boundary used for evaluation
- `EvaluationSourceRef sourceRef` — reference to source constraint
- `int actualValue` — the computed value from roster state
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
- `error` — evaluation failed

---

### ConstraintViolation
**File:** `models/constraint_violation.dart`

Details of a constraint violation.

**Fields:**
- `String constraintType` — min, max, etc.
- `int actualValue` — current count from roster
- `int requiredValue` — constraint's required value
- `String affectedEntryId` — the entry with the violation
- `String? affectedSelectionId` — the selection instance
- `EvaluationScope scope` — boundary where violation occurred
- `String message` — human-readable violation description

---

### EvaluationSummary
**File:** `models/evaluation_summary.dart`

Aggregate summary of all evaluations.

**Fields:**
- `int totalConstraints` — total constraints evaluated
- `int satisfiedCount` — constraints that passed
- `int violatedCount` — constraints that failed
- `int notApplicableCount` — constraints that didn't apply
- `int errorCount` — constraints that failed to evaluate
- `bool isValid` — true if violatedCount == 0

---

### EvaluationStatistics
**File:** `models/evaluation_statistics.dart`

Quantitative metrics from evaluation.

**Fields:**
- `int entriesEvaluated` — number of entries processed
- `int constraintsEvaluated` — number of constraints evaluated
- `int violationsFound` — total violations detected
- `Duration evaluationTime` — time taken to evaluate

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
| `CONSTRAINT_SKIPPED` | Constraint skipped due to condition | outcome = notApplicable |
| `EMPTY_ROSTER` | Roster has no selections | No constraints evaluated |

---

### EvaluationScope
**File:** `models/evaluation_scope.dart`

Defines the boundary of evaluation.

**Fields:**
- `String scopeType` — self, parent, force, roster
- `String? boundaryEntryId` — the entry defining the boundary
- `String? boundarySelectionId` — the selection defining the boundary

---

### EvaluationApplicability
**File:** `models/evaluation_applicability.dart`

Determines whether a constraint applies.

**Fields:**
- `bool applies` — whether constraint should be evaluated
- `String? reason` — why it doesn't apply (if applies == false)

---

### EvaluationSourceRef
**File:** `models/evaluation_source_ref.dart`

Reference to source definition.

**Fields:**
- `String sourceFileId` — file containing source
- `String? entryId` — entry containing constraint
- `String? constraintId` — the constraint ID (if present)
- `NodeRef? sourceNode` — node reference for traceability

---

### EvaluationContext
**File:** `models/evaluation_context.dart`

Runtime state during evaluation.

**Fields:**
- `String currentEntryId` — entry being evaluated
- `String? currentSelectionId` — selection being evaluated
- `Map<String, int> countsByScope` — precomputed counts per scope
- `List<String> ancestorEntryIds` — ancestor chain for scope resolution

---

### EvaluateFailure
**File:** `models/evaluate_failure.dart`

Fatal exception for M6 failures.

**Fields:**
- `String message`
- `String? entryId`
- `String? details`

**Fatality Policy:**

EvaluateFailure is thrown ONLY for:
1. Corrupted M5 input — BoundPackBundle violates frozen M5 contracts
2. Internal invariant violation — M6 implementation bug

EvaluateFailure is NOT thrown for:
- Unknown constraint types → warning, outcome = error
- Missing entry references → warning
- Evaluation failures → outcome = error

**In normal operation, no EvaluateFailure is thrown.**

---

## Services

### EvaluateService
**File:** `services/evaluate_service.dart`

**Method:**
```dart
Future<EvaluationResult> evaluateRoster({
  required BoundPackBundle boundBundle,
  required RosterState rosterState,
}) async
```

**Behavior:**
1. Validate inputs
2. Build evaluation context
3. For each selection in roster:
   - Find BoundEntry
   - Evaluate each constraint
   - Record outcome
4. Build summary and statistics
5. Return EvaluationResult

---

## Phase Isolation Rules (MANDATORY)

### Diagnostic Code Isolation

M6 diagnostic codes MUST NOT reuse M5 code patterns:

| Module | Code Patterns |
|--------|---------------|
| M5 Bind | `UNRESOLVED_*`, `SHADOWED_*`, `INVALID_*` |
| M6 Evaluate | `UNKNOWN_*`, `MISSING_*`, `CONSTRAINT_*`, `EMPTY_*` |

### Failure Type Isolation

| Module | Failure Type |
|--------|-------------|
| M4 Link | LinkFailure |
| M5 Bind | BindFailure |
| M6 Evaluate | EvaluateFailure |

---

## Determinism Contract

M6 guarantees:
- Same BoundPackBundle + same RosterState → identical EvaluationResult
- Evaluation order matches binding order → constraint order
- No dependence on runtime hash ordering

### evaluatedAt Determinism Rule (MANDATORY)

`evaluatedAt` must be derived from upstream immutable input.

**Required:** `evaluatedAt = boundBundle.boundAt`

**Forbidden:** `evaluatedAt = DateTime.now()`

---

## Required Tests

### Constraint Evaluation
- min constraint: count < value → violated
- min constraint: count >= value → satisfied
- max constraint: count > value → violated
- max constraint: count <= value → satisfied

### Summary Accuracy
- isValid == true when violatedCount == 0
- Counts match individual evaluations

### Warning Generation
- Unknown type → UNKNOWN_CONSTRAINT_TYPE warning

### Determinism
- Same input → identical output

### No-Failure Policy
- Unknown constraint type does NOT throw EvaluateFailure

---

## Glossary Terms

Already added to `/docs/glossary.md` (2026-02-10):
- Evaluate Failure
- Evaluation Result
- Rule Evaluation, Rule Evaluation Outcome, Rule Violation
- Constraint Evaluation, Constraint Evaluation Outcome, Constraint Violation
- Evaluation Summary, Evaluation Statistics
- Evaluation Notice, Evaluation Warning
- Evaluation Scope, Evaluation Applicability
- Evaluation Source Ref, Evaluation Context

---

## Approval Checklist

- [ ] Module layout approved
- [ ] Core model names approved
- [ ] Service name approved (EvaluateService)
- [ ] ConstraintEvaluationOutcome enum values approved
- [ ] Field definitions approved
- [ ] Warning codes approved
- [ ] Notice codes approved
- [ ] Fatality policy approved
- [ ] Phase isolation rules approved
- [ ] Determinism contract approved
- [ ] Glossary terms confirmed

**NO CODE UNTIL APPROVAL.**

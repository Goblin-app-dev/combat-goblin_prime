# Phase 4 — M6 Evaluate Design Proposal

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **PROPOSAL** — awaiting approval

---

## Problem Statement

M5 Bind produces a BoundPackBundle containing:
- Typed entities (BoundEntry, BoundProfile, BoundCategory, BoundCost, BoundConstraint)
- Query surface for lookups
- Resolved cross-file references
- BindDiagnostics for semantic issues

M5 explicitly **stores but does NOT evaluate** constraints. Constraint evaluation requires roster state:
- "min 1" requires knowing how many units are selected
- "max 3" requires knowing current selection count
- Scope-based constraints require traversing the selection hierarchy

**M6 Evaluate** takes a BoundPackBundle plus roster state and produces an EvaluationResult containing:
- Evaluated constraints with outcomes (satisfied/violated)
- Violations with details (current value vs required value)
- Summary statistics (pass/fail counts, severity breakdown)
- Evaluation diagnostics for non-fatal issues

---

## Inputs

- `BoundPackBundle` (from M5 Bind)
- `RosterState` — user's current selections and quantities

### RosterState Structure

RosterState represents the user's army/roster composition:

```dart
class RosterState {
  /// All selections in the roster, keyed by selection ID.
  final Map<String, RosterSelection> selections;

  /// The entry ID of the roster root (force/army).
  final String rootEntryId;

  /// Point limit for the roster (if applicable).
  final int? pointLimit;

  /// Timestamp when roster was created/modified.
  final DateTime modifiedAt;
}

class RosterSelection {
  /// Unique ID for this selection instance.
  final String selectionId;

  /// The bound entry this selection is based on.
  final String entryId;

  /// Number of this entry selected.
  final int count;

  /// Parent selection ID (null for root).
  final String? parentSelectionId;

  /// Child selections.
  final List<String> childSelectionIds;

  /// Selected category IDs for this selection.
  final List<String> categoryIds;
}
```

**Note:** RosterState is a proposed input structure. The exact shape may be refined during approval. M6 does not persist roster state; it evaluates a snapshot.

---

## Outputs

- `EvaluationResult` — complete M6 output containing:
  - All constraint evaluations with outcomes
  - All violations detected
  - Summary and statistics
  - Evaluation diagnostics for non-fatal issues
  - Reference to source BoundPackBundle
  - Provenance chain preserved (M6 → M5 → M4 → M3 → M2 → M1)

---

## Strict Non-Goals

M6 MUST NOT:

1. **No UI** — M6 produces data structures, not widgets or display logic
2. **No persistence** — M6 operates in-memory; storage remains in M1
3. **No network** — M6 is offline; network operations remain in M1
4. **No roster mutation** — M6 evaluates roster state; it does NOT modify it
5. **No modifier evaluation** — M6 evaluates constraints; modifier logic is separate (M7+)
6. **No list building** — M6 evaluates; army construction UX is downstream
7. **No cost calculation** — M6 reads costs; cost aggregation is separate
8. **No XML access** — M6 reads BoundPackBundle, never touches WrappedNode/XML

---

## Constraint Evaluation Model

### Constraint Types

BattleScribe constraints use these types:

| Type | Meaning | Evaluation |
|------|---------|------------|
| `min` | Minimum count required | `actualCount >= value` → SATISFIED |
| `max` | Maximum count allowed | `actualCount <= value` → SATISFIED |

### Constraint Fields

The `field` attribute specifies what is being counted:

| Field | What is counted |
|-------|----------------|
| `selections` | Number of this entry selected |
| `forces` | Number of force selections |

### Constraint Scope

The `scope` attribute defines the boundary for counting:

| Scope | Boundary |
|-------|----------|
| `self` | This entry only |
| `parent` | Parent entry |
| `force` | Containing force |
| `roster` | Entire roster |

### Evaluation Outcomes

```dart
enum ConstraintEvaluationOutcome {
  /// Constraint requirements are met.
  satisfied,

  /// Constraint requirements are NOT met.
  violated,

  /// Constraint does not apply in current context.
  notApplicable,

  /// Evaluation failed due to error.
  error,
}
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
- One-to-one correspondence with input BoundPackBundle + RosterState
- Does not modify bound entities or roster state
- Preserves provenance chain (M6 → M5 → M4 → M3 → M2 → M1)

---

### ConstraintEvaluation
**File:** `models/constraint_evaluation.dart`

Result of evaluating a single constraint.

**Fields:**
- `String constraintId` — ID of the BoundConstraint (if present)
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
- `String? affectedSelectionId` — the selection instance (if applicable)
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

**Warning Codes (initial set):**

| Code | Condition |
|------|-----------|
| `UNKNOWN_CONSTRAINT_TYPE` | Constraint type not recognized |
| `UNKNOWN_CONSTRAINT_FIELD` | Constraint field not recognized |
| `UNKNOWN_CONSTRAINT_SCOPE` | Constraint scope not recognized |
| `MISSING_ENTRY_REFERENCE` | Selection references entry not in bundle |

---

### EvaluationNotice
**File:** `models/evaluation_notice.dart`

Informational message from evaluation.

**Fields:**
- `String code` — notice code
- `String message` — human-readable description
- `EvaluationSourceRef? sourceRef` — source of notice

**Notice Codes (initial set):**

| Code | Condition |
|------|-----------|
| `CONSTRAINT_SKIPPED` | Constraint skipped due to condition |
| `EMPTY_ROSTER` | Roster has no selections to evaluate |

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
1. **Corrupted M5 input** — BoundPackBundle violates frozen M5 contracts
2. **Internal invariant violation** — M6 implementation bug

EvaluateFailure is NOT thrown for:
- Unknown constraint types → warning
- Missing entry references → warning
- Constraint evaluation errors → outcome = error

**In normal operation, no EvaluateFailure is thrown.**

---

## Phase Isolation Rules

### Diagnostic Code Isolation (MANDATORY)

M6 diagnostic codes (warnings, notices) MUST NOT reuse M5 diagnostic code names or meanings.

| Module | Diagnostic Pattern |
|--------|-------------------|
| M5 Bind | `UNRESOLVED_*`, `SHADOWED_*`, `INVALID_*` |
| M6 Evaluate | `UNKNOWN_*`, `MISSING_*`, `CONSTRAINT_*`, `EMPTY_*` |

### Failure Type Isolation (MANDATORY)

Each module has its own failure exception:

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
1. Validate inputs (throw EvaluateFailure if corrupted)
2. Build evaluation context with precomputed counts
3. For each selection in roster:
   a. Find corresponding BoundEntry
   b. For each constraint on the entry:
      - Determine scope boundary
      - Compute actual value from roster state
      - Compare against constraint value
      - Record ConstraintEvaluation with outcome
4. Build EvaluationSummary from all evaluations
5. Compute EvaluationStatistics
6. Return EvaluationResult

---

## Determinism Contract

M6 guarantees:
- Same BoundPackBundle + same RosterState → identical EvaluationResult
- Evaluation ordering matches entry binding order → constraint order
- No dependence on runtime hash ordering
- Warning/notice ordering is deterministic

### evaluatedAt Determinism Rule (MANDATORY)

`evaluatedAt` must be derived from upstream immutable input, never wall-clock time.

**Required:** `evaluatedAt = boundBundle.boundAt`

**Forbidden:** `evaluatedAt = DateTime.now()`

---

## Required Tests (when approved for implementation)

### Constraint Evaluation
- min constraint with count < value → violated
- min constraint with count >= value → satisfied
- max constraint with count > value → violated
- max constraint with count <= value → satisfied

### Scope Resolution
- self scope counts only current entry
- parent scope counts in parent context
- force scope counts across force
- roster scope counts across all selections

### Summary Accuracy
- isValid == true when violatedCount == 0
- Counts match individual evaluations

### Warning Generation
- Unknown constraint type → UNKNOWN_CONSTRAINT_TYPE warning
- Missing entry reference → MISSING_ENTRY_REFERENCE warning

### Determinism
- Evaluating same input twice yields identical output

### No-Failure Policy
- Unknown constraint type does NOT throw EvaluateFailure
- Missing entry reference does NOT throw EvaluateFailure

---

## Open Questions (require SME decision)

### Q1: Rule Evaluation

M5 deferred binding `rule` elements. Should M6 evaluate rules, or are rules deferred to a future phase?

**Options:**
- A: M6 evaluates rules (add RuleEvaluation, RuleViolation, etc.)
- B: Rules deferred to M7 (M6 focuses on constraints only)

**Recommendation:** Option B — keep M6 focused on constraints. Add rule evaluation in a future phase with explicit scope.

---

### Q2: Condition Evaluation

BattleScribe constraints can have conditions (e.g., "only apply if X is selected"). Should M6 evaluate conditions?

**Options:**
- A: M6 evaluates conditions (constraint skipped if condition false)
- B: M6 ignores conditions (evaluate all constraints regardless)
- C: M6 defers condition evaluation to M7+ (return notApplicable for conditional constraints)

**Recommendation:** Option C — conditions require complex evaluation logic. Defer to future phase.

---

### Q3: Modifier Application

Modifiers can change constraint values dynamically. Should M6 apply modifiers before evaluation?

**Options:**
- A: M6 applies modifiers (constraints evaluated with modified values)
- B: M6 uses raw constraint values (modifiers applied elsewhere)

**Recommendation:** Option B — modifier application is complex and deserves its own module.

---

## Glossary Additions Required (if approved)

Already added to `/docs/glossary.md`:
- **Evaluate Failure** — Fatal exception for M6 corruption
- **Evaluation Result** — Complete M6 output with evaluated roster state
- **Rule Evaluation** — Result of evaluating a single rule
- **Rule Evaluation Outcome** — Enum for rule result
- **Rule Violation** — Specific rule violation details
- **Constraint Evaluation** — Result of evaluating a single constraint
- **Constraint Evaluation Outcome** — Enum for constraint result
- **Constraint Violation** — Specific constraint violation details
- **Evaluation Summary** — Aggregate summary of evaluations
- **Evaluation Statistics** — Quantitative metrics from evaluation
- **Evaluation Notice** — Informational message
- **Evaluation Warning** — Non-fatal issue
- **Evaluation Scope** — Boundary of evaluation
- **Evaluation Applicability** — Whether rule/constraint applies
- **Evaluation Source Ref** — Reference to source definition
- **Evaluation Context** — Runtime state during evaluation

---

## Approval Checklist

- [ ] Problem statement approved
- [ ] Input/Output contract approved
- [ ] RosterState structure approved (or alternative proposed)
- [ ] Non-goals approved
- [ ] Constraint evaluation model approved (types, fields, scopes, outcomes)
- [ ] Core type names approved
- [ ] EvaluateFailure fatality policy approved
- [ ] Phase isolation rules approved (diagnostic codes, failure types)
- [ ] Module layout approved
- [ ] EvaluateService signature approved
- [ ] Determinism contract approved (evaluatedAt derivation)
- [ ] Warning codes approved
- [ ] Notice codes approved
- [ ] Open questions resolved (Q1: rules, Q2: conditions, Q3: modifiers)
- [ ] Required tests approved

**NO CODE UNTIL APPROVAL.**

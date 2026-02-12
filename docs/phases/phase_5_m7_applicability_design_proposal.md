# Phase 5 — M7 Applicability Design Proposal

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **FROZEN** (2026-02-11)
- Phase 5 (M7 Applicability): **PROPOSAL** — revision 1, awaiting approval

---

## Revision History

| Rev | Date | Changes |
|-----|------|---------|
| 1 | 2026-02-12 | Initial proposal |

---

## Problem Statement

M6 Evaluate currently evaluates ALL constraints on an entry, regardless of whether they apply to the current roster state. BSD data uses `<condition>` and `<conditionGroup>` elements to specify when constraints, modifiers, and rules should apply.

**Current behavior (M6):**
```
Constraint "max 1" → evaluated → violated/satisfied
```

**Desired behavior (M7):**
```
Constraint "max 1" with condition "if CHARACTER present"
  → condition NOT met → NOT_APPLICABLE (with reason)
  → condition MET → evaluated → violated/satisfied
```

This is critical for voice/search because:
- Users don't want to hear about constraints that don't apply
- "This limit doesn't apply because you don't have a CHARACTER" is more helpful than "limit violated"
- Reduces noise in evaluation reports

**M7 Applicability** evaluates conditions to determine whether constraints, modifiers, and other conditional elements apply to the current roster state.

---

## Inputs

### Input A: BoundPackBundle (from M5 Bind)
- Provides access to WrappedNodes via `linkedBundle.wrappedBundle`
- Used to traverse condition elements

### Input B: SelectionSnapshot (M6 contract)
- Provides roster state for condition evaluation
- Same contract M6 uses: orderedSelections(), entryIdFor(), countFor(), etc.

---

## Outputs

### Output: ApplicabilityResult

Result of evaluating whether a conditional element applies.

**Fields:**
- `bool applicable` — true if conditions are met (or no conditions present)
- `String? reason` — human-readable explanation when not applicable
- `List<ConditionEvaluation> conditionResults` — individual condition outcomes

**Usage:**
```dart
final result = applicabilityService.evaluate(
  conditionSource: constraintNode,
  snapshot: snapshot,
  boundBundle: boundBundle,
);

if (!result.applicable) {
  // Skip constraint evaluation, report as NOT_APPLICABLE
  print('Skipped: ${result.reason}');
}
```

---

## Core Types

### ConditionEvaluation

**File:** `models/condition_evaluation.dart`

Result of evaluating a single condition.

**Fields:**
- `String conditionType` — atLeast, atMost, greaterThan, instanceOf, etc.
- `String field` — selections, forces, costs
- `String scope` — self, roster, ancestor, force, etc.
- `String? childId` — entry ID being counted
- `int requiredValue` — threshold from condition
- `int actualValue` — computed value from roster
- `bool satisfied` — true if condition is met
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

---

### ConditionGroupEvaluation

**File:** `models/condition_group_evaluation.dart`

Result of evaluating a condition group (AND/OR).

**Fields:**
- `String groupType` — "and" or "or"
- `List<ConditionEvaluation> conditions` — individual condition results
- `List<ConditionGroupEvaluation> nestedGroups` — nested group results
- `bool satisfied` — true if group logic is satisfied

**Logic:**
- `type="and"` → all conditions AND nested groups must be satisfied
- `type="or"` → at least one condition OR nested group must be satisfied

---

### ApplicabilityResult

**File:** `models/applicability_result.dart`

Complete applicability evaluation result.

**Fields:**
- `bool applicable` — true if all conditions met (or no conditions)
- `String? reason` — explanation when not applicable
- `List<ConditionEvaluation> conditionResults` — leaf condition evaluations
- `ConditionGroupEvaluation? groupResult` — top-level group result (if conditions grouped)

**Determinism:**
- Results are deterministic given same inputs
- Reason text is constructed from condition data (not random)

---

### ApplicabilityDiagnostic

**File:** `models/applicability_diagnostic.dart`

Non-fatal issue during applicability evaluation.

**Fields:**
- `String code` — diagnostic code (closed set)
- `String message` — human-readable description
- `String sourceFileId` — file where issue occurred
- `NodeRef? sourceNode` — node where issue occurred
- `String? targetId` — the ID involved (if applicable)

**Diagnostic Codes (closed set):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `UNKNOWN_CONDITION_TYPE` | Condition type not recognized | Treat as NOT satisfied, continue |
| `UNKNOWN_SCOPE` | Scope value not recognized | Treat as NOT satisfied, continue |
| `UNKNOWN_FIELD` | Field value not recognized | Treat as NOT satisfied, continue |
| `UNRESOLVED_CHILD_ID` | childId not found in bundle | Treat as count=0, continue |

---

### ApplicabilityFailure

**File:** `models/applicability_failure.dart`

Fatal exception for M7 failures.

**Fields:**
- `String message`
- `String? fileId`
- `String? details`

**Fatality Policy:**

ApplicabilityFailure is thrown ONLY for:
1. Corrupted M5 input — BoundPackBundle violates frozen contracts
2. Internal invariant violation — M7 implementation bug

ApplicabilityFailure is NOT thrown for:
- Unknown condition types → diagnostic
- Unknown scopes → diagnostic
- Unresolved childIds → diagnostic

**In normal operation, no ApplicabilityFailure is thrown.**

---

## Condition Types (Closed Set)

BSData condition types supported:

| Type | Semantics | Example |
|------|-----------|---------|
| `atLeast` | actual >= required | "at least 1 CHARACTER" |
| `atMost` | actual <= required | "at most 3 selections" |
| `greaterThan` | actual > required | "more than 5 models" |
| `lessThan` | actual < required | "fewer than 10 points" |
| `equalTo` | actual == required | "exactly 2 units" |
| `notEqualTo` | actual != required | "not 0 selections" |
| `instanceOf` | entry is instance of type | "is a CHARACTER" |

**Unknown types:** Emit UNKNOWN_CONDITION_TYPE diagnostic, treat as NOT satisfied.

---

## Scope Resolution (Closed Set)

Condition scopes supported:

| Scope | Resolution | Count Source |
|-------|------------|--------------|
| `self` | Current selection | Entries matching childId under this selection |
| `parent` | Parent selection | Entries matching childId under parent |
| `ancestor` | Any ancestor selection | Walk up tree, count matching |
| `roster` | Entire roster | All selections matching childId |
| `force` | Current force | Selections in same force |
| `primary-category` | Selections with primary category | Filter by category |
| `primary-catalogue` | Selections from catalogue | Filter by catalogue |

**Unknown scopes:** Emit UNKNOWN_SCOPE diagnostic, treat as NOT satisfied.

---

## Field Resolution (Closed Set)

Condition fields supported:

| Field | Semantics |
|-------|-----------|
| `selections` | Count of selections matching criteria |
| `forces` | Count of forces matching criteria |

**Unknown fields:** Emit UNKNOWN_FIELD diagnostic, treat as NOT satisfied.

---

## Module Layout

### Module
- Folder: `lib/modules/m7_applicability/`
- Barrel: `lib/modules/m7_applicability/m7_applicability.dart`

### Public Exports (barrel only)
- `services/applicability_service.dart`
- `models/applicability_result.dart`
- `models/condition_evaluation.dart`
- `models/condition_group_evaluation.dart`
- `models/applicability_diagnostic.dart`
- `models/applicability_failure.dart`

### File Layout
```
lib/modules/m7_applicability/
├── m7_applicability.dart
├── models/
│   ├── applicability_result.dart
│   ├── condition_evaluation.dart
│   ├── condition_group_evaluation.dart
│   ├── applicability_diagnostic.dart
│   └── applicability_failure.dart
└── services/
    └── applicability_service.dart
```

---

## Services

### ApplicabilityService

**File:** `services/applicability_service.dart`

**Method:**
```dart
ApplicabilityResult evaluate({
  required WrappedNode conditionSource,
  required SelectionSnapshot snapshot,
  required BoundPackBundle boundBundle,
  required String contextSelectionId,
})
```

**Parameters:**
- `conditionSource` — Node containing conditions (modifier, constraint, etc.)
- `snapshot` — Current roster state
- `boundBundle` — For entry lookups
- `contextSelectionId` — "self" scope resolves relative to this selection

**Behavior:**
1. Find `<conditions>` or `<conditionGroups>` children of source node
2. If no conditions found → return `applicable: true`
3. Evaluate each condition against snapshot
4. Apply AND/OR logic for condition groups
5. Return ApplicabilityResult with all evaluations

**Determinism:**
- Same inputs → identical output
- No dependence on wall clock
- Condition order preserved from XML traversal

---

## Integration with M6 Evaluate

M7 does NOT modify M6. Instead, M7 provides a service M6 can optionally call.

**Current M6 flow:**
```
For each constraint:
  evaluate(constraint) → satisfied/violated
```

**Enhanced flow (M6 calls M7):**
```
For each constraint:
  applicability = M7.evaluate(constraint conditions)
  if not applicable:
    outcome = NOT_APPLICABLE (with reason)
  else:
    evaluate(constraint) → satisfied/violated
```

**Note:** This is an M6 enhancement, not an M7 responsibility. M7 provides the applicability service; M6 decides how to use it.

---

## Scope Boundaries

### M7 MAY:
- Parse condition and conditionGroup elements
- Evaluate condition logic against roster state
- Count selections matching criteria
- Apply AND/OR group logic
- Return applicability results with reasons
- Emit diagnostics for unknown types/scopes/fields

### M7 MUST NOT:
- Modify BoundPackBundle (read-only)
- Modify M6 behavior (separate service)
- Evaluate constraints (M6's job)
- Persist data
- Make network calls
- Produce UI elements
- Apply modifiers (M8+ concern)

---

## Phase Isolation Rules (Mandatory)

### Terminology Isolation

| Module | Terminology |
|--------|-------------|
| M5 Bind | BindDiagnostic |
| M6 Evaluate | EvaluationWarning, EvaluationNotice |
| M7 Applicability | ApplicabilityDiagnostic |

### Code Pattern Isolation

| Module | Code Patterns |
|--------|---------------|
| M5 Bind | `UNRESOLVED_ENTRY_LINK`, `SHADOWED_DEFINITION` |
| M6 Evaluate | `EMPTY_SNAPSHOT`, `UNKNOWN_SCOPE`, `UNKNOWN_FIELD` |
| M7 Applicability | `UNKNOWN_CONDITION_TYPE`, `UNKNOWN_SCOPE`, `UNKNOWN_FIELD`, `UNRESOLVED_CHILD_ID` |

### Failure Type Isolation

| Module | Failure Type |
|--------|-------------|
| M5 Bind | BindFailure |
| M6 Evaluate | EvaluateFailure |
| M7 Applicability | ApplicabilityFailure |

---

## Determinism Contract

M7 guarantees:
- Same inputs → identical ApplicabilityResult
- Condition evaluation order matches XML traversal
- Reason text is deterministic (constructed from condition data)
- No hash-map iteration leaks
- No wall-clock dependence

---

## Required Tests

### Structural Invariants (MANDATORY)
- Condition with `type="atLeast" value="1"` and count=0 → NOT satisfied
- Condition with `type="atLeast" value="1"` and count=1 → satisfied
- ConditionGroup `type="and"` with one false → group NOT satisfied
- ConditionGroup `type="or"` with one true → group satisfied
- No conditions → applicable=true

### Scope Resolution
- `scope="self"` counts only within context selection
- `scope="roster"` counts all selections
- `scope="ancestor"` walks up parent chain

### Diagnostic Invariants
- Unknown condition type → UNKNOWN_CONDITION_TYPE diagnostic
- Unknown scope → UNKNOWN_SCOPE diagnostic
- Unresolved childId → UNRESOLVED_CHILD_ID diagnostic

### Determinism
- Evaluating same conditions twice yields identical results

### No-Failure Policy
- Unknown types do not throw ApplicabilityFailure
- Missing entries do not throw ApplicabilityFailure

---

## Glossary Terms Required

Before implementation, add to `/docs/glossary.md`:

- **Applicability Result** — M7 output indicating whether conditions are met
- **Condition Evaluation** — Result of evaluating a single condition element
- **Condition Group Evaluation** — Result of evaluating an AND/OR condition group
- **Applicability Diagnostic** — Non-fatal issue during condition evaluation
- **Applicability Failure** — Fatal exception for M7 corruption
- **Applicability Service** — Service evaluating conditions against roster state

---

## Open Questions

### Q1: Should M7 handle modifier conditions?

Modifiers have nested conditions that determine when the modifier applies.

**Options:**
- A) M7 evaluates conditions for both constraints AND modifiers
- B) M7 only evaluates conditions; modifier application is M8

**Recommendation:** Option A — M7 is the condition evaluation service, agnostic to parent element type.

### Q2: Should M6 call M7 automatically?

**Options:**
- A) M6 calls M7 for every constraint (integrated)
- B) M6 continues as-is; caller can use M7 separately (decoupled)

**Recommendation:** Option B initially — maintain phase isolation. M6 can be enhanced later with controlled unfreeze.

### Q3: Condition inheritance?

Some conditions may reference entries that are defined at different levels.

**Decision:** Same resolution as M5 — use M4's ResolvedRefs and shadowing policy.

---

## Approval Checklist

- [ ] Module layout approved
- [ ] Core model names approved (ApplicabilityResult, ConditionEvaluation, ConditionGroupEvaluation, ApplicabilityDiagnostic, ApplicabilityFailure)
- [ ] Service name approved (ApplicabilityService)
- [ ] Condition types approved (atLeast, atMost, greaterThan, lessThan, equalTo, notEqualTo, instanceOf)
- [ ] Scope values approved (self, parent, ancestor, roster, force, primary-category, primary-catalogue)
- [ ] Field values approved (selections, forces)
- [ ] Diagnostic codes approved
- [ ] Determinism contract approved
- [ ] Phase isolation rules approved
- [ ] Glossary terms approved

**NO CODE UNTIL APPROVAL.**

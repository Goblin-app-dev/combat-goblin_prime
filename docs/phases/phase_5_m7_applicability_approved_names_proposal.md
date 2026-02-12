# Phase 5 — M7 Applicability Approved Names

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **FROZEN** (2026-02-11)
- Phase 5 (M7 Applicability): **PROPOSAL** — revision 1, awaiting approval

---

## Purpose

M7 Applicability evaluates `<condition>` and `<conditionGroup>` elements to determine whether constraints, modifiers, and other conditional elements apply to the current roster state.

**M7 evaluates conditions. M7 does NOT evaluate constraints (M6's job) or apply modifiers (M8+ concern).**

---

## Scope Boundaries

### M7 MAY:
- Parse condition and conditionGroup elements
- Evaluate condition logic against roster state
- Count selections matching criteria within specified scopes
- Apply AND/OR group logic for condition groups
- Return applicability results with human-readable reasons
- Emit diagnostics for unknown types/scopes/fields

### M7 MUST NOT:
- Modify BoundPackBundle (read-only)
- Modify M6 behavior (separate service)
- Evaluate constraints (M6's job)
- Apply modifiers (M8+ concern)
- Persist data (storage is M1's domain)
- Make network calls (network is M1's domain)
- Produce UI elements (UI is downstream)

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

## Core Types

### ApplicabilityResult
**File:** `models/applicability_result.dart`

Complete applicability evaluation result.

**Fields:**
- `bool applicable` — true if all conditions met (or no conditions)
- `String? reason` — human-readable explanation when not applicable
- `List<ConditionEvaluation> conditionResults` — leaf condition evaluations
- `ConditionGroupEvaluation? groupResult` — top-level group result (if conditions grouped)

**Rules:**
- Results are deterministic given same inputs
- Reason text is constructed from condition data (not random)
- No wall-clock dependence

---

### ConditionEvaluation
**File:** `models/condition_evaluation.dart`

Result of evaluating a single condition.

**Fields:**
- `String conditionType` — atLeast, atMost, greaterThan, lessThan, equalTo, notEqualTo, instanceOf
- `String field` — selections, forces
- `String scope` — self, parent, ancestor, roster, force, primary-category, primary-catalogue
- `String? childId` — entry ID being counted
- `int requiredValue` — threshold from condition
- `int actualValue` — computed value from roster
- `bool satisfied` — true if condition is met
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- Captures evaluation result for a single condition element
- actualValue computed via SelectionSnapshot queries
- satisfied determined by applying conditionType comparator

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

**Rules:**
- Diagnostics are accumulated, never thrown
- All diagnostics are non-fatal
- New diagnostic codes require doc + glossary update

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
1. Corrupted M5 input — BoundPackBundle violates frozen M5 contracts
2. Internal invariant violation — M7 implementation bug

ApplicabilityFailure is NOT thrown for:
- Unknown condition types → diagnostic
- Unknown scopes → diagnostic
- Unresolved childIds → diagnostic

**In normal operation, no ApplicabilityFailure is thrown.**

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

---

## Condition Types (Closed Set)

| Type | Semantics |
|------|-----------|
| `atLeast` | actual >= required |
| `atMost` | actual <= required |
| `greaterThan` | actual > required |
| `lessThan` | actual < required |
| `equalTo` | actual == required |
| `notEqualTo` | actual != required |
| `instanceOf` | entry is instance of type |

**Unknown types:** Emit UNKNOWN_CONDITION_TYPE diagnostic, treat as NOT satisfied.

---

## Scope Values (Closed Set)

| Scope | Resolution |
|-------|------------|
| `self` | Current selection |
| `parent` | Parent selection |
| `ancestor` | Any ancestor selection |
| `roster` | Entire roster |
| `force` | Current force |
| `primary-category` | Selections with primary category |
| `primary-catalogue` | Selections from catalogue |

**Unknown scopes:** Emit UNKNOWN_SCOPE diagnostic, treat as NOT satisfied.

---

## Field Values (Closed Set)

| Field | Semantics |
|-------|-----------|
| `selections` | Count of selections matching criteria |
| `forces` | Count of forces matching criteria |

**Unknown fields:** Emit UNKNOWN_FIELD diagnostic, treat as NOT satisfied.

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

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:

- **Applicability Result** — M7 output indicating whether conditions are met
- **Condition Evaluation** — Result of evaluating a single condition element
- **Condition Group Evaluation** — Result of evaluating an AND/OR condition group
- **Applicability Diagnostic** — Non-fatal issue during condition evaluation
- **Applicability Failure** — Fatal exception for M7 corruption
- **Applicability Service** — Service evaluating conditions against roster state

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
- [ ] Glossary terms approved

**NO CODE UNTIL APPROVAL.**

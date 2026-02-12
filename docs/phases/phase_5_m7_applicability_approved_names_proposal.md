# Phase 5 — M7 Applicability Approved Names (Rev 2)

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **FROZEN** (2026-02-11)
- Phase 5 (M7 Applicability): **PROPOSAL** — revision 2, awaiting approval

---

## Purpose

M7 Applicability evaluates `<condition>` and `<conditionGroup>` elements to determine whether constraints, modifiers, and other conditional elements apply to the current roster state.

**M7 evaluates conditions. M7 does NOT evaluate constraints (M6's job) or apply modifiers (M8+ concern).**

---

## Scope Boundaries

### M7 MAY:
- Parse condition and conditionGroup elements
- Evaluate condition logic against roster state (tri-state: applies/skipped/unknown)
- Count selections matching criteria within specified scopes
- Apply AND/OR group logic for condition groups (unknown-aware)
- Return applicability results with human-readable reasons
- Emit diagnostics for unknown types/scopes/fields
- Resolve field/scope as keyword OR id-like reference

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

### ApplicabilityState
**File:** `models/applicability_result.dart`

Tri-state enum for applicability outcomes.

```dart
enum ApplicabilityState { applies, skipped, unknown }
```

**Semantics:**
- `applies` — conditions true (or no conditions present)
- `skipped` — conditions evaluated false; constraint/modifier should not apply
- `unknown` — cannot determine; missing data, unsupported operator, unresolved reference

---

### ApplicabilityResult
**File:** `models/applicability_result.dart`

Complete applicability evaluation result.

**Fields:**
- `ApplicabilityState state` — final tri-state result
- `String? reason` — human-readable explanation (deterministic)
- `List<ConditionEvaluation> conditionResults` — leaf condition evaluations
- `ConditionGroupEvaluation? groupResult` — top-level group result (if conditions grouped)
- `String sourceFileId` — provenance (index-ready)
- `NodeRef sourceNode` — provenance (index-ready)
- `String? targetId` — optional referenced id

**Rules:**
- Results are deterministic given same inputs
- Reason text is constructed from condition data (not random)
- No wall-clock dependence

---

### ConditionEvaluation
**File:** `models/condition_evaluation.dart`

Result of evaluating a single condition.

**Fields:**
- `String conditionType` — atLeast, atMost, greaterThan, lessThan, equalTo, notEqualTo, instanceOf, notInstanceOf
- `String field` — keyword (selections, forces) OR id-like (costTypeId)
- `String scope` — keyword (self, parent, ancestor, roster, force) OR id-like (categoryId, entryId)
- `String? childId` — entry ID being counted
- `int requiredValue` — threshold from condition
- `int? actualValue` — computed value from roster (null if unknown)
- `ApplicabilityState state` — applies/skipped/unknown for this leaf
- `bool includeChildSelections` — whether to count subtree
- `bool includeChildForces` — whether to include nested forces
- `String? reasonCode` — diagnostic code when state is skipped/unknown
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- Captures evaluation result for a single condition element
- actualValue computed via SelectionSnapshot queries
- Unknown field/scope/type produces `state=unknown`, NOT skipped
- `actualValue == null` whenever `state == unknown`

---

### ConditionGroupEvaluation
**File:** `models/condition_group_evaluation.dart`

Result of evaluating a condition group (AND/OR).

**Fields:**
- `String groupType` — "and" or "or"
- `List<ConditionEvaluation> conditions` — individual condition results
- `List<ConditionGroupEvaluation> nestedGroups` — nested group results
- `ApplicabilityState state` — group outcome

**Logic (unknown-aware):**

**AND group:**
- If any child is `skipped` → group `skipped`
- Else if any child is `unknown` → group `unknown`
- Else → `applies`

**OR group:**
- If any child is `applies` → group `applies`
- Else if any child is `unknown` → group `unknown`
- Else → `skipped`

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
| `UNKNOWN_CONDITION_TYPE` | Condition type not recognized | Leaf state `unknown` |
| `UNKNOWN_CONDITION_SCOPE_KEYWORD` | Scope keyword not recognized | Leaf state `unknown` |
| `UNKNOWN_CONDITION_FIELD_KEYWORD` | Field keyword not recognized | Leaf state `unknown` |
| `UNRESOLVED_CONDITION_SCOPE_ID` | Scope is ID-like but not found | Leaf state `unknown` |
| `UNRESOLVED_CONDITION_FIELD_ID` | Field is ID-like but not found | Leaf state `unknown` |
| `UNRESOLVED_CHILD_ID` | childId not found in bundle | Leaf state `unknown` |
| `SNAPSHOT_DATA_GAP_COSTS` | Cost field requested but snapshot lacks cost data | Leaf state `unknown` |
| `SNAPSHOT_DATA_GAP_CHILD_SEMANTICS` | Cannot compute includeChildSelections distinction | Leaf state `unknown` |
| `SNAPSHOT_DATA_GAP_CATEGORIES` | Cannot resolve category-id scope | Leaf state `unknown` |
| `SNAPSHOT_DATA_GAP_FORCE_BOUNDARY` | Cannot determine force boundary | Leaf state `unknown` |

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
- Unknown condition types → diagnostic, state unknown
- Unknown scopes → diagnostic, state unknown
- Unresolved IDs → diagnostic, state unknown

**In normal operation, no ApplicabilityFailure is thrown.**

---

## Services

### ApplicabilityService
**File:** `services/applicability_service.dart`

**Method 1: evaluate (single-source)**
```dart
ApplicabilityResult evaluate({
  required WrappedNode conditionSource,
  required String sourceFileId,
  required NodeRef sourceNode,
  required SelectionSnapshot snapshot,
  required BoundPackBundle boundBundle,
  required String contextSelectionId,
})
```

**Parameters:**
- `conditionSource` — Node containing conditions (modifier, constraint, etc.)
- `sourceFileId` — Provenance for index-ready output
- `sourceNode` — Provenance for index-ready output
- `snapshot` — Current roster state
- `boundBundle` — For entry/category/costType lookups
- `contextSelectionId` — "self" scope resolves relative to this selection

**Method 2: evaluateMany (bulk-friendly)**
```dart
List<ApplicabilityResult> evaluateMany({
  required List<(WrappedNode conditionSource, String sourceFileId, NodeRef sourceNode)> sources,
  required SelectionSnapshot snapshot,
  required BoundPackBundle boundBundle,
  required String contextSelectionId,
})
```

**Purpose:**
- Deterministic bulk evaluation in one pass
- Results preserve input order
- Enables voice/search without separate index builder

**Behavior:**
1. Find `<conditions>` or `<conditionGroups>` children of source node
2. If no conditions found → return `state: applies`
3. Evaluate each condition against snapshot
4. Apply AND/OR logic for condition groups (unknown-aware)
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
| `notInstanceOf` | entry is NOT instance of type |

**Unknown types:** Emit `UNKNOWN_CONDITION_TYPE` diagnostic, leaf state `unknown`.

---

## Scope Values

**Keywords (minimum required):**

| Scope | Resolution |
|-------|------------|
| `self` | Current selection |
| `parent` | Parent selection |
| `ancestor` | Any ancestor selection |
| `roster` | Entire roster |
| `force` | Current force |

**ID-like scopes:**
- Category ID → evaluate within category boundary (if snapshot supports)
- Entry ID → deferred semantics (state `unknown` until documented)

**Unknown scopes:** Emit appropriate diagnostic, leaf state `unknown`.

---

## Field Values

**Keywords:**

| Field | Semantics |
|-------|-----------|
| `selections` | Count of selections matching criteria |
| `forces` | Count of forces matching criteria |

**ID-like fields:**
- Cost type ID → sum of cost values for that type (if snapshot supports)

**Unknown fields:** Emit appropriate diagnostic, leaf state `unknown`.

---

## Child Inclusion Semantics

**Attributes:**
- `includeChildSelections` — true: count subtree; false: count direct only
- `includeChildForces` — true: include nested forces; false: direct only

**If snapshot cannot compute distinction:** Leaf state `unknown` with `SNAPSHOT_DATA_GAP_CHILD_SEMANTICS`.

---

## Determinism Contract

M7 guarantees:
- Same inputs → identical ApplicabilityResult
- Condition evaluation order matches XML traversal
- Reason text is deterministic (constructed from condition data)
- `evaluateMany` preserves input order
- No hash-map iteration leaks
- No wall-clock dependence

---

## Required Tests

### Structural Invariants (MANDATORY)
- Condition with `type="atLeast" value="1"` and count=0 → state `skipped`
- Condition with `type="atLeast" value="1"` and count=1 → state `applies`
- `notInstanceOf` basic cases → correct state
- ConditionGroup `type="and"` with one skipped → group `skipped`
- ConditionGroup `type="and"` with one unknown, none skipped → group `unknown`
- ConditionGroup `type="or"` with one applies → group `applies`
- ConditionGroup `type="or"` with none applies, one unknown → group `unknown`
- No conditions → state `applies`

### Child Inclusion
- `includeChildSelections=true` → subtree counting
- `includeChildSelections=false` → direct-only counting
- Snapshot cannot support → state `unknown`

### ID Resolution
- Field is costTypeId, costs unavailable → state `unknown` + `SNAPSHOT_DATA_GAP_COSTS`
- Scope is categoryId, categories unavailable → state `unknown` + `SNAPSHOT_DATA_GAP_CATEGORIES`
- Unresolved childId → state `unknown` + `UNRESOLVED_CHILD_ID`

### Determinism
- Evaluating same conditions twice yields identical results
- `evaluateMany` preserves input order

### No-Failure Policy
- Unknown types do not throw ApplicabilityFailure
- Unresolved IDs do not throw ApplicabilityFailure

---

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:

- **Applicability State** — Tri-state enum: applies, skipped, unknown
- **Applicability Result** — M7 output with tri-state, reason, and evaluations
- **Condition Evaluation** — Result of evaluating a single condition element
- **Condition Group Evaluation** — Result of evaluating an AND/OR condition group
- **Applicability Diagnostic** — Non-fatal issue during condition evaluation
- **Applicability Failure** — Fatal exception for M7 corruption
- **Applicability Service** — Service evaluating conditions against roster state

---

## Approval Checklist

- [ ] Module layout approved
- [ ] Core model names approved (ApplicabilityState, ApplicabilityResult, ConditionEvaluation, ConditionGroupEvaluation, ApplicabilityDiagnostic, ApplicabilityFailure)
- [ ] Service name approved (ApplicabilityService)
- [ ] Service methods approved (evaluate, evaluateMany)
- [ ] Condition types approved (atLeast, atMost, greaterThan, lessThan, equalTo, notEqualTo, instanceOf, notInstanceOf)
- [ ] Scope values approved (self, parent, ancestor, roster, force + id-like)
- [ ] Field values approved (selections, forces + costTypeId)
- [ ] Child inclusion semantics approved (includeChildSelections, includeChildForces)
- [ ] Diagnostic codes approved (10 codes)
- [ ] Tri-state applicability approved
- [ ] Unknown-aware group logic approved
- [ ] Determinism contract approved
- [ ] Glossary terms approved

**NO CODE UNTIL APPROVAL.**

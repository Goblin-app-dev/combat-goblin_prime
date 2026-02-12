# Phase 5 — M7 Applicability Design Proposal (Rev 2)

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **FROZEN** (2026-02-11)
- Phase 5 (M7 Applicability): **FROZEN** (2026-02-12)

---

## Revision History

| Rev | Date | Changes |
|-----|------|---------|
| 1 | 2026-02-12 | Initial proposal |
| 2 | 2026-02-12 | Fixture-aligned condition coverage; tri-state applicability; child-inclusion semantics; ID-based field/scope resolution; unknown-aware group logic; index-ready identities; bulk-friendly API contract |
| 3 | 2026-02-12 | Implementation review fixes: (A) diagnostics attached per-result, (B) includeChildForces returns unknown, (C) field ID-like detection, (D) multiple groups combined as implicit AND, (E) deep hashCode, (F) scope ID-like detection |
| 3.1 | 2026-02-12 | Field resolution now uses actual cost type registry lookup from game system (replaces heuristic ID-like detection) |

---

## Problem Statement

M6 Evaluate evaluates constraints mechanically but does not determine whether constraints/modifiers/rules apply under BSD `<condition>` and `<conditionGroup>` gating.

This causes:
- Noisy evaluation output
- Incorrect user-facing explanations ("violated") when the constraint shouldn't apply
- Poor voice/search quality (missing "why")

**M7 Applicability** computes deterministic applicability for conditional elements against the current roster snapshot, producing truthful explanations:
- **Skipped:** conditions evaluated false (we know it doesn't apply)
- **Unknown:** conditions could not be evaluated (we don't know if it applies)

M7 is a standalone service. It does not modify frozen M6.

---

## Inputs

### Input A: BoundPackBundle (from M5 Bind)
- Read-only, frozen.
- Provides lookups (entries, categories, cost types where available).
- Provides provenance and access path to wrapped nodes (via linked bundle) when required to traverse condition XML structure.

### Input B: SelectionSnapshot (M6 contract)
- Read-only, deterministic snapshot operations.
- Provides stable traversal and scope context for condition evaluation (ordered selections, ancestry, children, counts, force boundary detection).

M7 does not define a roster model.

---

## Outputs

### Output: ApplicabilityResult (Tri-state)

Applicability is **not boolean**.

M7 distinguishes:
- **applies:** conditions true (or no conditions present)
- **skipped:** conditions false (constraint/modifier/rule should not apply)
- **unknown:** cannot determine (unsupported operator/scope/field, missing target, snapshot data gap)

ApplicabilityResult contains:
- The final tri-state applicability
- Deterministic reasons
- Leaf and group evaluation details
- Provenance identity (index-ready)

---

## Core Types

### ApplicabilityState

**File:** `models/applicability_result.dart` (or colocated enum file)

```dart
enum ApplicabilityState { applies, skipped, unknown }
```

---

### ConditionEvaluation

**File:** `models/condition_evaluation.dart`

Result of evaluating a single `<condition>` leaf.

**Fields:**
- `String conditionType` — atLeast, atMost, greaterThan, instanceOf, notInstanceOf, etc.
- `String field` — keyword (selections, forces) OR id-like (e.g., costTypeId)
- `String scope` — keyword OR id-like boundary reference (category/entry)
- `String? childId` — entry/category/other referenced id (when present)
- `int requiredValue` — threshold from condition
- `int? actualValue` — computed value; null if unknown
- `ApplicabilityState state` — applies/skipped/unknown for this leaf
- `bool includeChildSelections`
- `bool includeChildForces`
- `String? reasonCode` — set when state is skipped/unknown (closed set codes below)
- **Provenance:**
  - `String sourceFileId`
  - `NodeRef sourceNode`

**Rules:**
- Unknown field/scope/type/target must produce `state=unknown`, not "skipped".
- `actualValue == null` whenever `state == unknown`.

---

### ConditionGroupEvaluation

**File:** `models/condition_group_evaluation.dart`

Evaluates `<conditionGroup type="and|or">` with nested conditions and groups.

**Fields:**
- `String groupType` — "and" or "or"
- `List<ConditionEvaluation> conditions`
- `List<ConditionGroupEvaluation> nestedGroups`
- `ApplicabilityState state`

**Group logic (unknown-aware):**

**AND:**
- If any child is `skipped` → group `skipped`
- Else if any child is `unknown` → group `unknown`
- Else → `applies`

**OR:**
- If any child is `applies` → group `applies`
- Else if any child is `unknown` → group `unknown`
- Else → `skipped`

This prevents "unknown treated as false" errors.

---

### ApplicabilityResult

**File:** `models/applicability_result.dart`

Complete applicability evaluation for a given conditional source node and context.

**Fields:**
- `ApplicabilityState state`
- `String? reason` — deterministic explanation (non-judgmental)
- `List<ConditionEvaluation> conditionResults` — leaf results in XML traversal order
- `ConditionGroupEvaluation? groupResult` — top-level group (if present)
- `List<ApplicabilityDiagnostic> diagnostics` — attached per-result for voice/search context (Rev 3)
- **Provenance identity (index-ready):**
  - `String sourceFileId`
  - `NodeRef sourceNode`
  - `String? targetId` — optional referenced id (when applicable)

**Determinism:**
- Leaf ordering preserves XML traversal order.
- Reason text is deterministic (constructed from parsed condition data).
- Diagnostics attached to result, not mutable service state (Rev 3).

---

### ApplicabilityDiagnostic

**File:** `models/applicability_diagnostic.dart`

Non-fatal issues encountered during evaluation. Diagnostics do not collapse into "skipped".

**Fields:**
- `String code` — closed set
- `String message`
- `String sourceFileId`
- `NodeRef? sourceNode`
- `String? targetId`

---

### ApplicabilityFailure

**File:** `models/applicability_failure.dart`

Fatal exception for corruption/invariants.

**Thrown ONLY for:**
1. Corrupted M5 input (frozen contract violation)
2. Internal invariant failure in M7 implementation

**Not thrown for:** unknown type/scope/field/target.

---

## Condition Types (Fixture-aligned Closed Set)

Supported in Rev 2:

| Type | Semantics |
|------|-----------|
| `atLeast` | actual >= required |
| `atMost` | actual <= required |
| `greaterThan` | actual > required |
| `lessThan` | actual < required |
| `equalTo` | actual == required |
| `notEqualTo` | actual != required |
| `instanceOf` | membership/type test (as defined by BSD semantics) |
| `notInstanceOf` | negated membership/type test |

**Unknown types:**
- Emit diagnostic `UNKNOWN_CONDITION_TYPE`
- Leaf `state=unknown`

---

## Child Inclusion Semantics (BLOCKING, Rev 2)

Fixtures commonly use:
- `includeChildSelections="true|false"`
- `includeChildForces="true|false"`

Rev 2 requires these fields be parsed and applied.

**Normative semantics:**
- `includeChildSelections=true` → counts include subtree selections (DFS descendants)
- `includeChildSelections=false` → counts include direct-only children (immediate children) where applicable
- `includeChildForces=true` → force counts include nested force structures (if snapshot supports)

**If snapshot cannot compute these distinctions deterministically:**
- Leaf `state=unknown`
- `reasonCode=SNAPSHOT_DATA_GAP_CHILD_SEMANTICS` (or force equivalent)

---

## Field Resolution (Keyword OR ID)

Field can be:
- **keyword:** `selections`, `forces`
- **id-like:** cost type id (fixtures show this)

**Resolution:**
1. If field is `selections` or `forces` → keyword field
2. Else if field matches a known costTypeId in the bundle → cost field
   - If snapshot does not provide cost totals → leaf `unknown` with `SNAPSHOT_DATA_GAP_COSTS`
3. Else → leaf `unknown` with `UNRESOLVED_CONDITION_FIELD_ID`

**Note:** Unknown field is `unknown`, not "skipped".

---

## Scope Resolution (Keyword OR ID)

Scope can be:
- **keywords:** self, parent, ancestor, roster, force (minimum required)
- **id-like:** categoryId or entryId used as a boundary reference (fixtures show scope as an id)

**Resolution:**
1. If scope is a supported keyword → keyword scope
2. Else if scope matches a known category id in bundle:
   - Evaluate within that category boundary only if snapshot supports category membership deterministically
   - Otherwise leaf `unknown` with `SNAPSHOT_DATA_GAP_CATEGORIES`
3. Else if scope matches a known entry id in bundle:
   - Rev 2 does not invent semantics.
   - Only evaluate if an explicit operational meaning is documented and implementable via snapshot.
   - Otherwise leaf `unknown` with `SNAPSHOT_DATA_GAP_SCOPE_ENTRY_BOUNDARY` (or `UNRESOLVED_CONDITION_SCOPE_ID`)
4. Else → leaf `unknown` with `UNRESOLVED_CONDITION_SCOPE_ID`

---

## Diagnostics / Reason Codes (Closed Set)

M7 uses `ApplicabilityDiagnostic` for system issues, and `ConditionEvaluation.reasonCode` for leaf outcome explanations. Codes must not reuse M5/M6 codes.

**Diagnostic Codes:**
- `UNKNOWN_CONDITION_TYPE`
- `UNKNOWN_CONDITION_SCOPE_KEYWORD`
- `UNKNOWN_CONDITION_FIELD_KEYWORD`
- `UNRESOLVED_CONDITION_SCOPE_ID`
- `UNRESOLVED_CONDITION_FIELD_ID`
- `UNRESOLVED_CHILD_ID`
- `SNAPSHOT_DATA_GAP_COSTS`
- `SNAPSHOT_DATA_GAP_CHILD_SEMANTICS`
- `SNAPSHOT_DATA_GAP_CATEGORIES`
- `SNAPSHOT_DATA_GAP_FORCE_BOUNDARY`

(Exact final set approved during names gate.)

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

(No new file names introduced.)

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

**Notes:**
- `sourceFileId` + `sourceNode` are required to make the output index-ready and stable.
- `contextSelectionId` defines the evaluation anchor for `scope=self` and ancestry resolution.

**Method 2: evaluateMany (bulk-friendly contract)**
```dart
List<ApplicabilityResult> evaluateMany({
  required List<(WrappedNode conditionSource, String sourceFileId, NodeRef sourceNode)> sources,
  required SelectionSnapshot snapshot,
  required BoundPackBundle boundBundle,
  required String contextSelectionId,
})
```

**Purpose:**
- Enables deterministic bulk evaluation without requiring a separate "index builder" module yet.
- Allows voice/search to evaluate all relevant conditional elements in one deterministic pass.

**Determinism:**
- Results preserve the order of `sources` input.
- No unordered map iteration without sorted keys.

---

## Integration with M6 Evaluate

M7 does not modify M6.

Caller/orchestrator composes a voice/search view:
- If M7 state is `skipped`: present as "not applicable" with reason
- If M7 state is `unknown`: present as "cannot determine applicability" with reason + diagnostics
- If `applies`: present M6 outcome normally

This supports voice honesty without unfreezing M6.

---

## Scope Boundaries

### M7 MAY:
- Traverse condition/conditionGroup structures from wrapped nodes
- Evaluate condition truthiness against snapshot context
- Produce tri-state applicability results with provenance
- Emit diagnostics without failing

### M7 MUST NOT:
- Modify BoundPackBundle or snapshot
- Evaluate constraints (M6 responsibility)
- Apply modifiers (future phase)
- Persist data / network / UI

---

## Required Tests (Rev 2)

### Leaf Condition Semantics
- `atLeast` with actual < required → leaf `skipped`
- `atLeast` with actual >= required → leaf `applies`
- `notInstanceOf` basic cases → correct leaf state

### includeChild semantics
- With `includeChildSelections=true` → subtree counting changes outcome
- With `includeChildSelections=false` → direct-only counting changes outcome
- If snapshot cannot support → leaf `unknown` with `SNAPSHOT_DATA_GAP_CHILD_SEMANTICS`

### Group Logic with Unknowns
- AND group: one `skipped` → group `skipped`
- AND group: one `unknown` and none skipped → group `unknown`
- OR group: one `applies` → group `applies`
- OR group: none applies but one `unknown` → group `unknown`

### ID Resolution
- Field recognized as costTypeId:
  - If costs not available → `unknown` + `SNAPSHOT_DATA_GAP_COSTS`
- Scope recognized as category id:
  - If categories not available → `unknown` + `SNAPSHOT_DATA_GAP_CATEGORIES`
- Unresolved childId → `unknown` + `UNRESOLVED_CHILD_ID`

### Determinism
- Same inputs → identical ApplicabilityResult and diagnostics ordering
- `evaluateMany` preserves input order

### No-Failure Policy
- Unknown type/scope/field does not throw ApplicabilityFailure
- Unresolved ids do not throw ApplicabilityFailure

---

## Open Questions (Explicit)

### Q1: Entry-id scope operational semantics

If the project wants "entry-id scope" to mean "nearest ancestor with entryId defines boundary," this must be documented and added to snapshot contract if necessary. Otherwise remain `unknown`.

### Q2: Category membership in snapshot

If M7 is expected to resolve category-id scopes, snapshot must expose deterministic category membership for selection instances OR M7 must remain `unknown` for that path.

---

## Approval Checklist

- [ ] Tri-state applicability approved (ApplicabilityState)
- [ ] Condition types approved (+ notInstanceOf)
- [ ] includeChildSelections/includeChildForces semantics approved
- [ ] Field keyword + costTypeId resolution approved
- [ ] Scope keyword + id-like resolution policy approved
- [ ] Unknown-aware group logic approved
- [ ] Diagnostic codes approved (isolation preserved)
- [ ] Service signature updated with explicit source identity
- [ ] evaluateMany bulk-friendly contract approved
- [ ] Determinism contract approved
- [ ] Required tests approved

**NO CODE UNTIL APPROVAL.**

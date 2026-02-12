# Orchestrator v1 — Names-Only Proposal

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **FROZEN** (2026-02-11)
- Phase 5 (M7 Applicability): **FROZEN** (2026-02-12)
- Phase 6 (M8 Modifiers): **FROZEN** (2026-02-12)
- Orchestrator v1: **PROPOSED**

---

## Revision History

| Rev | Date | Changes |
|-----|------|---------|
| 1 | 2026-02-12 | Initial names-only proposal (coordinator pattern) |

---

## Purpose

Orchestrator is the **single deterministic entrypoint** that coordinates M6/M7/M8 evaluation to produce a unified ViewBundle. It takes frozen inputs (BoundPackBundle + SelectionSnapshot) and returns a complete view of the roster with all evaluations applied.

**Orchestrator coordinates. Orchestrator does NOT add semantics, interpret rules, or persist data.**

---

## Design Decision: Coordinator (Not Composer)

Orchestrator is a **coordinator**, not a pure composer:

| Aspect | Coordinator (chosen) | Pure Composer (rejected) |
|--------|---------------------|--------------------------|
| M6/M7/M8 calls | Internal | External (caller manages) |
| Sequencing | Owned by Orchestrator | Caller must know order |
| Single API | Yes, one call | No, four-call choreography |
| Future unfreeze risk | Low | High (convenience leaks) |

**Rationale:**
- Prevents "just one convenience" unfreeze trap
- Determinism easier to guarantee (one module owns ordering)
- UI/voice/search get single API: "give me the view bundle"

---

## Scope Boundaries

### Orchestrator MAY:
- Call M6 EvaluateService.evaluateConstraints()
- Call M7 ApplicabilityService.evaluate() / evaluateMany()
- Call M8 ModifierService.applyModifiers() / applyModifiersMany()
- Merge results into a unified ViewBundle
- Aggregate diagnostics from all modules
- Preserve provenance (raw Bound* references or stable IDs)

### Orchestrator MUST NOT:
- Add semantic interpretation (rules, meanings)
- Modify BoundPackBundle (read-only)
- Modify SelectionSnapshot (read-only)
- Persist data (storage is M1's domain)
- Make network calls (network is M1's domain)
- Produce UI elements (UI is downstream)
- Transform diagnostic codes (pass through unchanged)

---

## Module Layout

### Module
- Folder: `lib/modules/orchestrator/`
- Barrel: `lib/modules/orchestrator/orchestrator.dart`

### Public Exports (barrel only)
- `services/orchestrator_service.dart`
- `models/orchestrator_request.dart`
- `models/orchestrator_options.dart`
- `models/view_bundle.dart`
- `models/view_selection.dart`
- `models/orchestrator_diagnostic.dart`

### File Layout
```
lib/modules/orchestrator/
├── orchestrator.dart
├── models/
│   ├── orchestrator_request.dart
│   ├── orchestrator_options.dart
│   ├── view_bundle.dart
│   ├── view_selection.dart
│   └── orchestrator_diagnostic.dart
└── services/
    └── orchestrator_service.dart
```

---

## Core Types

### OrchestratorRequest
**File:** `models/orchestrator_request.dart`

Input bundle for orchestration.

**Fields:**
- `BoundPackBundle boundBundle` — M5 output (frozen, read-only)
- `SelectionSnapshot snapshot` — Current roster state (frozen format)
- `OrchestratorOptions options` — Configuration (optional features)

**Rules:**
- Immutable input contract
- All fields required (options may have defaults)

---

### OrchestratorOptions
**File:** `models/orchestrator_options.dart`

Configuration for orchestration behavior.

**Fields:**
- `bool includeSkippedOperations` — Include skipped modifier operations in output (default: true)
- `bool includeAllDiagnostics` — Include all diagnostics or filter by severity (default: true)

**Rules:**
- All options have sensible defaults
- Options do not change evaluation semantics, only output verbosity

---

### ViewBundle
**File:** `models/view_bundle.dart`

Complete orchestrated output containing all evaluation results.

**Fields:**
- `String packId` — From BoundPackBundle (identity)
- `DateTime evaluatedAt` — Timestamp of orchestration
- `List<ViewSelection> selections` — Computed views for each selection
- `EvaluationReport evaluationReport` — M6 constraint evaluations (preserved)
- `List<ApplicabilityResult> applicabilityResults` — M7 results (preserved)
- `List<ModifierResult> modifierResults` — M8 results (preserved)
- `List<OrchestratorDiagnostic> diagnostics` — Merged diagnostics from all modules
- `BoundPackBundle boundBundle` — Reference to input (for downstream lookups)

**Rules:**
- Deterministic: same inputs → identical ViewBundle
- Selections ordered by snapshot.orderedSelections()
- All M6/M7/M8 results preserved without transformation
- Diagnostics merged but codes unchanged

---

### ViewSelection
**File:** `models/view_selection.dart`

Computed view of a single selection with all evaluations applied.

**Fields:**
- `String selectionId` — Selection identity
- `String entryId` — Entry ID from snapshot
- `BoundEntry? boundEntry` — Reference to bound entry (for downstream)
- `List<ModifierResult> appliedModifiers` — Modifiers applied to this selection
- `List<ApplicabilityResult> applicabilityResults` — Conditions evaluated for this selection
- `Map<String, ModifierValue?> effectiveValues` — Computed values after modifiers
- `String sourceFileId` — Provenance
- `NodeRef sourceNode` — Provenance

**Rules:**
- effectiveValues keyed by field name
- null value means "unknown" or "not computed"
- Ordering deterministic (fields sorted alphabetically)

---

### OrchestratorDiagnostic
**File:** `models/orchestrator_diagnostic.dart`

Unified diagnostic from orchestration (wraps module diagnostics).

**Fields:**
- `String source` — Origin module: "M6", "M7", "M8", or "ORCHESTRATOR"
- `String code` — Original diagnostic code (unchanged)
- `String message` — Human-readable description
- `String sourceFileId` — File where issue occurred
- `NodeRef? sourceNode` — Node where issue occurred
- `String? targetId` — ID involved (if applicable)

**Orchestrator-specific codes:**

| Code | Condition | Behavior |
|------|-----------|----------|
| `SELECTION_NOT_IN_BUNDLE` | Selection references entry not in BoundPackBundle | Selection skipped, diagnostic emitted |
| `EVALUATION_ORDER_VIOLATION` | Internal ordering invariant violated | OrchestratorFailure thrown |

**Rules:**
- Module diagnostics preserved with original codes
- Orchestrator adds `source` field for traceability
- No transformation of diagnostic meanings

---

## Services

### OrchestratorService
**File:** `services/orchestrator_service.dart`

**Method: buildViewBundle**
```dart
ViewBundle buildViewBundle(OrchestratorRequest request)
```

**Parameters:**
- `request` — Contains BoundPackBundle, SelectionSnapshot, and OrchestratorOptions

**Returns:**
- `ViewBundle` — Complete orchestrated output

**Behavior:**
1. Validate inputs (check BoundPackBundle integrity)
2. Call M6 `evaluateConstraints()` with snapshot
3. For each selection in `snapshot.orderedSelections()`:
   a. Call M7 `evaluate()` for applicable conditions
   b. Call M8 `applyModifiers()` for applicable modifiers
   c. Build `ViewSelection` with computed values
4. Aggregate all results into `ViewBundle`
5. Merge diagnostics from M6/M7/M8

**Determinism Contract:**
- Same inputs → identical ViewBundle
- Evaluation order: M6 → M7 → M8 (fixed)
- Selection processing order: snapshot.orderedSelections() (stable)
- No hash-map iteration leaks
- No wall-clock dependence (except evaluatedAt timestamp)

---

## Error Handling

### OrchestratorFailure
Fatal exception thrown ONLY for:
1. Corrupted M5 input — BoundPackBundle violates frozen contracts
2. Internal invariant violation — Orchestrator implementation bug
3. Evaluation order violation — M6/M7/M8 returned inconsistent state

**In normal operation, no OrchestratorFailure is thrown.**

Unknown selections, missing entries, and evaluation errors produce diagnostics, not exceptions.

---

## Determinism Contract

Orchestrator guarantees:
- Same `OrchestratorRequest` → identical `ViewBundle`
- Evaluation order: M6 → M7 → M8 (never changes)
- Selection order: matches `snapshot.orderedSelections()` exactly
- Diagnostic order: M6 diagnostics, then M7, then M8, then Orchestrator
- No hash-map iteration leaks (all maps sorted before output)
- `evaluatedAt` is the only non-deterministic field (wall-clock)

---

## Required Tests

### Structural Invariants (MANDATORY)
- buildViewBundle returns ViewBundle with correct packId
- selections count matches snapshot.orderedSelections() count
- evaluationReport is preserved from M6
- applicabilityResults are preserved from M7
- modifierResults are preserved from M8

### Determinism
- Calling buildViewBundle twice with same input yields equal output (except evaluatedAt)
- Selection order matches snapshot.orderedSelections()

### Diagnostic Aggregation
- M6 diagnostics appear in ViewBundle.diagnostics with source="M6"
- M7 diagnostics appear with source="M7"
- M8 diagnostics appear with source="M8"
- Diagnostic codes are not transformed

### Error Cases
- Selection referencing non-existent entry → SELECTION_NOT_IN_BUNDLE diagnostic, selection skipped
- Empty snapshot → ViewBundle with empty selections (not an error)

---

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:

- **Orchestrator Request** — Input bundle for orchestration (BoundPackBundle + SelectionSnapshot + options)
- **Orchestrator Options** — Configuration for orchestration output verbosity
- **View Bundle** — Complete orchestrated output with all M6/M7/M8 results
- **View Selection** — Computed view of single selection with effective values
- **Orchestrator Diagnostic** — Unified diagnostic wrapper with source module attribution
- **Orchestrator Service** — Coordinator service that calls M6/M7/M8 and produces ViewBundle

---

## Approval Checklist

- [ ] Module layout approved (lib/modules/orchestrator/)
- [ ] Core model names approved (OrchestratorRequest, OrchestratorOptions, ViewBundle, ViewSelection, OrchestratorDiagnostic)
- [ ] Service name approved (OrchestratorService)
- [ ] Service method approved (buildViewBundle)
- [ ] Coordinator pattern approved (internal M6/M7/M8 calls)
- [ ] Determinism contract approved
- [ ] Diagnostic aggregation rules approved
- [ ] Glossary terms approved

**NO CODE UNTIL APPROVAL.**

# Phase 6 — M8 Modifiers Names-Only Proposal (Rev 2)

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **FROZEN** (2026-02-11)
- Phase 5 (M7 Applicability): **FROZEN** (2026-02-12)
- Phase 6 (M8 Modifiers): **FROZEN** (2026-02-12)

---

## Revision History

| Rev | Date | Changes |
|-----|------|---------|
| 1 | 2026-02-12 | Initial names-only proposal |
| 2 | 2026-02-12 | ModifierValue type-safe wrapper; ModifierTargetRef with FieldKind disambiguation; UNSUPPORTED_TARGET_SCOPE diagnostic |
| 3 | 2026-02-12 | FROZEN after implementation and test verification (18/18 tests pass) |

---

## Purpose

M8 applies modifier operations to produce effective values for entry characteristics, costs, constraints, and other modifiable fields.

**M8 applies modifiers. M8 does NOT evaluate constraints (M6's job) or evaluate conditions (M7's job).**

---

## Scope Boundaries

### M8 MAY:
- Parse modifier elements from condition sources
- Apply modifier operations (set, increment, decrement, append, etc.)
- Resolve modifier targets (characteristics, costs, constraints, metadata)
- Produce effective values after modifier application
- Return ModifierResult with applied operations and provenance
- Emit diagnostics for unknown types/scopes/targets
- Use M7 ApplicabilityResult to filter applicable modifiers

### M8 MUST NOT:
- Modify BoundPackBundle (read-only)
- Evaluate constraints (M6's job)
- Evaluate conditions (M7's job)
- Persist data (storage is M1's domain)
- Make network calls (network is M1's domain)
- Produce UI elements (UI is downstream)

---

## Module Layout

### Module
- Folder: `lib/modules/m8_modifiers/`
- Barrel: `lib/modules/m8_modifiers/m8_modifiers.dart`

### Public Exports (barrel only)
- `services/modifier_service.dart`
- `models/modifier_result.dart`
- `models/modifier_operation.dart`
- `models/modifier_target_ref.dart`
- `models/modifier_value.dart`
- `models/modifier_diagnostic.dart`
- `models/modifier_failure.dart`

### File Layout
```
lib/modules/m8_modifiers/
├── m8_modifiers.dart
├── models/
│   ├── modifier_result.dart
│   ├── modifier_operation.dart
│   ├── modifier_target_ref.dart
│   ├── modifier_value.dart
│   ├── modifier_diagnostic.dart
│   └── modifier_failure.dart
└── services/
    └── modifier_service.dart
```

---

## Core Types

### ModifierValue
**File:** `models/modifier_value.dart`

Type-safe variant wrapper for modifier values. Replaces `dynamic` with explicit type discrimination.

```dart
sealed class ModifierValue {
  const ModifierValue();
}

class IntModifierValue extends ModifierValue {
  final int value;
  const IntModifierValue(this.value);
}

class DoubleModifierValue extends ModifierValue {
  final double value;
  const DoubleModifierValue(this.value);
}

class StringModifierValue extends ModifierValue {
  final String value;
  const StringModifierValue(this.value);
}

class BoolModifierValue extends ModifierValue {
  final bool value;
  const BoolModifierValue(this.value);
}
```

**Rules:**
- All modifier values wrapped in appropriate subtype
- No `dynamic` or `Object` in modifier signatures
- Type safety enforced at compile time

---

### FieldKind
**File:** `models/modifier_target_ref.dart`

Disambiguates field namespace for modifier targets.

```dart
enum FieldKind {
  characteristic,  // Profile characteristic field
  cost,            // Cost type field
  constraint,      // Constraint value field
  metadata,        // Entry metadata (name, hidden, etc.)
}
```

**Purpose:**
- Field strings can be ambiguous (e.g., "value" could be cost or constraint)
- FieldKind resolves ambiguity at resolution time
- Unknown field kind → diagnostic, not exception

---

### ModifierTargetRef
**File:** `models/modifier_target_ref.dart`

Reference to a modifier target with field namespace disambiguation.

**Fields:**
- `String targetId` — ID of target entry/profile/cost
- `String field` — field name being modified
- `FieldKind fieldKind` — namespace disambiguation
- `String? scope` — optional scope restriction
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- Combines targetId + field + fieldKind for unambiguous reference
- Unknown scope → state unknown (not exception)

---

### ModifierOperation
**File:** `models/modifier_operation.dart`

Single modifier operation with parsed data.

**Fields:**
- `String operationType` — set, increment, decrement, append, etc.
- `ModifierTargetRef target` — what is being modified
- `ModifierValue value` — the modifier value
- `bool isApplicable` — derived from M7 applicability (true if applies)
- `String? reasonSkipped` — if not applicable, why
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- `isApplicable` determined by M7 (if condition evaluated)
- Operations with `isApplicable=false` are recorded but not applied

---

### ModifierResult
**File:** `models/modifier_result.dart`

Complete result of modifier application for a target.

**Fields:**
- `ModifierTargetRef target` — what was modified
- `ModifierValue? baseValue` — value before modifiers
- `ModifierValue? effectiveValue` — value after modifiers
- `List<ModifierOperation> appliedOperations` — operations that were applied
- `List<ModifierOperation> skippedOperations` — operations skipped (not applicable)
- `List<ModifierDiagnostic> diagnostics` — issues encountered
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- Deterministic: same inputs → identical result
- Operations applied in XML traversal order
- Skipped operations preserved for transparency

---

### ModifierDiagnostic
**File:** `models/modifier_diagnostic.dart`

Non-fatal issue during modifier processing.

**Fields:**
- `String code` — diagnostic code (closed set)
- `String message` — human-readable description
- `String sourceFileId` — file where issue occurred
- `NodeRef? sourceNode` — node where issue occurred
- `String? targetId` — the ID involved (if applicable)

**Diagnostic Codes (closed set):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `UNKNOWN_MODIFIER_TYPE` | Modifier type not recognized | Operation skipped |
| `UNKNOWN_MODIFIER_FIELD` | Field not recognized | Operation skipped |
| `UNKNOWN_MODIFIER_SCOPE` | Scope keyword not recognized | Operation skipped |
| `UNRESOLVED_MODIFIER_TARGET` | Target ID not found in bundle | Operation skipped |
| `INCOMPATIBLE_VALUE_TYPE` | Value type incompatible with field | Operation skipped |
| `UNSUPPORTED_TARGET_KIND` | Target kind not supported for this operation | Operation skipped |
| `UNSUPPORTED_TARGET_SCOPE` | Scope not supported for this target kind | Operation skipped |

**Rules:**
- Diagnostics are accumulated, never thrown
- All diagnostics are non-fatal
- New diagnostic codes require doc + glossary update

---

### ModifierFailure
**File:** `models/modifier_failure.dart`

Fatal exception for M8 failures.

**Fields:**
- `String message`
- `String? fileId`
- `String? details`

**Fatality Policy:**

ModifierFailure is thrown ONLY for:
1. Corrupted M5 input — BoundPackBundle violates frozen M5 contracts
2. Internal invariant violation — M8 implementation bug

ModifierFailure is NOT thrown for:
- Unknown modifier types → diagnostic, operation skipped
- Unknown fields/scopes → diagnostic, operation skipped
- Unresolved targets → diagnostic, operation skipped

**In normal operation, no ModifierFailure is thrown.**

---

## Services

### ModifierService
**File:** `services/modifier_service.dart`

**Method 1: applyModifiers (single-target)**
```dart
ModifierResult applyModifiers({
  required WrappedNode modifierSource,
  required String sourceFileId,
  required NodeRef sourceNode,
  required BoundPackBundle boundBundle,
  required SelectionSnapshot snapshot,
  required String contextSelectionId,
  required ApplicabilityService applicabilityService,
})
```

**Parameters:**
- `modifierSource` — Node containing modifiers
- `sourceFileId` — Provenance for index-ready output
- `sourceNode` — Provenance for index-ready output
- `boundBundle` — For entry/profile/cost lookups
- `snapshot` — Current roster state (for condition evaluation via M7)
- `contextSelectionId` — Context for condition evaluation
- `applicabilityService` — M7 service for condition evaluation

**Method 2: applyModifiersMany (bulk-friendly)**
```dart
List<ModifierResult> applyModifiersMany({
  required List<(WrappedNode modifierSource, String sourceFileId, NodeRef sourceNode)> sources,
  required BoundPackBundle boundBundle,
  required SelectionSnapshot snapshot,
  required String contextSelectionId,
  required ApplicabilityService applicabilityService,
})
```

**Purpose:**
- Deterministic bulk application in one pass
- Results preserve input order

**Behavior:**
1. Find `<modifier>` or `<modifiers>` children of source node
2. For each modifier, check applicability via M7
3. If applicable, apply operation to target
4. Return ModifierResult with all operations

---

## Modifier Types (Initial Set)

| Type | Semantics |
|------|-----------|
| `set` | Replace value with modifier value |
| `increment` | Add modifier value to current value |
| `decrement` | Subtract modifier value from current value |
| `append` | Append string to current value |

**Unknown types:** Emit `UNKNOWN_MODIFIER_TYPE` diagnostic, operation skipped.

---

## Determinism Contract

M8 guarantees:
- Same inputs → identical ModifierResult
- Modifier application order matches XML traversal
- `applyModifiersMany` preserves input order
- No hash-map iteration leaks
- No wall-clock dependence

---

## Required Tests

### Structural Invariants (MANDATORY)
- Modifier with `type="set"` replaces base value → effectiveValue equals modifier value
- Modifier with `type="increment"` adds to base → effectiveValue equals base + modifier
- Modifier with condition that evaluates `skipped` → operation in skippedOperations
- No modifiers → effectiveValue equals baseValue

### Applicability Integration
- Modifier with applicable condition → operation applied
- Modifier with non-applicable condition → operation skipped with reason

### Diagnostics
- Unknown modifier type → `UNKNOWN_MODIFIER_TYPE` diagnostic
- Unresolved target → `UNRESOLVED_MODIFIER_TARGET` diagnostic
- Unsupported target scope → `UNSUPPORTED_TARGET_SCOPE` diagnostic

### Determinism
- Applying same modifiers twice yields identical results
- `applyModifiersMany` preserves input order

### No-Failure Policy
- Unknown types do not throw ModifierFailure
- Unresolved targets do not throw ModifierFailure

---

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:

- **Modifier Value** — Type-safe variant wrapper for modifier values (int, double, string, bool)
- **Field Kind** — Enum disambiguating field namespace (characteristic, cost, constraint, metadata)
- **Modifier Target Ref** — Reference to modifier target with field namespace disambiguation
- **Modifier Operation** — Single modifier operation with type, target, value, and applicability
- **Modifier Result** — M8 output with base value, effective value, and applied/skipped operations
- **Modifier Diagnostic** — Non-fatal issue during modifier processing
- **Modifier Failure** — Fatal exception for M8 corruption
- **Modifier Service** — Service applying modifiers to produce effective values

---

## Frozen Invariants (M8 Modifiers)

The following invariants are locked and must not change without a formal unfreeze:

### Diagnostic Codes (Frozen Set — 7 codes)
1. `UNKNOWN_MODIFIER_TYPE` — Modifier type not recognized
2. `UNKNOWN_MODIFIER_FIELD` — Field not recognized
3. `UNKNOWN_MODIFIER_SCOPE` — Scope keyword not recognized
4. `UNRESOLVED_MODIFIER_TARGET` — Target ID not found in bundle
5. `INCOMPATIBLE_VALUE_TYPE` — Value type incompatible with field
6. `UNSUPPORTED_TARGET_KIND` — Target kind not supported for operation
7. `UNSUPPORTED_TARGET_SCOPE` — Scope not supported for target kind

### Determinism Guarantees
- Same inputs → identical `ModifierResult`
- Modifier application order matches XML traversal order
- `applyModifiersMany` preserves input order exactly
- No hash-map iteration leaks (all maps sorted before output)
- No wall-clock or random dependence

### No-Mutation Guarantee
- M8 does NOT modify `BoundPackBundle` (read-only access)
- M8 does NOT modify `SelectionSnapshot` (read-only access)
- M8 produces new `ModifierResult` objects, never mutates inputs

### Unknown Handling
- Unknown applicability (M7 returns `unknown`) → `effectiveValue` is `null`, diagnostic emitted
- Unknown modifier type → diagnostic emitted, operation skipped
- Unknown field/scope → diagnostic emitted, operation skipped

### Non-Goals (Explicitly Excluded)
- M8 does NOT evaluate constraints (M6's job)
- M8 does NOT evaluate conditions (M7's job)
- M8 does NOT interpret rules or semantics
- M8 does NOT persist data or make network calls
- M8 does NOT produce UI elements

---

## Approval Checklist

- [x] Module layout approved
- [x] Core model names approved (ModifierValue, FieldKind, ModifierTargetRef, ModifierOperation, ModifierResult, ModifierDiagnostic, ModifierFailure)
- [x] Service name approved (ModifierService)
- [x] Service methods approved (applyModifiers, applyModifiersMany)
- [x] Modifier types approved (set, increment, decrement, append)
- [x] Diagnostic codes approved (7 codes)
- [x] FieldKind enum approved (characteristic, cost, constraint, metadata)
- [x] ModifierValue sealed class approved (Int, Double, String, Bool variants)
- [x] Determinism contract approved
- [x] Glossary terms approved

**FROZEN 2026-02-12. All 18 invariant tests pass.**

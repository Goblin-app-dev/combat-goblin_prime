# Phase 5 — M7 Rules Approved Names

## Status

- Phase 1A (M1 Acquire): **FROZEN**
- Phase 1B (M2 Parse): **FROZEN**
- Phase 1C (M3 Wrap): **FROZEN** (2026-02-04)
- Phase 2 (M4 Link): **FROZEN** (2026-02-05)
- Phase 3 (M5 Bind): **FROZEN** (2026-02-10)
- Phase 4 (M6 Evaluate): **FROZEN** (2026-02-11)
- Phase 5 (M7 Rules): **PROPOSAL** — revision 1, awaiting approval

---

## Revision History

| Rev | Date | Changes |
|-----|------|---------|
| 1 | 2026-02-11 | Initial proposal |

---

## Purpose

M7 Rules binds `rule` elements that were deferred from M5 Bind. Rules are game rule definitions describing abilities, weapon traits, and special rules.

**M7 binds rules into typed entities. M7 does NOT evaluate rules against roster state.**

---

## Scope Boundaries

### M7 MAY:
- Bind `rule` elements into BoundRule
- Follow infoLinks to rules using M4's ResolvedRefs
- Build entry→rule association index
- Apply shadowing policy (first-match-wins by file order)
- Emit diagnostics for unresolved links and shadowed definitions
- Provide query methods for rule lookup

### M7 MUST NOT:
- Modify BoundPackBundle (read-only)
- Evaluate rules (rules are definitions, not constraints)
- Touch raw XML (uses WrappedNode only)
- Persist data (storage is M1's domain)
- Make network calls (network is M1's domain)
- Produce UI elements (UI is downstream)
- Bind modifiers (deferred to M8+)
- Evaluate conditions (deferred to M8+)

---

## Tag Eligibility (MANDATORY)

| Bound Type | Eligible tagNames |
|------------|-------------------|
| BoundRule | `rule` |

**Link elements (infoLink)** are followed to their resolved targets. Only targets with tagName `rule` are bound as rules.

---

## Module Layout

### Module
- Folder: `lib/modules/m7_rules/`
- Barrel: `lib/modules/m7_rules/m7_rules.dart`

### Public Exports (barrel only)
- `services/rules_service.dart`
- `models/extended_bound_pack_bundle.dart`
- `models/bound_rule.dart`
- `models/rules_diagnostic.dart`
- `models/rules_failure.dart`

### File Layout
```
lib/modules/m7_rules/
├── m7_rules.dart
├── models/
│   ├── extended_bound_pack_bundle.dart
│   ├── bound_rule.dart
│   ├── rules_diagnostic.dart
│   └── rules_failure.dart
└── services/
    └── rules_service.dart
```

---

## Core Types

### ExtendedBoundPackBundle
**File:** `models/extended_bound_pack_bundle.dart`

Complete M7 output extending M5.

**Fields:**
- `BoundPackBundle boundBundle` — original M5 output (immutable)
- `List<BoundRule> rules` — all bound rules (flat list)
- `List<RulesDiagnostic> diagnostics` — rule-specific diagnostics
- `DateTime extendedAt` — derived from `boundBundle.boundAt` (deterministic)
- `String packId` — same as boundBundle.packId

**Query methods:**
- `BoundRule? ruleById(String id)`
- `Iterable<BoundRule> get allRules`
- `Iterable<BoundRule> rulesForEntry(String entryId)`

**Delegation:** All M5 query methods delegated to `boundBundle`.

**Query Semantics:**

| Query | ID not found | Relationship empty |
|-------|--------------|-------------------|
| `ruleById(id)` | Returns `null` | N/A |
| `allRules` | N/A | Returns empty iterable |
| `rulesForEntry(id)` | Returns empty iterable | Returns empty iterable |

**No query throws on missing data.** All return null or empty.

**Deterministic Ordering:**
All list-returning queries return results in **binding order**:
1. File resolution order (primaryCatalog → dependencyCatalogs → gameSystem)
2. Within each file: node index order (pre-order depth-first from M3)

---

### BoundRule
**File:** `models/bound_rule.dart`

Bound game rule definition.

**Eligible tagNames:** `rule`

**Fields:**
- `String id` — unique rule identifier
- `String name` — display name
- `String? description` — rule text (null if empty)
- `String? publicationId` — source publication reference
- `String? page` — page reference in publication
- `bool isHidden` — true if hidden="true"
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- Description extracted from nested `description` element text
- Empty or missing description → null
- Hidden defaults to false if absent
- publicationId/page stored as-is (not resolved)

---

### RulesDiagnostic
**File:** `models/rules_diagnostic.dart`

Non-fatal semantic issue during rule binding.

**Fields:**
- `String code` — diagnostic code (closed set)
- `String message` — human-readable description
- `String sourceFileId` — file where issue occurred
- `NodeRef? sourceNode` — node where issue occurred (if applicable)
- `String? targetId` — the ID involved (if applicable)

**Diagnostic Codes (closed set):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `UNRESOLVED_RULE_LINK` | infoLink targetId not found | Skip link, omit from rules |
| `SHADOWED_RULE_DEFINITION` | Rule ID matched multiple targets | Use first target, log shadowed |
| `EMPTY_RULE_DESCRIPTION` | Rule has no description text | Bind rule, description = null |

**Rules:**
- Diagnostics are accumulated, never thrown
- All diagnostics are non-fatal
- New diagnostic codes require doc + glossary update

---

### RulesFailure
**File:** `models/rules_failure.dart`

Fatal exception for M7 failures.

**Fields:**
- `String message`
- `String? fileId`
- `String? details`

**Fatality Policy:**

RulesFailure is thrown ONLY for:
1. Corrupted M5 input — BoundPackBundle violates frozen M5 contracts
2. Internal invariant violation — M7 implementation bug

RulesFailure is NOT thrown for:
- Unresolved rule links → diagnostic
- Shadowed definitions → diagnostic
- Empty descriptions → diagnostic

**In normal operation, no RulesFailure is thrown.**

---

## Services

### RulesService
**File:** `services/rules_service.dart`

**Method:**
```dart
Future<ExtendedBoundPackBundle> bindRules({
  required BoundPackBundle boundBundle,
}) async
```

**Behavior:**
1. Initialize rule collections and indices
2. Traverse all files in file resolution order (primary → deps → gamesystem)
3. For each `rule` element: create BoundRule
4. Resolve infoLinks to rules using M4's ResolvedRefs
5. Apply shadowing policy (first-match-wins)
6. Build query indices
7. Return ExtendedBoundPackBundle with all rules and diagnostics

---

## Shadowing Policy

### File Precedence

**First-match-wins** based on file resolution order:

1. primaryCatalog (highest precedence)
2. dependencyCatalogs (in list order)
3. gameSystem (lowest precedence)

### Within-File Tie-Break

If multiple rules with the same ID exist in one file:
- **First in node order wins** — earliest NodeRef in `WrappedFile.nodes` order
- Emit SHADOWED_RULE_DEFINITION diagnostic for skipped duplicates

---

## Rule Root Definition (MANDATORY)

A **bindable rule root** is any node where:
1. The node's `tagName` is `rule`
2. The node does NOT have an ancestor with tagName `rule`

This is **container-agnostic** — works with any schema variant.

---

## Entry-Rule Associations

### Strategy

Since M5 is frozen and cannot be modified, M7 builds a separate association index:

```dart
Map<String, List<String>> _entryRuleIndex; // entryId → List<ruleId>
```

`rulesForEntry(entryId)` uses this index to return associated rules.

### Association Sources

1. **Nested rules** — rules directly nested within entries
2. **InfoLinks to rules** — entries referencing rules via infoLink type="rule"

Both are resolved during M7 binding and added to the index.

---

## Determinism Contract

M7 guarantees:
- Same BoundPackBundle → identical ExtendedBoundPackBundle
- Rule ordering matches file resolution order → node order
- Query results ordered deterministically
- No hash-map iteration leaks
- Stable diagnostic ordering

### extendedAt Determinism Rule (MANDATORY)

`extendedAt` must be derived from upstream immutable input:

**Required:** `extendedAt = boundBundle.boundAt`

**Forbidden:** `extendedAt = DateTime.now()`

---

## Phase Isolation Rules (Mandatory)

### Terminology Isolation

| Module | Terminology |
|--------|-------------|
| M5 Bind | BindDiagnostic |
| M6 Evaluate | EvaluationWarning, EvaluationNotice |
| M7 Rules | RulesDiagnostic |

### Code Pattern Isolation

| Module | Code Patterns |
|--------|---------------|
| M5 Bind | `UNRESOLVED_ENTRY_LINK`, `SHADOWED_DEFINITION` |
| M7 Rules | `UNRESOLVED_RULE_LINK`, `SHADOWED_RULE_DEFINITION` |

### Failure Type Isolation

| Module | Failure Type |
|--------|-------------|
| M5 Bind | BindFailure |
| M6 Evaluate | EvaluateFailure |
| M7 Rules | RulesFailure |

---

## Required Tests

### Structural Invariants (MANDATORY)
- Every `rule` element produces a BoundRule
- Rules with descriptions have non-null description
- Rules without descriptions have null description

### Query Contracts
- ruleById returns correct rule or null
- allRules contains all bound rules
- rulesForEntry returns correct subset

### Diagnostic Invariants
- Unresolved infoLink to rule → UNRESOLVED_RULE_LINK diagnostic
- Multi-target rule → SHADOWED_RULE_DEFINITION diagnostic

### Determinism
- Binding same input twice yields identical output

### No-Failure Policy
- Unresolved rule links do not throw RulesFailure
- Empty descriptions do not throw RulesFailure

---

## Glossary Additions Required

Before implementation, add to `/docs/glossary.md`:

- **Bound Rule** — Game rule definition with name, description, and provenance
- **Extended Bound Pack Bundle** — M7 output extending M5 with bound rules
- **Rules Diagnostic** — Non-fatal semantic issue during rule binding
- **Rules Failure** — Fatal exception for M7 corruption
- **Rules Service** — Service binding rules from BoundPackBundle

---

## Approval Checklist

- [ ] Module layout approved
- [ ] Core model names approved (ExtendedBoundPackBundle, BoundRule, RulesDiagnostic, RulesFailure)
- [ ] Service name approved (RulesService)
- [ ] Tag eligibility approved (rule only)
- [ ] Field definitions approved
- [ ] Query surface approved
- [ ] Query semantics approved (null/empty on missing)
- [ ] Entry-rule association strategy approved (separate index)
- [ ] Shadowing policy approved (same as M5)
- [ ] Diagnostic codes approved
- [ ] Determinism contract approved
- [ ] Phase isolation rules approved
- [ ] Glossary terms approved

**NO CODE UNTIL APPROVAL.**

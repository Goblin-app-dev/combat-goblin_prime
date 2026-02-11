# Phase 5 — M7 Rules Design Proposal

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

## Problem Statement

M5 Bind explicitly deferred binding `rule` elements:

> "Bind `rule` elements (deferred to future phase)"

Rules in BSData are game rule definitions that describe abilities, weapon traits, and special rules. Examples include:
- "Pistol" — describes pistol weapon behavior
- "Hazardous" — describes hazardous weapon risk
- "Leader" — describes unit leader mechanics
- "Feel No Pain" — describes damage mitigation ability

Rules are:
- Attached to entries (weapons, units, abilities)
- Referenced via infoLinks
- Displayed to users as help text
- Looked up by ID for cross-referencing

**M7 Rules** binds rule elements into typed entities with a query surface, completing the entity binding phase.

---

## Inputs

### Input A: BoundPackBundle (from M5 Bind)

M7 extends M5's output to include rules. The BoundPackBundle is passed through with rules added.

Key M5 outputs used:
- `LinkedPackBundle` — for accessing WrappedNodes
- Existing bound entities (entries, profiles, categories)
- ResolvedRefs from M4 (for infoLinks to rules)

---

## Outputs

### Output: ExtendedBoundPackBundle

M7 extends BoundPackBundle with:
- `List<BoundRule>` — all bound rules
- Query methods for rules
- Rule associations on entries

**Design Decision: Extension vs. New Type**

Two options considered:

| Option | Approach | Tradeoff |
|--------|----------|----------|
| A | New ExtendedBoundPackBundle type | Type safety, clear phase boundary |
| B | Add rules to existing BoundPackBundle | Simpler, but modifies frozen M5 output |

**Recommendation:** Option A — new type maintains phase isolation and doesn't modify frozen M5 contracts.

---

## Core Types

### BoundRule

**File:** `models/bound_rule.dart`

Bound game rule definition.

**Eligible tagNames:** `rule`

**Fields:**
- `String id` — unique rule identifier
- `String name` — display name
- `String? description` — rule text (may be null if empty)
- `String? publicationId` — source publication reference
- `String? page` — page reference in publication
- `bool isHidden` — true if hidden="true"
- `String sourceFileId` — provenance
- `NodeRef sourceNode` — provenance

**Rules:**
- Description extracted from child `description` element text
- Empty description → null (not empty string)
- Hidden flag defaults to false if absent

---

### ExtendedBoundPackBundle

**File:** `models/extended_bound_pack_bundle.dart`

M7 output extending M5's BoundPackBundle.

**Fields:**
- `BoundPackBundle boundBundle` — original M5 output (unchanged)
- `List<BoundRule> rules` — all bound rules (flat list)
- `DateTime extendedAt` — derived from `boundBundle.boundAt` (deterministic)
- `String packId` — same as boundBundle.packId

**Query methods:**
- `BoundRule? ruleById(String id)`
- `Iterable<BoundRule> get allRules`
- `Iterable<BoundRule> rulesForEntry(String entryId)`

**Query Semantics:**
| Query | ID not found | Relationship empty |
|-------|--------------|-------------------|
| `ruleById(id)` | Returns `null` | N/A |
| `allRules` | N/A | Returns empty iterable |
| `rulesForEntry(id)` | Returns empty iterable | Returns empty iterable |

**Delegation:** All M5 query methods are delegated to `boundBundle`:
- `entryById(id)` → `boundBundle.entryById(id)`
- `allEntries` → `boundBundle.allEntries`
- etc.

---

### RulesDiagnostic

**File:** `models/rules_diagnostic.dart`

Non-fatal semantic issue during rule binding.

**Fields:**
- `String code` — diagnostic code (closed set)
- `String message` — human-readable description
- `String sourceFileId` — file where issue occurred
- `NodeRef? sourceNode` — node where issue occurred
- `String? targetId` — the ID involved (if applicable)

**Diagnostic Codes (closed set):**

| Code | Condition | Behavior |
|------|-----------|----------|
| `UNRESOLVED_RULE_LINK` | infoLink to rule targetId not found | Skip link, omit from rules |
| `SHADOWED_RULE_DEFINITION` | Rule ID matched multiple targets | Use first target, log shadowed |
| `EMPTY_RULE_DESCRIPTION` | Rule has no description text | Bind rule, description = null |

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
2. Traverse all files in file resolution order (same as M5)
3. For each `rule` element: create BoundRule
4. Resolve infoLinks to rules using M4's ResolvedRefs
5. Apply shadowing policy (first-match-wins, same as M5)
6. Build query indices
7. Return ExtendedBoundPackBundle with all rules and diagnostics

---

## Entry-Rule Associations

Rules are associated with entries through two mechanisms:

### 1. Nested Rules
Rules nested directly within entries are collected during binding.

**Implementation:** When binding entries (M5), collect rule references. M7 populates these.

**Design Decision:** M5 is frozen, so M7 cannot modify entry binding. Instead:
- M7 builds a separate `Map<entryId, List<ruleId>>` index
- `rulesForEntry(entryId)` uses this index

### 2. InfoLinks to Rules
Entries may reference rules via infoLinks with type="rule".

**Implementation:**
- M4 already resolves infoLink targetIds
- M7 filters for type="rule" infoLinks
- Associates resolved rule with entry

---

## Rule Root Definition

A **bindable rule root** is any node where:
1. The node's `tagName` is `rule`
2. The node does NOT have an ancestor with tagName `rule`

This matches the entry-root detection pattern from M5.

**Shared Rules:** Rules in `sharedRules` container are bound at file level and referenced via infoLinks.

---

## Shadowing Policy

Same as M5:

### File Precedence
**First-match-wins** based on file resolution order:
1. primaryCatalog (highest precedence)
2. dependencyCatalogs (in list order)
3. gameSystem (lowest precedence)

### Within-File Tie-Break
If multiple rules with the same ID exist in one file:
- **First in node order wins**
- Emit SHADOWED_RULE_DEFINITION diagnostic for skipped duplicates

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

## Scope Boundaries

### M7 MAY:
- Bind `rule` elements into BoundRule
- Follow infoLinks to rules
- Build entry→rule associations
- Apply shadowing policy
- Emit diagnostics for unresolved links
- Provide query methods for rule lookup

### M7 MUST NOT:
- Modify BoundPackBundle (read-only pass-through)
- Evaluate rules against roster state (rules are definitions, not constraints)
- Touch raw XML (uses WrappedNode only)
- Persist data
- Make network calls
- Produce UI elements
- Bind modifiers (deferred to M8+)
- Evaluate conditions (deferred to M8+)

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
| M7 Rules | `UNRESOLVED_RULE_LINK`, `SHADOWED_RULE_DEFINITION`, `EMPTY_RULE_DESCRIPTION` |

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
- Rules with descriptions have non-null description field
- Rules without descriptions have null description field

### Query Contracts
- ruleById returns correct rule or null
- allRules contains all bound rules
- rulesForEntry returns correct subset

### Diagnostic Invariants
- Unresolved infoLink to rule → UNRESOLVED_RULE_LINK diagnostic
- Multi-target rule → SHADOWED_RULE_DEFINITION diagnostic
- Empty description → EMPTY_RULE_DESCRIPTION diagnostic

### Determinism
- Binding same input twice yields identical output

### No-Failure Policy
- Unresolved rule links do not throw RulesFailure
- Empty descriptions do not throw RulesFailure

---

## Open Questions

### Q1: Should rules be added to BoundEntry?

**Options:**
- A) Add `List<BoundRule> rules` field to BoundEntry (modifies M5)
- B) Keep rules separate with entry→rule index (M5 unchanged)

**Recommendation:** Option B — M5 is frozen; maintain phase isolation.

### Q2: Publication resolution?

Rules reference `publicationId`. Should M7 resolve this to publication name?

**Options:**
- A) Store publicationId as-is (defer resolution)
- B) Resolve to publication name during binding

**Recommendation:** Option A — publication resolution is a separate concern.

### Q3: Rule inheritance?

Some rules may be defined at game system level and overridden in catalogs.

**Decision:** Same shadowing policy as M5 — first-match-wins by file order.

---

## Glossary Terms Required

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
- [ ] Entry-rule association strategy approved
- [ ] Shadowing policy approved (same as M5)
- [ ] Diagnostic codes approved
- [ ] Determinism contract approved
- [ ] Phase isolation rules approved
- [ ] Glossary terms approved

**NO CODE UNTIL APPROVAL.**

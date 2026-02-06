⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 23: M5 proposal SME clarifications applied (docs-only).

**Step 23 details:** SME review identified under-specifications; clarifications added:
- Tag eligibility lists per bound type (prevents wrong-type binding)
- Match definition: id + tagName both required
- Within-file tie-break: first in node order wins
- Query semantics: null/empty on missing, no throwing
- Deterministic ordering: binding order for all list queries
- Hidden content policy: bind with flag, don't filter
- SME decisions recorded (EntryGroup=no, Rules=deferred, TypeRegistry=no, Provenance=yes, Hidden=flag)
- Audited against frozen M3/M4 contracts: consistent
- Files touched this step:
  - docs/phases/phase_3_m5_bind_design_proposal.md (clarifications)
  - docs/phases/phase_3_m5_bind_approved_names_proposal.md (clarifications)
  - tools/name_audit.md (this file, Step 23)
- No new names introduced

---

Step 22: Phase 3 (M5 Bind) docs-first proposal created — awaiting approval.

**Step 22 details:** M5 Bind docs-first proposal:
- Created design proposal: docs/phases/phase_3_m5_bind_design_proposal.md
- Created approved names proposal: docs/phases/phase_3_m5_bind_approved_names_proposal.md
- Updated module_io_registry.md with M5 PROPOSAL section
- Updated name_audit.md (this file, Step 22)
- Glossary NOT updated (no code yet; terms added when M5 implemented)
- Files touched this step:
  - docs/phases/phase_3_m5_bind_design_proposal.md (NEW)
  - docs/phases/phase_3_m5_bind_approved_names_proposal.md (NEW)
  - docs/module_io_registry.md (M5 PROPOSAL section)
  - tools/name_audit.md (this file)

---

Step 21: Phase 2 (M4 Link) FROZEN — all tests passed.

**PROCESS NOTE:** M3 code landed (commit `88c6a77`) before docs trail was fully consistent.
Docs trail repaired in commit `b9ccb03`. No docs-first compliance claimed for M3.

**Step 20 details:** M4 Link implementation:
- Created m4_link module (barrel + models + service)
- Implemented: LinkedPackBundle, SymbolTable, ResolvedRef, LinkDiagnostic, LinkFailure, LinkService
- Tests: m4_link_flow_test.dart, m4_link_invariants_test.dart
- All names from approved Phase 2 proposal only

**Step 21 details:** M4 Link freeze:
- All 9 tests passed (2026-02-05)
- Added diagnostic pinpointing to flow test
- Files touched this step:
  - test/modules/m4_link/m4_link_flow_test.dart (diagnostic detail output)
  - docs/module_io_registry.md (M4 section marked FROZEN)
  - docs/glossary.md (added: Symbol Table, Resolved Ref, Link Diagnostic, Link Failure, Linked Pack Bundle, Link Service)
  - tools/name_audit.md (this file, Step 21)

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file

### New Files
- docs/phases/phase_1c_m3_approved_names_proposal.md (M3 naming proposal)
- lib/modules/m3_wrap/m3_wrap.dart (barrel file)
- lib/modules/m3_wrap/models/node_ref.dart
- lib/modules/m3_wrap/models/wrapped_node.dart
- lib/modules/m3_wrap/models/wrapped_file.dart
- lib/modules/m3_wrap/models/wrapped_pack_bundle.dart
- lib/modules/m3_wrap/models/wrap_failure.dart
- lib/modules/m3_wrap/services/wrap_service.dart
- test/modules/m3_wrap/m3_wrap_flow_test.dart
- test/modules/m3_wrap/m3_wrap_invariants_test.dart

### Modified Files
- docs/phases/phase_1c_m3_approved_names_proposal.md (updated status: IMPLEMENTED, approval checklist marked complete)
- docs/module_io_registry.md (updated M3 status: Implemented, tests pending)
- docs/glossary.md (added: Node Ref, Wrapped Node, Wrapped File, Wrapped Pack Bundle, Wrap Failure)
- tools/name_audit.md (added process repair note, updated Step 14)

---

## Existing Symbols Referenced
(All names copied directly from code or approved docs)
- [x] Files
- [x] Classes
- [x] Methods
- [x] Fields
- [x] Enums / enum values
- [x] Public constants

---

## New or Changed Names
- [ ] No new or changed public names introduced
- [x] Yes — new or changed names were introduced

### Implemented Names (approved)
- NodeRef (strongly-typed node handle)
- WrappedNode (indexed element with provenance)
- WrappedFile (per-file node table + idIndex)
- WrappedPackBundle (complete M3 output)
- WrapFailure (structural corruption exception)
- WrapService (ParsedPackBundle → WrappedPackBundle)

All names documented in:
- /docs/phases/phase_1c_m3_approved_names_proposal.md
- /docs/glossary.md

**FROZEN.** All 17 tests passed (2026-02-04).

---

## Module Boundary Integrity
- [x] Changes stay within declared module boundaries
- [x] No upstream module depends on downstream internals
- [x] `/docs/module_io_registry.md` updated to reflect new IO contracts

---

## Phase Freeze Compliance
- [x] No frozen module was modified
- [ ] Frozen module modified with explicit approval

M1 Acquire frozen. M2 Parse frozen. M3 Wrap frozen (2026-02-04). M4 Link frozen (2026-02-05).

---

## Copyright Guardrail
- [x] No prohibited IP terms introduced
- [x] External filenames displayed verbatim only

---

## Determinism & Debuggability
- [x] M3 traversal contract specifies deterministic indexing (pre-order depth-first, root=0)
- [x] idIndex collision policy documented (list-based, no throwing)

---

## Final Verification
- [x] Names follow established codebase patterns (m1_acquire, m2_parse → m3_wrap)
- [x] Naming proposal document created
- [x] Glossary updated with M3 terms
- [x] Module IO registry updated with M3 contract
- [x] Implementation complete — tests passed
- [x] **M3 FROZEN** (2026-02-04)

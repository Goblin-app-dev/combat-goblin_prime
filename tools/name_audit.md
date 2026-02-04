⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 13: Phase 1C (M3 Wrap) naming proposal — docs-first, awaiting approval.

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file

### New Files
- docs/phases/phase_1c_m3_approved_names_proposal.md (M3 naming proposal)

### Modified Files
- docs/module_io_registry.md (added M3 Wrap proposal section)
- docs/glossary.md (added: Node Ref, Wrapped Node, Wrapped File, Wrapped Pack Bundle, Wrap Failure)
- tools/name_audit.md (updated: Step 13)

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

### Proposed Names (awaiting approval)
- NodeRef (strongly-typed node handle)
- WrappedNode (indexed element with provenance)
- WrappedFile (per-file node table + idIndex)
- WrappedPackBundle (complete M3 output)
- WrapFailure (structural corruption exception)
- WrapService (ParsedPackBundle → WrappedPackBundle)

All names documented in:
- /docs/phases/phase_1c_m3_approved_names_proposal.md
- /docs/glossary.md

**NO CODE UNTIL APPROVAL.**

---

## Module Boundary Integrity
- [x] Changes stay within declared module boundaries
- [x] No upstream module depends on downstream internals
- [x] `/docs/module_io_registry.md` updated to reflect new IO contracts

---

## Phase Freeze Compliance
- [x] No frozen module was modified
- [ ] Frozen module modified with explicit approval

Docs-only change. M1 Acquire frozen. M2 Parse frozen. M3 Wrap proposal only.

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
- [ ] **AWAITING APPROVAL** — no code written yet

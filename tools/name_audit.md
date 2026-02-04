⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 12: Phase 1B (M2 Parse) structural validation tests added. M2 frozen.

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file

### New Files
- test/modules/m2_parse/m2_parse_invariants_test.dart (structural invariant tests)

### Modified Files
- tools/name_audit.md (updated: Step 12)
- docs/module_io_registry.md (marked M2 Parse as frozen)

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
- [x] No new or changed public names introduced
- [ ] Yes — new or changed names were introduced

Structural invariant tests only. No new public API names introduced.
Tests validate M2 losslessness guarantees: tag, attributes, child order, text, provenance, determinism.

---

## Module Boundary Integrity
- [x] Changes stay within declared module boundaries
- [x] No upstream module depends on downstream internals
- [x] `/docs/module_io_registry.md` updated to reflect new IO contracts

---

## Phase Freeze Compliance
- [x] No frozen module was modified
- [ ] Frozen module modified with explicit approval

Test addition only. M1 Acquire frozen. M2 Parse now frozen (API-stable, no logic changes).

---

## Copyright Guardrail
- [x] No prohibited IP terms introduced
- [x] External filenames displayed verbatim only

---

## Determinism & Debuggability
- [x] Test validates deterministic pipeline (M1 → M2)
- [x] Diagnostic output for debugging

---

## Final Verification
- [x] Names copied, not retyped
- [x] Test imports use approved barrel paths
- [x] No deep schema assertions (deferred to Phase 2)
- [x] M2 API verified against phase_1b_m2_approved_names_proposal.md
- [x] M1 files unchanged

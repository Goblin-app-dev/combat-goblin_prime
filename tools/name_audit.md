⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 11: Add M2 Parse integration test (acquire → parse flow).

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file

### New Files
- test/modules/m2_parse/m2_parse_flow_test.dart (integration test: acquire → parse)

### Modified Files
- tools/name_audit.md (updated: Step 11)

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

This is an app-serving integration test. No new public API names introduced.
Test validates the M1 Acquire → M2 Parse pipeline using existing fixtures.

---

## Module Boundary Integrity
- [x] Changes stay within declared module boundaries
- [x] No upstream module depends on downstream internals
- [x] `/docs/module_io_registry.md` updated to reflect new IO contracts

---

## Phase Freeze Compliance
- [x] No frozen module was modified
- [ ] Frozen module modified with explicit approval

Test addition only. M1 Acquire remains frozen. M2 Parse stub unchanged.

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

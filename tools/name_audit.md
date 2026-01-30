⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 2: M1 Acquire models verified against approved names; Diagnostic legalized.

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file
- lib/modules/m1_acquire/services/acquire_service.dart
- tools/name_audit.md

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

If **Yes**, ALL of the following are mandatory:
- [ ] Names were proposed before implementation
- [ ] `/docs/glossary.md` updated
- [ ] `/docs/naming_contract.md` updated if rules changed
- [ ] `/docs/name_change_log.md` updated (for renames or semantic changes)
- [ ] Explicit approval obtained

If any box above is unchecked, the change is invalid.

---

## Module Boundary Integrity
- [x] Changes stay within declared module boundaries
- [x] No upstream module depends on downstream internals
- [x] `/docs/module_io_registry.md` updated if IO changed

---

## Phase Freeze Compliance
- [x] No frozen module was modified  
- [ ] Frozen module modified with explicit approval

---

## Copyright Guardrail
- [x] No prohibited IP terms introduced
- [x] External filenames displayed verbatim only

---

## Determinism & Debuggability
- [x] Output is deterministic
- [x] Diagnostics are structured and explain failures
- [x] No silent failure paths introduced

---

## Final Verification
- [x] Names copied, not retyped
- [x] Naming docs are authoritative and current
- [x] Code matches approved names exactly

⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 5: Fix test compilation errors (import path correction + template removal).

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file
- test/modules/m1_acquire/m1_acquire_flow_test.dart (import fix: combat_goblin → combat_goblin_prime)
- test/widget_test.dart (deleted: template with invalid package:untitled import)

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

This change corrects a bug (wrong package name in import) to match the existing
established package name `combat_goblin_prime` from pubspec.yaml. No new names.

---

## Module Boundary Integrity
- [x] Changes stay within declared module boundaries
- [x] No upstream module depends on downstream internals
- [x] `/docs/module_io_registry.md` not affected (test-only change)

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

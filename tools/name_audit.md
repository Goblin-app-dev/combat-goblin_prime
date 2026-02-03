⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 6: Add PackManifest, SourceLocator, DependencyRecord for update checking workflow.

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file

### New Files
- lib/modules/m1_acquire/models/dependency_record.dart (new: DependencyRecord model)
- lib/modules/m1_acquire/models/source_locator.dart (new: SourceLocator model)
- lib/modules/m1_acquire/models/pack_manifest.dart (new: PackManifest model)

### Modified Files
- lib/modules/m1_acquire/models/acquire_failure.dart (added: missingTargetIds field)
- lib/modules/m1_acquire/models/raw_pack_bundle.dart (added: manifest field)
- lib/modules/m1_acquire/services/acquire_service.dart (added: source parameter, manifest building)
- lib/modules/m1_acquire/m1_acquire.dart (added: new model exports)
- test/modules/m1_acquire/m1_acquire_flow_test.dart (added: source parameter, manifest validation)
- docs/glossary.md (added: new term definitions)
- docs/name_change_log.md (added: new name entries)
- docs/phases/phase_1a_m1_approved_names_proposal.md (added: new model specs)
- docs/module_io_registry.md (updated: M1 IO contracts)

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

### New Names (all approved 2026-02-02)
- DependencyRecord (model)
- SourceLocator (model)
- PackManifest (model)
- AcquireFailure.missingTargetIds (field)
- RawPackBundle.manifest (field)
- AcquireService.buildBundle source parameter

All names documented in:
- /docs/glossary.md
- /docs/name_change_log.md
- /docs/phases/phase_1a_m1_approved_names_proposal.md

---

## Module Boundary Integrity
- [x] Changes stay within declared module boundaries
- [x] No upstream module depends on downstream internals
- [x] `/docs/module_io_registry.md` updated to reflect new IO contracts

---

## Phase Freeze Compliance
- [x] No frozen module was modified
- [ ] Frozen module modified with explicit approval

M1 Acquire is not yet frozen; changes are permitted.

---

## Copyright Guardrail
- [x] No prohibited IP terms introduced
- [x] External filenames displayed verbatim only

---

## Determinism & Debuggability
- [x] Output is deterministic
- [x] Diagnostics are structured and explain failures
- [x] No silent failure paths introduced
- [x] AcquireFailure now includes missingTargetIds for actionable UI prompts

---

## Final Verification
- [x] Names copied, not retyped
- [x] Naming docs are authoritative and current
- [x] Code matches approved names exactly

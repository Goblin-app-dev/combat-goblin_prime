⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 9: Phase 1B M2 Parse naming proposal (docs-only, awaiting approval).

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file

### New Files
- docs/phases/phase_1b_m2_approved_names_proposal.md (M2 naming proposal)

### Modified Files
- docs/module_io_registry.md (added: M2 Parse section)
- tools/name_audit.md (updated: Step 9 naming proposal)

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

This is a naming proposal (docs-only). No code written yet.
Proposed names awaiting approval:
- ElementDto (generic XML element representation)
- ParsedFile (parsed file with provenance)
- ParsedPackBundle (complete parsed output)
- ParseFailure (parse error with diagnostics)
- ParseService (bytes → DTO conversion)

Glossary additions required before implementation:
- Element DTO
- Parsed File
- Parsed Pack Bundle

---

## Module Boundary Integrity
- [x] Changes stay within declared module boundaries
- [x] No upstream module depends on downstream internals
- [x] `/docs/module_io_registry.md` updated to reflect new IO contracts

---

## Phase Freeze Compliance
- [x] No frozen module was modified
- [ ] Frozen module modified with explicit approval

Docs-only change; no code modified.

---

## Copyright Guardrail
- [x] No prohibited IP terms introduced
- [x] External filenames displayed verbatim only

---

## Determinism & Debuggability
- [x] N/A — docs-only change, no runtime behavior affected

---

## Final Verification
- [x] Names copied, not retyped
- [x] Naming docs are authoritative and current
- [x] Conceptual layer names are proposals only, not final implementation names

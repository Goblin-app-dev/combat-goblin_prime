⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 10: Phase 1B M2 Parse naming approved + glossary + stub code.

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file

### New Files
- lib/modules/m2_parse/m2_parse.dart (barrel)
- lib/modules/m2_parse/models/element_dto.dart
- lib/modules/m2_parse/models/parsed_file.dart
- lib/modules/m2_parse/models/parsed_pack_bundle.dart
- lib/modules/m2_parse/models/parse_failure.dart
- lib/modules/m2_parse/services/parse_service.dart

### Modified Files
- docs/phases/phase_1b_m2_approved_names_proposal.md (approved, caveats documented)
- docs/module_io_registry.md (M2 Parse section finalized)
- docs/glossary.md (added: Element DTO, Parsed File, Parsed Pack Bundle, Parse Failure)
- tools/name_audit.md (updated: Step 10)

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

### New Names (approved 2026-02-03)
- ElementDto (generic XML element representation)
- ParsedFile (parsed file with source provenance)
- ParsedPackBundle (complete parsed output)
- ParseFailure (parse error with diagnostics)
- ParseService (bytes → DTO conversion)

All names documented in:
- /docs/glossary.md
- /docs/phases/phase_1b_m2_approved_names_proposal.md

Caveats documented:
- sourceIndex is nullable/best-effort (line numbers not guaranteed by xml package)
- "Lossless" means semantic preservation, not byte-identical reconstruction

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

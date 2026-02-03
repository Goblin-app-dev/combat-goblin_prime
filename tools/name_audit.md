⚠️ PARTIAL FILE OUTPUTS ARE NOT ACCEPTABLE — FULL FILES ONLY ⚠️

# Name & Change Audit Checklist

This checklist MUST be completed for every change or PR.
If any required item is unchecked, the change is invalid.

Step 7: Document Phase 1B+ layer contracts (docs-only, no code changes).

---

## Files Touched
- [x] Exact file paths listed
- [x] Full contents provided for every changed file

### New Files
- (none)

### Modified Files
- docs/module_io_registry.md (added: Phase 1B+ layer contracts for Index Reader, Downloader, Orchestrator, Cleanup, Update Checker)
- docs/glossary.md (added: Attempt Status Wrapper, Index (BSData), Version Token definitions)
- tools/name_audit.md (updated: Step 7 docs-only change)

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

This is a docs-only change. No new public API names introduced.
Glossary terms added are conceptual definitions, not code symbols:
- Attempt Status Wrapper (concept, not a type)
- Index (BSData) (external ecosystem term)
- Version Token (concept, not a type)

Future Phase 1B+ layers described use conceptual names only (Index Reader, Downloader, Orchestrator, Cleanup, Update Checker) — actual implementation names will be proposed and approved before coding.

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

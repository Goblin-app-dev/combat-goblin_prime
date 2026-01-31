# Name Change Log

All renames or semantic changes must be recorded here.

---

## Format
- Date
- Old name
- New name
- Reason
- Approval reference

---

No silent renames are permitted.

---

## 2026-01-30
- Old name: N/A
- New name: Diagnostic
- Reason: Legalize public type referenced by RawPackBundle.acquireDiagnostics
- Approval reference: Phase 1A naming contract

## 2026-01-31
- Old name: AcquireStorage.storeFile(...) (without packId)
- New name: AcquireStorage.storeFile(..., packId) with invariant checks
- Reason: require packId for catalogs, forbid for gamesystems, and support deterministic pack-scoped catalog storage layout
- Approval reference: user approval (Phase 1A Step 4)

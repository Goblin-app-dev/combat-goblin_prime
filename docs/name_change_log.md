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

## 2026-01-30
- Old name: N/A
- New name: Diagnostic
- Reason: Legalize approved public type referenced by `RawPackBundle.acquireDiagnostics`.
- Approval reference: M1 Acquire approved names proposal update.

## 2026-02-01
- Old name: N/A
- New name: packId
- Reason: Capture pack storage identity in AcquireStorage storeFile signature.
- Approval reference: M1 Acquire approved names proposal update.

## 2026-01-31
- Old name: AcquireStorage.storeFile(...) (without packId)
- New name: AcquireStorage.storeFile(..., packId)
- Reason: required to support deterministic pack-scoped catalog storage layout
- Approval reference: user approval (Phase 1A Step 4)

## 2026-02-02
- Old name: N/A
- New name: DependencyRecord
- Reason: New model to store version information for dependency catalogs; enables update checking after raw file deletion.
- Approval reference: User approval (Phase 1A workflow enhancement)

## 2026-02-02
- Old name: N/A
- New name: SourceLocator
- Reason: New model to identify upstream source (repo URL, branch) for update checking.
- Approval reference: User approval (Phase 1A workflow enhancement)

## 2026-02-02
- Old name: N/A
- New name: PackManifest
- Reason: New model to persist pack version information; survives dependency deletion; enables update detection.
- Approval reference: User approval (Phase 1A workflow enhancement)

## 2026-02-02
- Old name: AcquireFailure (without missingTargetIds)
- New name: AcquireFailure.missingTargetIds
- Reason: Add list of missing dependency targetIds to enable actionable UI prompts.
- Approval reference: User approval (Phase 1A workflow enhancement)

## 2026-02-02
- Old name: RawPackBundle (without manifest)
- New name: RawPackBundle.manifest
- Reason: Add PackManifest field to output bundle for downstream persistence.
- Approval reference: User approval (Phase 1A workflow enhancement)

## 2026-02-02
- Old name: AcquireService.buildBundle (without source parameter)
- New name: AcquireService.buildBundle(..., source)
- Reason: Add SourceLocator parameter to track upstream source for update checking.
- Approval reference: User approval (Phase 1A workflow enhancement)

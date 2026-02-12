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

## 2026-02-10
- Old name: N/A
- New name: BoundPackBundle, BoundEntry, BoundProfile, BoundCategory, BoundCost, BoundConstraint
- Reason: New M5 Bind entity types for typed interpretation of linked pack data.
- Approval reference: Phase 3 M5 Bind approved names proposal

## 2026-02-10
- Old name: N/A
- New name: BindDiagnostic, BindFailure
- Reason: New M5 Bind diagnostic and error types.
- Approval reference: Phase 3 M5 Bind approved names proposal

## 2026-02-10
- Old name: N/A
- New name: BindService
- Reason: New M5 Bind service for entity binding with entry-root detection.
- Approval reference: Phase 3 M5 Bind approved names proposal

## 2026-02-10
- Old name: N/A
- New name: EvaluateFailure
- Reason: New M6 Evaluate fatal exception for corrupted input or internal bugs. Parallels BindFailure/LinkFailure pattern.
- Approval reference: Phase 4 M6 Evaluate approved output vocabulary

## 2026-02-10
- Old name: N/A
- New name: EvaluationResult, RuleEvaluation, RuleEvaluationOutcome, RuleViolation, ConstraintEvaluation, ConstraintEvaluationOutcome, ConstraintViolation
- Reason: New M6 Evaluate core entity types for rule and constraint evaluation output.
- Approval reference: Phase 4 M6 Evaluate approved output vocabulary

## 2026-02-10
- Old name: N/A
- New name: EvaluationSummary, EvaluationStatistics
- Reason: New M6 Evaluate aggregate summary and metrics types.
- Approval reference: Phase 4 M6 Evaluate approved output vocabulary

## 2026-02-10
- Old name: N/A
- New name: EvaluationNotice, EvaluationWarning
- Reason: New M6 Evaluate diagnostic types for non-fatal issues.
- Approval reference: Phase 4 M6 Evaluate approved output vocabulary

## 2026-02-10
- Old name: N/A
- New name: EvaluationScope, EvaluationApplicability, EvaluationSourceRef, EvaluationContext
- Reason: New M6 Evaluate supporting types for scope, applicability, provenance, and runtime context.
- Approval reference: Phase 4 M6 Evaluate approved output vocabulary

## 2026-02-11
- Old name: EvaluationResult
- New name: EvaluationReport
- Reason: Rename for clarity. "Report" better communicates this is the deterministic output document, distinct from telemetry.
- Approval reference: Phase 4 M6 Evaluate design proposal revision 3

## 2026-02-11
- Old name: EvaluationStatistics
- New name: EvaluationTelemetry
- Reason: Renamed and repurposed. Telemetry is explicitly non-deterministic instrumentation data (timing, etc.), excluded from equality comparisons.
- Approval reference: Phase 4 M6 Evaluate design proposal revision 3

## 2026-02-11
- Old name: RuleEvaluation, RuleEvaluationOutcome, RuleViolation, EvaluationApplicability, EvaluationContext
- New name: (same, but status changed to RESERVED for M7+)
- Reason: Rule evaluation deferred to M7. These names are approved but M6 does NOT produce these types.
- Approval reference: Phase 4 M6 Evaluate design proposal revision 3

## 2026-02-12 (M7 Applicability Rev 2 — APPROVED)
- Old name: N/A
- New name: ApplicabilityState, ApplicabilityResult, ConditionEvaluation, ConditionGroupEvaluation
- Reason: New M7 Applicability core types for tri-state condition evaluation (applies/skipped/unknown).
- Approval reference: Phase 5 M7 Applicability design proposal Rev 2 (approved 2026-02-12)

## 2026-02-12 (M7 Applicability Rev 2 — APPROVED)
- Old name: N/A
- New name: ApplicabilityDiagnostic, ApplicabilityFailure
- Reason: New M7 Applicability diagnostic and error types.
- Approval reference: Phase 5 M7 Applicability design proposal Rev 2 (approved 2026-02-12)

## 2026-02-12 (M7 Applicability Rev 2 — APPROVED)
- Old name: N/A
- New name: ApplicabilityService
- Reason: New M7 Applicability service with evaluate() and evaluateMany() methods.
- Approval reference: Phase 5 M7 Applicability design proposal Rev 2 (approved 2026-02-12)

## 2026-02-12 (M7 Applicability Rev 2 — APPROVED)
- Old name: N/A
- New name: UNKNOWN_CONDITION_TYPE, UNKNOWN_CONDITION_SCOPE_KEYWORD, UNKNOWN_CONDITION_FIELD_KEYWORD, UNRESOLVED_CONDITION_SCOPE_ID, UNRESOLVED_CONDITION_FIELD_ID, UNRESOLVED_CHILD_ID, SNAPSHOT_DATA_GAP_COSTS, SNAPSHOT_DATA_GAP_CHILD_SEMANTICS, SNAPSHOT_DATA_GAP_CATEGORIES, SNAPSHOT_DATA_GAP_FORCE_BOUNDARY
- Reason: New M7 Applicability diagnostic codes (10 codes total).
- Approval reference: Phase 5 M7 Applicability design proposal Rev 2 (approved 2026-02-12)

## 2026-02-12 (M7 Applicability Rev 3 — Implementation Fixes)
- Old name: ApplicabilityResult (without diagnostics field)
- New name: ApplicabilityResult.diagnostics
- Reason: Attach diagnostics per-result instead of mutable service state. Enables callers (voice/search) to access diagnostics without depending on service internal state.
- Approval reference: Phase 5 M7 Applicability implementation review fixes (2026-02-12)

## 2026-02-12 (M8 Modifiers Rev 2 — FROZEN)
- Old name: N/A
- New name: ModifierValue, IntModifierValue, DoubleModifierValue, StringModifierValue, BoolModifierValue
- Reason: New M8 Modifiers type-safe variant wrapper for modifier values. Replaces dynamic with explicit type discrimination.
- Approval reference: Phase 6 M8 Modifiers names proposal Rev 2 (frozen 2026-02-12)

## 2026-02-12 (M8 Modifiers Rev 2 — FROZEN)
- Old name: N/A
- New name: FieldKind
- Reason: New M8 enum disambiguating field namespace (characteristic, cost, constraint, metadata) for modifier targets.
- Approval reference: Phase 6 M8 Modifiers names proposal Rev 2 (frozen 2026-02-12)

## 2026-02-12 (M8 Modifiers Rev 2 — FROZEN)
- Old name: N/A
- New name: ModifierTargetRef
- Reason: New M8 reference type for modifier targets with field namespace disambiguation (targetId + field + fieldKind).
- Approval reference: Phase 6 M8 Modifiers names proposal Rev 2 (frozen 2026-02-12)

## 2026-02-12 (M8 Modifiers Rev 2 — FROZEN)
- Old name: N/A
- New name: ModifierOperation, ModifierResult, ModifierDiagnostic, ModifierFailure
- Reason: New M8 Modifiers core types for operation representation, result output, diagnostics, and fatal exceptions.
- Approval reference: Phase 6 M8 Modifiers names proposal Rev 2 (frozen 2026-02-12)

## 2026-02-12 (M8 Modifiers Rev 2 — FROZEN)
- Old name: N/A
- New name: ModifierService
- Reason: New M8 Modifiers service with applyModifiers() and applyModifiersMany() methods.
- Approval reference: Phase 6 M8 Modifiers names proposal Rev 2 (frozen 2026-02-12)

## 2026-02-12 (M8 Modifiers Rev 2 — FROZEN)
- Old name: N/A
- New name: UNKNOWN_MODIFIER_TYPE, UNKNOWN_MODIFIER_FIELD, UNKNOWN_MODIFIER_SCOPE, UNRESOLVED_MODIFIER_TARGET, INCOMPATIBLE_VALUE_TYPE, UNSUPPORTED_TARGET_KIND, UNSUPPORTED_TARGET_SCOPE
- Reason: New M8 Modifiers diagnostic codes (7 codes total).
- Approval reference: Phase 6 M8 Modifiers names proposal Rev 2 (frozen 2026-02-12)

## 2026-02-12 (Orchestrator v1 — FROZEN)
- Old name: N/A
- New name: OrchestratorRequest, OrchestratorOptions
- Reason: New Orchestrator input types for coordinator pattern.
- Approval reference: Orchestrator v1 names proposal (frozen 2026-02-12)

## 2026-02-12 (Orchestrator v1 — FROZEN)
- Old name: N/A
- New name: ViewBundle, ViewSelection
- Reason: New Orchestrator output types for unified view of evaluated roster.
- Approval reference: Orchestrator v1 names proposal (frozen 2026-02-12)

## 2026-02-12 (Orchestrator v1 — FROZEN)
- Old name: N/A
- New name: OrchestratorDiagnostic, DiagnosticSource
- Reason: New Orchestrator diagnostic wrapper with source module attribution.
- Approval reference: Orchestrator v1 names proposal (frozen 2026-02-12)

## 2026-02-12 (Orchestrator v1 — FROZEN)
- Old name: N/A
- New name: OrchestratorService, OrchestratorFailure
- Reason: New Orchestrator coordinator service and fatal exception type.
- Approval reference: Orchestrator v1 names proposal (frozen 2026-02-12)

## 2026-02-12 (Orchestrator v1 — FROZEN)
- Old name: N/A
- New name: SELECTION_NOT_IN_BUNDLE, EVALUATION_ORDER_VIOLATION
- Reason: New Orchestrator-specific diagnostic codes (2 codes total).
- Approval reference: Orchestrator v1 names proposal (frozen 2026-02-12)

## 2026-02-12 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexBundle, UnitDoc, WeaponDoc, RuleDoc, CharacteristicDoc
- Reason: New M9 Index-Core document types for search index.
- Approval reference: M9 Index-Core names proposal Rev 1

## 2026-02-12 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexDiagnostic
- Reason: New M9 Index-Core diagnostic type.
- Approval reference: M9 Index-Core names proposal Rev 1

## 2026-02-12 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexService
- Reason: New M9 Index-Core service for building search index.
- Approval reference: M9 Index-Core names proposal Rev 1

## 2026-02-12 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: MISSING_NAME, DUPLICATE_DOC_KEY, UNKNOWN_PROFILE_TYPE, EMPTY_CHARACTERISTICS, TRUNCATED_DESCRIPTION
- Reason: New M9 Index-Core diagnostic codes (5 codes total).
- Approval reference: M9 Index-Core names proposal Rev 1

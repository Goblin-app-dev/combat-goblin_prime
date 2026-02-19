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

## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexBundle, UnitDoc, WeaponDoc, RuleDoc
- Reason: New M9 Index-Core document types for search index (3 doc kinds only).
- Approval reference: M9 Index-Core names proposal Rev 2

## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: CharacteristicDoc
- New name: IndexedCharacteristic
- Reason: Demoted from standalone doc to field type on UnitDoc/WeaponDoc per reviewer feedback.
- Approval reference: M9 Index-Core names proposal Rev 2

## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexDiagnostic
- Reason: New M9 Index-Core diagnostic type.
- Approval reference: M9 Index-Core names proposal Rev 2

## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: IndexService
- Reason: New M9 Index-Core service for building search index.
- Approval reference: M9 Index-Core names proposal Rev 2

## 2026-02-13 (M9 Index-Core — PROPOSED)
- Old name: N/A
- New name: MISSING_NAME, DUPLICATE_DOC_KEY, DUPLICATE_RULE_CANONICAL_KEY, UNKNOWN_PROFILE_TYPE, EMPTY_CHARACTERISTICS, TRUNCATED_DESCRIPTION, LINK_TARGET_MISSING
- Reason: New M9 Index-Core diagnostic codes (7 codes total, +2 from Rev 1).
- Approval reference: M9 Index-Core names proposal Rev 2

## 2026-02-17 (Phase 11B — Multi-Catalog — PROPOSAL)
- Old name: N/A
- New name: kMaxSelectedCatalogs
- Reason: New constant defining maximum user-selected primary catalogs (value: 3).
- Approval reference: Phase 11B Multi-Catalog names proposal

## 2026-02-17 (Phase 11B — GitHub Sync — PROPOSAL)
- Old name: N/A
- New name: TrackedFile, SessionPackState, RepoSyncState, GitHubSyncState, GitHubSyncStateService
- Reason: New GitHub sync state types for blob SHA tracking and update detection. Stored separately from M1 engine metadata.
- Approval reference: Phase 11B Multi-Catalog names proposal

## 2026-02-17 (Phase 11B — Multi-Pack Search — PROPOSAL)
- Old name: N/A
- New name: MultiPackSearchHit, MultiPackSearchResult, MultiPackSearchService
- Reason: New multi-pack search types for deterministic cross-bundle search with merge and deduplication.
- Approval reference: Phase 11B Multi-Catalog names proposal

## 2026-02-17 (Phase 11B — BsdResolver Extensions — PROPOSAL)
- Old name: N/A
- New name: RepoTreeEntry, RepoTreeResult, fetchRepoTree()
- Reason: BsdResolverService extensions for GitHub Trees API with blob SHA tracking.
- Approval reference: Phase 11B Multi-Catalog names proposal

## 2026-02-17 (Phase 11B — ImportSessionController Extensions — PROPOSAL)
- Old name: primaryCatalogFile, rawBundle, boundBundle, indexBundle, setPrimaryCatalogFile()
- New name: selectedCatalogs, rawBundles, boundBundles, indexBundles, setSelectedCatalogs() (with deprecated aliases preserved)
- Reason: Multi-catalog support: single → multiple. Legacy single accessors deprecated but preserved for backward compatibility.
- Approval reference: Phase 11B Multi-Catalog names proposal

## 2026-02-17 (Phase 11B — SearchScreen Extensions — PROPOSAL)
- Old name: SearchScreen.indexBundle
- New name: SearchScreen.indexBundles, SearchScreen.bundleOrder, SearchScreen.single(), SearchScreen.multi()
- Reason: Multi-pack search support: single bundle → multiple bundles with deterministic ordering. Legacy indexBundle deprecated.
- Approval reference: Phase 11B Multi-Catalog names proposal

## 2026-02-17 (Phase 11B — GitHub Catalog Picker — APPROVED)
- Old name: FilePickerView
- New name: GitHubCatalogPickerView
- Reason: Replace local file picker with GitHub-primary import flow. GitHubCatalogPickerView fetches repo tree, auto-selects .gst, shows .cat checkbox list (max 3), triggers importFromGitHub(). FilePickerView class deprecated; file kept at same path.
- Approval reference: User approval (Phase 11B GitHub Catalog Picker, 2026-02-17)

## 2026-02-17 (Phase 11B — GitHub Catalog Picker — APPROVED)
- Old name: N/A
- New name: loadRepoCatalogTree()
- Reason: New ImportSessionController method. Wraps _bsdResolver.fetchRepoTree() for view use. Returns sorted RepoTreeResult?. Idempotent; no ImportStatus change.
- Approval reference: User approval (Phase 11B GitHub Catalog Picker, 2026-02-17)

## 2026-02-17 (Phase 11B — GitHub Catalog Picker — APPROVED)
- Old name: N/A
- New name: importFromGitHub()
- Reason: New ImportSessionController method. Downloads .gst + .cat files via fetchFileByPath(), pre-populates dependencies, calls attemptBuild(). Enforces 3-catalog limit. Deterministic failure policy: fail-all on download failure; stable-sorted resolvingDeps on dep failure.
- Approval reference: User approval (Phase 11B GitHub Catalog Picker, 2026-02-17)

## 2026-02-17 (Phase 11B — GitHub Catalog Picker — APPROVED)
- Old name: N/A (previously private _fetchFileContent())
- New name: fetchFileByPath()
- Reason: Expose public download method on BsdResolverService for use by importFromGitHub(). Returns raw bytes only; no storage side effects.
- Approval reference: User approval (Phase 11B GitHub Catalog Picker, 2026-02-17)

## 2026-02-18 (Phase 11C — Per-Slot UI Model — APPROVED)
- Old name: kMaxSelectedCatalogs = 3
- New name: kMaxSelectedCatalogs = 2
- Reason: Demo limitation. Reducing from 3 to 2 slots for initial release to bound memory/network usage. Per-slot architecture is designed for arbitrary N.
- Approval reference: Phase 11C review feedback (2026-02-18)

## 2026-02-18 (Phase 11C — Per-Slot UI Model — APPROVED)
- Old name: N/A
- New name: SlotStatus
- Reason: New enum for per-slot lifecycle: empty, fetching, ready, building, loaded, error.
- Approval reference: Phase 11C review feedback (2026-02-18)

## 2026-02-18 (Phase 11C — Per-Slot UI Model — APPROVED)
- Old name: N/A
- New name: SlotState (with missingTargetIds field)
- Reason: New immutable data class for per-slot state snapshot. missingTargetIds field (sorted) surfaces unresolved dependency IDs when pipeline encounters AcquireFailure.
- Approval reference: Phase 11C review feedback (2026-02-18)

## 2026-02-18 (Phase 11C — Update Detection — APPROVED)
- Old name: bool _updateAvailable (controller internal)
- New name: UpdateCheckStatus enum (unknown / upToDate / updatesAvailable / failed)
- Reason: bool conflated "not checked" and "no updates found". Tri-state (+ failed) required to avoid implying upToDate when check hasn't run or failed.
- Approval reference: Phase 11C review feedback (2026-02-18)

## 2026-02-18 (Phase 11C — ImportSessionController — APPROVED)
- Old name: N/A
- New name: fetchAndSetGameSystem(), assignCatalogToSlot(), loadSlot(), clearSlot(), loadAllReadySlots(), checkForUpdatesAsync(), checkForUpdates(), initPersistenceAndRestore()
- Reason: New controller methods for per-slot lifecycle, game system download, and update check.
- Approval reference: Phase 11C review feedback (2026-02-18)

## 2026-02-18 (Phase 11C — Navigation — APPROVED)
- Old name: ImportWizardScreen, SearchScreen (standalone)
- New name: AppShell (Drawer + Home/Downloads), HomeScreen (search + slot status bar), DownloadsScreen (slot panels + catalog picker)
- Reason: Replace single-flow wizard with persistent shell navigation. Search is always accessible; catalog management moved to Downloads tab.
- Approval reference: Phase 11C review feedback (2026-02-18)

## 2026-02-18 (Phase 11C — SourceLocator re-export — APPROVED)
- Old name: SourceLocator (internal to m1_acquire; consumers must import directly)
- New name: SourceLocator re-exported from import_session_controller.dart
- Reason: UI consumers that construct SourceLocator should not need to reach into m1_acquire engine internals. Dependency direction preserved: UI → controller → m1_acquire.
- Approval reference: Phase 11C review feedback (2026-02-18)

## 2026-02-18 (Phase 12 — Voice Integration — PROPOSAL)
- Old name: N/A
- New name: VoiceSessionState (enum: idle, listening, wakeDetected, capturingCommand, transcribing, canonicalizing, executing, speaking, followUpWindow)
- Reason: New voice state machine enum for hands-free voice lifecycle. Deterministic transitions with cooldown rules.
- Approval reference: Phase 12 Voice Integration proposal (2026-02-18)

## 2026-02-18 (Phase 12 — Voice Integration — PROPOSAL)
- Old name: N/A
- New name: DomainCanonicalizer
- Reason: New service mapping untrusted STT transcript to pack entities via M9 normalization + deterministic fuzzy matching. Core differentiator for 40k vocabulary reliability.
- Approval reference: Phase 12 Voice Integration proposal (2026-02-18)

## 2026-02-18 (Phase 12 — Voice Integration — PROPOSAL)
- Old name: N/A
- New name: VoiceQueryResolution
- Reason: New output model from DomainCanonicalizer containing canonicalDocId, confidence, originalTranscript, canonicalText.
- Approval reference: Phase 12 Voice Integration proposal (2026-02-18)

## 2026-02-18 (Phase 12 — Voice Integration — PROPOSAL)
- Old name: N/A
- New name: VoiceMode (enum: search, assistant)
- Reason: New enum for user-selected voice interaction mode. Search navigates to result; assistant speaks answer.
- Approval reference: Phase 12 Voice Integration proposal (2026-02-18)

## 2026-02-18 (Phase 12 — Voice Integration — PROPOSAL)
- Old name: N/A
- New name: PronunciationPreprocessor
- Reason: New deterministic substitution map applied before TTS for domain term pronunciation. Does not affect queries.
- Approval reference: Phase 12 Voice Integration proposal (2026-02-18)

## 2026-02-18 (Phase 12 — Voice Integration — PROPOSAL)
- Old name: N/A
- New name: VoiceIntent (assistant mode intents v1)
- Reason: New bounded deterministic intent type for assistant mode. Includes unit ability query, rule read, stat query, navigation commands. No LLM required.
- Approval reference: Phase 12 Voice Integration proposal (2026-02-18)

## 2026-02-18 (Phase 12 — Voice Integration — PROPOSAL)
- Old name: N/A
- New name: STT lane names (PlatformSttAdapter, OfflineSttAdapter), TTS adapter name (TtsAdapter)
- Reason: Proposed adapter names for dual-lane STT (platform online + Whisper offline) and system TTS. Unified interface contracts. Final names pending Step 0B approval.
- Approval reference: Phase 12 Voice Integration proposal (2026-02-18)

## 2026-02-19 (Phase 11D — Faction Picker — APPROVED)
- Old name: N/A
- New name: FactionOption
- Reason: New value type representing a selectable faction in the faction picker. Fields: displayName, primaryPath, libraryPaths. Excludes library catalog rows from the picker list.
- Approval reference: Phase 11 UI Behavior Tweak Proposal (2026-02-19)

## 2026-02-19 (Phase 11D — Faction Picker — APPROVED)
- Old name: N/A
- New name: FactionPickerScreen
- Reason: New dedicated screen for picking a faction for a slot. Highlight-and-replace model (no second confirmation). Shows searchable faction list; "Clear" action in AppBar.
- Approval reference: Phase 11 UI Behavior Tweak Proposal (2026-02-19)

## 2026-02-19 (Phase 11D — Faction Picker — APPROVED)
- Old name: N/A
- New name: availableFactions()
- Reason: New ImportSessionController method. Derives sorted List<FactionOption> from RepoTreeResult. Excludes library catalogs. Strips known prefix segments for displayName. Stable sort: ascending by displayName.
- Approval reference: Phase 11 UI Behavior Tweak Proposal (2026-02-19)

## 2026-02-19 (Phase 11D — Faction Picker — APPROVED)
- Old name: N/A
- New name: loadFactionIntoSlot()
- Reason: New ImportSessionController method. One-tap import flow: fetch primary → pre-flight scan → fetch deps → mark ready → call loadSlot() immediately. Uses faction.displayName as the slot catalogName.
- Approval reference: Phase 11 UI Behavior Tweak Proposal (2026-02-19)

## 2026-02-19 (Phase 11D — Faction Picker — APPROVED)
- Old name: N/A
- New name: gameSystemDisplayName
- Reason: New ImportSessionController getter. Short name for loaded game system, derived from gameSystemFile.fileName by stripping .gst extension.
- Approval reference: Phase 11 UI Behavior Tweak Proposal (2026-02-19)

## 2026-02-19 (Phase 11D — Faction Picker — APPROVED)
- Old name: N/A
- New name: cachedRepoTree
- Reason: New ImportSessionController getter exposing _cachedRepoTree (most recent loadRepoCatalogTree() result). Allows FactionPickerScreen and DownloadsScreen to derive faction lists without re-fetching.
- Approval reference: Phase 11 UI Behavior Tweak Proposal (2026-02-19)

## 2026-02-19 (Phase 11D — Faction Picker — APPROVED)
- Old name: DownloadsScreen — editable URL field always shown
- New name: DownloadsScreen — read-only URL display with "Change" button; default URL preloaded (BSData/wh40k-10e); auto-fetch on mount; slot panel tap → FactionPickerScreen
- Reason: Reduce friction and user error. Repo URL is secondary; slot tap drives faction selection. Default repo eliminates manual URL entry for the primary use case.
- Approval reference: Phase 11 UI Behavior Tweak Proposal (2026-02-19)

## 2026-02-19 (Phase 11D — Faction Picker — APPROVED)
- Old name: _CatalogPicker (inline file list inside slot panel)
- New name: (removed) — slot panel tap opens FactionPickerScreen instead
- Reason: Faction picker screen provides scroll room, search, and highlight-and-replace without cluttering the slot panel.
- Approval reference: Phase 11 UI Behavior Tweak Proposal (2026-02-19)

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

## 2026-02-19 (Phase 11E — Faction Picker Fix + Downloads UX — APPROVED)
- Old name: availableFactions() — substring-match algorithm (library matched to primary by displayName.contains)
- New name: availableFactions() — group-by algorithm (strip category prefix + "Library - " → group key → primary = lex-smallest non-library, libraryPaths = all library files in group)
- Reason: Substring matching failed to consolidate all factions (e.g. Chaos Knights, Imperial Knights, Daemons showed as two rows). Group-by is deterministic and handles all patterns uniformly.
- Approval reference: Phase 11 UI Tweaks Additions and Corrections (2026-02-19)

## 2026-02-19 (Phase 11E — Downloads UX — APPROVED)
- Old name: N/A
- New name: _loadGameSystem() (view-local method in DownloadsScreen)
- Reason: New handler for "Load Game System Data" button. Replaces the auto-select .gst flow. User-triggered download; SHA-aware; shows picker if multiple .gst files.
- Approval reference: Phase 11 UI Tweaks Additions and Corrections (2026-02-19)

## 2026-02-19 (Phase 11E — Downloads UX — APPROVED)
- Old name: N/A
- New name: _gstLoadedBlobSha (view-local state in DownloadsScreen)
- Reason: Tracks the blob SHA of the game system at load time for SHA-based update detection in the "Load Game System Data" button.
- Approval reference: Phase 11 UI Tweaks Additions and Corrections (2026-02-19)

## 2026-02-19 (Phase 11E — Downloads UX — APPROVED)
- Old name: _SlotPanel.onLoad + "Load" button + "Load All Ready Slots" button
- New name: (removed)
- Reason: Slots are now auto-loaded by loadFactionIntoSlot(). Users never manually trigger pipeline. Load/Load All buttons removed from Downloads screen.
- Approval reference: Phase 11 UI Tweaks Additions and Corrections (2026-02-19)

## 2026-02-19 (Phase 11E — Downloads UX — APPROVED)
- Old name: _GameSystemSection (auto-list of .gst files for selection)
- New name: _LoadGameSystemButton (single user-triggered button; SHA-aware; shows picker dialog for multi-.gst repos)
- Reason: Replace list-style selector with a single-tap button that handles all states (not loaded / loaded+up-to-date / loaded+update-available). Matches "one button" spec requirement.
- Approval reference: Phase 11 UI Tweaks Additions and Corrections (2026-02-19)

## 2026-02-20 (Phase 11E — Persistence + Fast Boot — APPROVED)
- Old name: N/A
- New name: PersistedSession.schemaVersion
- Reason: New int field for format version migration. Value 2 for 11E snapshots; legacy sessions without field treated as version 1.
- Approval reference: Phase 11E Persistence + Fast Boot name proposal (2026-02-20)

## 2026-02-20 (Phase 11E — Persistence + Fast Boot — APPROVED)
- Old name: N/A
- New name: PersistedSession.gameSystemDisplayName
- Reason: New String? field storing human-readable game system label for instant boot display without loading file bytes.
- Approval reference: Phase 11E Persistence + Fast Boot name proposal (2026-02-20)

## 2026-02-20 (Phase 11E — Persistence + Fast Boot — APPROVED)
- Old name: N/A
- New name: PersistedSession.sourceKey
- Reason: New String? field storing SourceLocator.sourceKey for boot-time SourceLocator reconstruction and GitHubSyncStateService lookup.
- Approval reference: Phase 11E Persistence + Fast Boot name proposal (2026-02-20)

## 2026-02-20 (Phase 11E — Persistence + Fast Boot — APPROVED)
- Old name: N/A
- New name: PersistedCatalog.factionDisplayName
- Reason: New String? field storing faction label (e.g. "Tyranids") for instant boot display.
- Approval reference: Phase 11E Persistence + Fast Boot name proposal (2026-02-20)

## 2026-02-20 (Phase 11E — Persistence + Fast Boot — APPROVED)
- Old name: N/A
- New name: PersistedCatalog.primaryCatRepoPath
- Reason: New String? field storing repo-relative .cat path for re-download fallback.
- Approval reference: Phase 11E Persistence + Fast Boot name proposal (2026-02-20)

## 2026-02-20 (Phase 11E — Persistence + Fast Boot — APPROVED)
- Old name: N/A
- New name: PersistedCatalog.dependencyStoredPaths
- Reason: New Map<String, String>? field mapping targetId → M1 local path for offline dependency reload.
- Approval reference: Phase 11E Persistence + Fast Boot name proposal (2026-02-20)

## 2026-02-20 (Phase 11E — Persistence + Fast Boot — APPROVED)
- Old name: SessionPersistenceService._sessionFileName = 'last_session.json'
- New name: SessionPersistenceService._snapshotFileName = 'app_snapshot.json'
- Reason: Storage file renamed to reflect evolved snapshot format. Migration fallback reads last_session.json if app_snapshot.json absent.
- Approval reference: Phase 11E Persistence + Fast Boot name proposal (2026-02-20)

## 2026-02-26 (Phase 12A — Voice Seam Extraction — APPROVED)
- Old name: N/A
- New name: SpokenVariant
- Reason: New voice model type. One M10 SearchHit enriched with sourceSlotId and tieBreakKey. Used as the leaf node in voice grouping.
- Approval reference: Phase 12A Voice Seam Proposal (2026-02-26)

## 2026-02-26 (Phase 12A — Voice Seam Extraction — APPROVED)
- Old name: N/A
- New name: SpokenEntity
- Reason: New voice model type. Groups SpokenVariants sharing the same canonicalKey within the same slot. primaryVariant = variants.first (deterministic auto-pick).
- Approval reference: Phase 12A Voice Seam Proposal (2026-02-26)

## 2026-02-26 (Phase 12A — Voice Seam Extraction — APPROVED)
- Old name: N/A
- New name: VoiceSearchResponse
- Reason: New output model from VoiceSearchFacade. Contains entities, diagnostics, spokenSummary (pure function, no timestamps).
- Approval reference: Phase 12A Voice Seam Proposal (2026-02-26)

## 2026-02-26 (Phase 12A — Voice Seam Extraction — APPROVED)
- Old name: N/A
- New name: VoiceSelectionSession
- Reason: New in-memory cursor over List<SpokenEntity>. Clamped cycling (no wrap). Supports nextVariant, previousVariant, nextEntity, previousEntity, chooseEntity, reset.
- Approval reference: Phase 12A Voice Seam Proposal (2026-02-26)

## 2026-02-26 (Phase 12A — Voice Seam Extraction — APPROVED)
- Old name: N/A
- New name: SearchResultGrouper
- Reason: New pure function service. Groups M10 SearchHit results into SpokenEntity groups by canonicalKey within a single slot. No state, no side effects.
- Approval reference: Phase 12A Voice Seam Proposal (2026-02-26)

## 2026-02-26 (Phase 12A — Voice Seam Extraction — APPROVED)
- Old name: N/A
- New name: VoiceSearchFacade
- Reason: New app-layer voice search entrypoint. Calls StructuredSearchService per slot bundle (bypasses MultiPackSearchService.search). Returns VoiceSearchResponse. Provides suggest() delegating to MultiPackSearchService.suggest().
- Approval reference: Phase 12A Voice Seam Proposal (2026-02-26)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: VoiceStopReason
- Reason: Closed enum (8 values) for the reason a listen session ended. Always set when leaving ListeningState. No unknown/other values.
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: VoiceListenMode
- Reason: Enum for user-selected interaction mode: pushToTalkSearch, handsFreeAssistant.
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: VoiceListenTrigger
- Reason: Enum for the originator of beginListening: pushToTalk, wakeWord. Enables explainable log diagnostics (Skill 11).
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: VoiceRuntimeState, IdleState, ArmingState, ListeningState, ProcessingState, ErrorState
- Reason: Sealed class hierarchy for listen state machine. Carries attached data (mode, trigger, reason, message) per state.
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: VoiceRuntimeEvent, WakeDetected, ListeningBegan, ListeningEnded, StopRequested, ErrorRaised, RouteChanged, PermissionDenied, AudioFocusDenied
- Reason: Sealed class hierarchy for controller event stream. Eight concrete subtypes with attached data.
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: AudioFrameStream
- Reason: typedef AudioFrameStream = Stream<Uint8List>. Placeholder for mic frame delivery to future STT engines.
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: WakeEvent, WakeWordDetector
- Reason: WakeEvent is a named data class (phrase, confidence?). WakeWordDetector is an abstract interface with stream-based API for Sherpa plug-in (Phase 12C).
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: MicPermissionGateway, AudioFocusGateway, AudioRouteObserver
- Reason: Injectable gateway interfaces for platform audio I/O. Real adapters deferred to Phase 12C. Enables deterministic unit tests without platform dependencies.
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: VoiceRuntimeController
- Reason: State machine owner for mic lifecycle. Injected dependencies, closed enums, stream-based events, ValueNotifier state. Public API: state, events, mode, modeNotifier, onAudioCaptured, setMode(), beginListening(), endListening(), dispose().
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: FakeWakeWordDetector, FakeMicPermissionGateway, FakeAudioFocusGateway, FakeAudioRouteObserver
- Reason: Testing helpers in lib/voice/runtime/testing/. Configurable fakes with simulation methods for deterministic contract tests.
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-27 (Phase 12B — Audio Runtime — APPROVED)
- Old name: N/A
- New name: VoiceControlBar
- Reason: Minimal UI widget at lib/ui/voice/voice_control_bar.dart. Mode toggle + PTT button. Observes VoiceRuntimeController; no direct mic logic in widget (Skill 06).
- Approval reference: Phase 12B Audio Runtime Proposal (2026-02-27)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: N/A
- New name: AudioCaptureGateway, PlatformAudioCaptureGateway, FakeAudioCaptureGateway
- Reason: Platform mic capture gateway. Streams canonical PCM16/16kHz/mono frames. `record` package in real adapter; pushFrame-based fake for tests.
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: N/A
- New name: SpeechToTextEngine, OfflineSpeechToTextEngine, OnlineSpeechToTextEngine
- Reason: Batch STT interface and implementations. Offline: sherpa_onnx transducer, lazy-init, VOICE PERF logging. Online: stub (Phase 12D), always throws UnsupportedError.
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: N/A
- New name: TextCandidate
- Reason: STT output model at lib/voice/models/text_candidate.dart. Engine fills text/confidence/isFinal; controller overwrites sessionId/mode/trigger with actual session context.
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: N/A
- New name: VoiceSettings, VoiceSettingsService
- Reason: Persisted voice preferences (lastMode, onlineSttEnabled, wakeWordEnabled, maxCaptureDurationSeconds). Atomic-write JSON pattern identical to SessionPersistenceService.
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: N/A
- New name: PlatformWakeWordDetector
- Reason: Sherpa ONNX KWS adapter. Keywords in BPE token space. Async factory with graceful degradation on missing model assets.
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: N/A
- New name: VoicePlatformFactory
- Reason: Synchronous factory for all platform adapters. Real on Android/iOS; no-op fakes on Web/Desktop. Wake-word init async via createWakeWordDetector().
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: PlatformAudioFocusGateway (stub, Phase 12B deferred)
- New name: PlatformAudioFocusGateway (real, audio_session backed)
- Reason: Phase 12C implements real audio_session AVAudioSession/AudioFocus management.
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: PlatformMicPermissionGateway (stub, Phase 12B deferred)
- New name: PlatformMicPermissionGateway (real, permission_handler backed)
- Reason: Phase 12C implements real permission_handler mic permission requests.
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: N/A
- New name: TextCandidateProducedEvent
- Reason: New VoiceRuntimeEvent subtype. Emitted after state transitions to IdleState (Rule A). Carries the TextCandidate produced by the STT engine for the completed session.
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-02-28 (Phase 12C — Real Audio I/O — APPROVED)
- Old name: VoiceStopReason (8 values)
- New name: VoiceStopReason (11 values, +sttFailed, +captureLimitReached, +wakeEngineUnavailable)
- Reason: Phase 12C adds three new stop reasons for STT failure, hard capture limit, and wake engine unavailability. Additive change; backward-compatible.
- Approval reference: Phase 12C Real Audio I/O Proposal (2026-02-28)

## 2026-03-01 (Phase 12D — Voice Understanding — APPROVED)
- Old name: N/A
- New name: VoiceIntentKind, VoiceIntent (sealed), SearchIntent, AssistantQuestionIntent, DisambiguationCommandIntent, UnknownIntent
- Reason: New Phase 12D intent classification hierarchy. Sealed class enables exhaustive switch in coordinator and tests. Four subtypes cover all recognized transcript patterns.
- Approval reference: Phase 12D Voice Understanding Proposal (2026-03-01)

## 2026-03-01 (Phase 12D — Voice Understanding — APPROVED)
- Old name: N/A
- New name: DisambiguationCommand
- Reason: New Phase 12D enum for the four voice navigation commands (next/previous/select/cancel). Recognized by exact string match in VoiceIntentClassifier; multiple surface forms accepted.
- Approval reference: Phase 12D Voice Understanding Proposal (2026-03-01)

## 2026-03-01 (Phase 12D — Voice Understanding — APPROVED)
- Old name: N/A
- New name: SpokenResponsePlan
- Reason: New Phase 12D coordinator output model. Carries primaryText, entities, selectedIndex, followUps, debugSummary. No timestamps. Enables Phase 12E TTS without coordinator rewrite.
- Approval reference: Phase 12D Voice Understanding Proposal (2026-03-01)

## 2026-03-01 (Phase 12D — Voice Understanding — APPROVED)
- Old name: N/A
- New name: VoiceIntentClassifier
- Reason: New Phase 12D stateless service for intent classification. Command match → question heuristic → search default ordering.
- Approval reference: Phase 12D Voice Understanding Proposal (2026-03-01)

## 2026-03-01 (Phase 12D — Voice Understanding — APPROVED)
- Old name: DomainCanonicalizer (Phase 12 proposal, 2026-02-18, not yet implemented)
- New name: DomainCanonicalizer (Phase 12D implementation, lib/voice/understanding/domain_canonicalizer.dart)
- Reason: Phase 12 originally proposed DomainCanonicalizer. Phase 12D implements it with normalized Levenshtein fuzzy matching (threshold ≥ 0.75), 128-char length cap, and stable tie-break.
- Approval reference: Phase 12D Voice Understanding Proposal (2026-03-01)

## 2026-03-01 (Phase 12D — Voice Understanding — APPROVED)
- Old name: N/A
- New name: VoiceAssistantCoordinator
- Reason: New Phase 12D coordinator class. Owns in-memory VoiceSelectionSession for disambiguation. Produces SpokenResponsePlan from transcript + slotBundles + contextHints. Injected with VoiceSearchFacade, VoiceIntentClassifier, DomainCanonicalizer.
- Approval reference: Phase 12D Voice Understanding Proposal (2026-03-01)

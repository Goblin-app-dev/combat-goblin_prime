# Phase 12E — Spoken Output (TTS) Proposal

**Branch context:** `claude/github-catalog-picker-Py9xI`
**Current status:** Phase 12D complete (Voice Understanding + Disambiguation + Spoken Response Plan)
**Primary goal:** Render `SpokenResponsePlan` to audible speech in a deterministic, offline-capable, demo-safe manner.

---

## 1. Scope & Non-Negotiables

### 1.1 Frozen Modules Rule

- **M1–M10 engine modules are FROZEN** unless explicitly authorized.
- **IndexBundle is FROZEN.**
- Do not alter structured search or engine model layers.
- All work for Phase 12E must remain within:
  - `lib/voice/`
  - `lib/ui/home/`
  - `lib/voice/understanding/`
  - `lib/voice/adapters/`
  - `lib/voice/settings/`

### 1.2 Determinism Rule

All voice behavior must be deterministic:
- No timestamps stored in models.
- No nondeterministic ordering.
- Stable tie-break rules.
- Same transcript + same bundles = same result.
- Logging timestamps are allowed.

**Rule A (state transitions):** State must be updated **before** emitting corresponding event.

### 1.3 Voice-First Direction

Spoken output must reinforce the "audio-first assistant" intent:
- Hands-free wake word (existing)
- Offline ASR (existing, pending model files)
- Domain-aware disambiguation (existing)
- **Spoken response output (Phase 12E)**
- Visual UI remains secondary and primarily for validation/debugging

---

## 2. Problem Statement

The system currently produces a deterministic, domain-aware `SpokenResponsePlan` (Phase 12D), but the user experience is incomplete without audible output. Phase 12E adds:
- A platform-abstracted TTS capability
- A deterministic "speech playback" implementation that consumes `SpokenResponsePlan`
- Integration with existing stop funnel and audio focus behavior

---

## 3. Phase 12E Deliverables

### 3.1 New Runtime Interface(s)

Add a platform-agnostic TTS surface under `lib/voice/runtime/`:

- `TextToSpeechEngine` (interface):
  - `Future<void> initialize()` (lazy — must not be called at boot)
  - `Future<void> speak(String text)`
  - `Future<void> stop()`
  - `Future<void> dispose()`
  - Optional: `Stream<TtsEvent>` if needed (avoid unless truly required)

**Determinism note:** TTS side effects are allowed, but the *inputs* must be derived deterministically from `SpokenResponsePlan`.

### 3.2 Platform Adapter Implementation

Under `lib/voice/adapters/` implement platform-backed TTS:
- `PlatformTextToSpeechEngine` (or similar) wired via `voice_platform_factory.dart`

Requirements:
- No runtime downloads
- No network required
- If platform lacks TTS, degrade gracefully (silent mode + UI banner)

### 3.3 Plan Playback Controller

Implement a single responsible unit that converts plan → speech actions:
- Suggested name: `SpokenPlanPlayer` (or `VoiceOutputController`)
- **Location: `lib/voice/runtime/` — owned by the voice runtime layer, not UI.**

**Architectural rule:** No UI widget may own or directly instantiate the `SpokenPlanPlayer`. UI may pass a plan to the coordinator or a voice-owned callback; the controller lives and operates entirely within the voice runtime layer. This ensures future contributors cannot wire TTS directly inside `HomeScreen` or any other widget.

Responsibilities:
- Receive a `SpokenResponsePlan`
- Produce deterministic spoken text sequence:
  - speak `primaryText`
  - optionally speak 0..N `followUps` depending on `VoiceSettings`
- Integrate with stop funnel:
  - Cancel speech immediately on `stop()` / session end / cancel intent
  - Cooperate with audio focus gateway to avoid feedback loops

**Boot rule:** The controller must initialize TTS lazily on first speak. It must never trigger `TextToSpeechEngine.initialize()` synchronously during app boot or controller construction.

### 3.4 Integration Points

The output path must not bypass runtime rules.

**Integration rule:** TTS playback must be mediated through a voice-owned controller (not called directly from UI widgets).

Practical wiring options:
1. `HomeScreen` receives plan → passes to `SpokenPlanPlayer` via voice coordinator callback
2. `VoiceAssistantCoordinator` produces plan → also emits "speak" command via a callback to runtime-owned output controller

**Do not:**
- Call TTS directly from UI without routing through the stop funnel
- Start speech without ensuring state is consistent (Rule A)

### 3.5 Settings

Extend `lib/voice/settings/`:
- Enable/disable spoken output
- Optional: follow-up verbosity (primary only vs primary + follow-ups)
- Optional: speech rate / voice selection (platform-dependent; keep minimal)

Defaults:
- Spoken output enabled for demo builds
- Follow-ups default off unless required for disambiguation clarity

---

## 4. Deterministic Spoken Text Specification

Phase 12E must define a deterministic mapping from plan → spoken text:
- **Primary:** Always speak `primaryText` exactly as provided (no time phrases, no randomness).
- **Follow-ups:** If enabled, speak in list order (`followUps[0..n]`), unchanged.
- **Selected entity mention:** Only if the plan includes a `selectedIndex` AND the coordinator explicitly included a selection confirmation in `primaryText`. Do not invent phrasing at the TTS layer.

**Key constraint:** The TTS layer must not "improve" wording or paraphrase. That belongs in the deterministic plan generation (12D/13).

---

## 5. Audio Focus & Interrupt Policy

The system already contains audio focus abstractions. Phase 12E must define predictable behavior:

- If the app enters a listening session:
  - Stop or duck any ongoing TTS before capturing mic audio (avoid echo)
- If TTS begins while listening:
  - Either stop listening or defer TTS; policy must be explicit and deterministic
- Stop funnel always wins:
  - `cancel`, `select`, explicit stop, or session termination must stop speech immediately

**Concurrency rule (non-negotiable):** At most one spoken output playback may be active at a time. If a new `SpokenResponsePlan` is emitted while speech is in progress, the system must stop current speech immediately and then speak the new plan (no queueing). The speech layer must treat the plan as an immutable snapshot for the entire playback lifecycle and must not observe or rely on mutable list references. TTS initialization must be lazy on first speak and must not block the boot path. All speech start/stop transitions must be mediated through the voice-owned controller and must obey Rule A (state updated before emitting events).

---

## 6. Preconditions / Structural Hardening (Recommended)

These items are either prerequisites or part of 12E implementation. They are included here because they directly affect TTS correctness and determinism.

### 6.1 Freeze `SpokenResponsePlan` List Fields at Construction

Rationale:
- `entities` and `followUps` are `List<>` and can be mutated after construction if references escape.
- TTS playback must not observe mid-session mutation.

Requirement:
- Defensive copy + unmodifiable view at construction time.
- Ensure plan is effectively immutable from consumers.
- **The plan must be treated as an immutable snapshot for the entire playback lifecycle. No component may alter the plan once speech has begun.**

Example pattern (conceptual):
- `final List<SpokenEntity> entities = List.unmodifiable(List.of(inputEntities));`
- `final List<String> followUps = List.unmodifiable(List.of(inputFollowUps));`

**Determinism impact:** Positive (prevents nondeterministic mutation-based behavior).

### 6.2 Add Debug-Time Asserts for Documented Invariants

Rationale:
- The class documents invariants but does not enforce them.
- Silent invalid plans create confusing voice output and UI selection bugs.

Add asserts (debug-only):
- `primaryText.trim().isNotEmpty`
- `followUps` entries are non-empty (optional but recommended)
- If `selectedIndex != null`, it must satisfy:
  - `0 <= selectedIndex < entities.length`
  - If `entities.isEmpty`, then `selectedIndex` must be `null`

**Determinism impact:** Neutral-to-positive (prevents invalid states).

---

## 7. Acceptance Criteria

Phase 12E is complete when:

1. `SpokenResponsePlan` can be spoken end-to-end on at least one target platform.
2. Spoken output is gated by settings and can be disabled.
3. Stop funnel cancels speech immediately and reliably.
4. Audio focus policy is explicit and validated (no mic + TTS echo loops).
5. No changes in frozen engine layers (M1–M10, IndexBundle).
6. Determinism preserved:
   - same transcript + same bundles → same plan → same spoken text sequence
   - no timestamps stored in models
7. Concurrency rule verified: a new plan while speech is active cancels current speech and starts new (no queuing).
8. Tests added:
   - unit tests for plan immutability + asserts behavior (debug path)
   - unit tests for plan → speak sequencing (using a fake TTS engine)
   - tests for stop behavior (speech interrupted on cancel/stop)
   - tests for concurrency rule (new plan preempts active speech)

---

## 8. Risks & Mitigations

- **Risk:** TTS introduces race conditions with listen sessions.
  **Mitigation:** Route all playback through a single controller that obeys runtime state and stop funnel.

- **Risk:** Platform TTS availability varies.
  **Mitigation:** Degrade gracefully (silent mode + UI banner), never crash.

- **Risk:** Boot time increases from eager TTS initialization.
  **Mitigation:** Lazy initialization on first speak; initialization must never be called synchronously during boot or controller construction.

---

## 9. Out of Scope (Explicit)

- Changes to `VoiceSearchFacade` grouping rules (slot-local only stays).
- Any changes to M10 structured search internals.
- Any cross-slot merging behavior.
- Re-architecture of voice runtime state machine.
- "Smarter" answers (belongs to Phase 13 Domain Deepening).

---

## 10. Next Document(s) (Optional)

After Phase 12E:
- Phase 12F (or equivalent): voice interaction stability pass (interrupts, ducking, stress testing)
- Phase 11E optimization pass: boot time reduction
- Phase 13: domain deepening (stats/rule/ability summaries)

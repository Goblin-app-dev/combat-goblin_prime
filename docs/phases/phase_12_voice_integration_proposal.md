# Phase 12 — Voice Integration (Hands-Free, Offline-Capable, Zero Recurring Cost)

**Status:** PROPOSAL (2026-02-18)
**Date:** 2026-02-18
**Depends on:** M9 Index (frozen), M10 Structured Search (frozen)
**Input:** IndexBundle, user voice input
**Output:** Deterministic voice query resolution, spoken responses
**Mutation:** None (no frozen modules modified)

---

## Product Constraints (Non-Negotiable)

- User hands must remain free.
- App is already open.
- "Hey Goblin" is the primary entry point.
- Voice must feel fast and reliable.
- Offline must work.
- No recurring API costs.

Everything below serves those constraints.

---

## System Overview

3-Layer Voice Stack:

```
Wake Layer
  |
STT Layer (Dual-Lane)
  |
Domain Canonicalizer (Deterministic)
  |
SearchFacade / PackManager
  |
TTS Layer
```

No frozen modules are modified.

---

## Wake Word Strategy (MVP to Upgrade Path)

### MVP (Phase 12A)

**Method:** Rolling STT phrase detection for exact phrase: "hey goblin"

**Implementation:**
- Short 2-3 second rolling listen windows
- Exact match after normalization
- Cooldown window after trigger
- Only active when voice toggle enabled
- Only active when app in foreground

**Why this works:**
- Zero training
- Zero cost
- Works online and offline (if offline STT available)
- Easy to ship
- Battery safe

### Phase 12E (Upgrade Later)

Replace wake detection with:
- sherpa_onnx Keyword Spotting model
- Locally trained ONNX model for "Hey Goblin"

Not required for demo or v1.

---

## STT Strategy (Speech-to-Text)

Dual-Lane Logic.

### Online Lane (Primary UX)

**Package:** `speech_to_text`

**Why:**
- Fast partial results
- Native OS optimizations
- Feels instant

**Used for:**
- Wake detection
- Command capture
- Quick queries

### Offline Lane (Fallback)

**Engine:** Whisper.cpp via `whisper_flutter_plus`

**Why Whisper over Sherpa ASR for MVP:**
- Higher domain accuracy
- Strong community validation
- More consistent decoding behavior
- Good for complex Warhammer terms

**Used when:**
- No internet
- Platform STT fails
- User enables "Offline Mode"

### Important: ONE Offline STT Engine

We do NOT run Whisper + Sherpa ASR simultaneously.
Pick one for v1: **Whisper.**
Sherpa remains optional for future optimization.

---

## The Core Differentiator: Domain Canonicalizer

STT output is treated as untrusted noise.

**Example:**
```
"Lemon Russ"
  -> normalize
  -> fuzzy match against loaded IndexBundle canonical keys
  -> resolve to docId: unit:leman_russ
```

### Canonicalizer Responsibilities

1. Normalize transcript using M9 normalization logic
2. Match against:
   - Unit display names
   - Weapon names
   - Rule names
3. Use deterministic fuzzy match
4. Resolve ties deterministically
5. Return:

```dart
VoiceQueryResolution {
  canonicalDocId,
  confidence,
  originalTranscript,
  canonicalText,
}
```

### Why This Works for 40k

We are not trying to train STT to understand Aeldari, Tzeentch, Necron
Overlord, or Mortarion. We let STT approximate. We fix it deterministically
afterward.

This guarantees alignment with:
- M9 index
- M10 search
- Deterministic engine philosophy

---

## TTS Strategy (Text-to-Speech)

### MVP: System TTS

**Package:** `flutter_tts`

**Why:**
- Free
- Offline capable (OS dependent)
- Fast
- Stable
- Small footprint

### Pronunciation Preprocessor

Before speaking:
```dart
text.replaceAll("Tzeentch", "Zeench")
text.replaceAll("Aeldari", "El-dar-ee")
```

Stored in a deterministic dictionary with stable ordering.
Applied before TTS only (does not change underlying queries).

### Optional Upgrade (Phase 12C+)

Piper / VITS neural TTS models via sherpa_onnx.

**Pros:** More natural voice.
**Cons:** 40-80MB download, more CPU, more integration risk.

Becomes: "Enhanced Voice Mode (Optional Download)".
Not required for initial release.

---

## State Machine (Critical for UX)

### States

```
Idle
Listening
WakeDetected
CapturingCommand
Transcribing
Canonicalizing
Executing
Speaking
FollowUpWindow
```

### Rules

- Saying "stop" interrupts TTS.
- Saying "repeat" replays last response.
- If TTS playing and wake detected: interrupt + restart.
- Follow-up window lasts ~5 seconds.

This is what makes it "Siri-like".

---

## Toggle Behavior (User Experience)

User chooses:

| Mode | Result |
|------|--------|
| Search | Navigates to result |
| Assistant | Speaks answer, stays on screen |

Plus:
- Wake Word Enabled (On/Off)
- Push-to-Talk Search Mode vs Conversational Assistant Mode

---

## Cost Analysis

| Component | Cost |
|-----------|------|
| speech_to_text | $0 |
| flutter_tts | $0 |
| Whisper.cpp | $0 |
| Wake via STT | $0 |
| Sherpa KWS (future) | $0 |
| Cloud APIs | Not required |

**Recurring cost: $0**

---

## Storage and Performance

### Whisper Model

- Tiny/Small model recommended
- 40-80MB
- Download on first voice enable
- Stored in app documents directory

### Inference

- Run in background isolate
- Never block UI thread
- Wake detection lightweight
- Command STT heavier but brief

---

## Phase Roadmap

### Phase 12A — Voice Seam + Wake-by-STT (Online Lane First)

**Objective:** Get "Hey Goblin" working hands-free while app is open using
rolling listen phrase detection on platform STT.

**Deliverables:**

1. **Voice session state machine (skeleton)**
   - States: idleListening, wakeDetected, capturingCommand, transcribing,
     canonicalizing, executing, speaking, followUpWindow
   - Deterministic transitions and cooldown rules

2. **Platform STT adapter**
   - Uses `speech_to_text`
   - Supports partial results and rolling windows

3. **Wake detector via STT phrase detection**
   - Rolling listens (2-3 seconds)
   - Exact match on normalized transcript ("hey goblin")
   - Cooldown after trigger (2-3 seconds)

4. **Command capture**
   - After wake, capture next utterance until end-of-speech
   - Produce a final transcript

5. **Minimal UI integration**
   - Voice toggle (Off / Search / Assistant)
   - Audible cue/beep and visible "Listening..." indicator

**Acceptance criteria:**
- Wake triggers reliably with "hey goblin" within <1s (online).
- Rolling listen never blocks UI thread.
- Voice mode toggle works.
- Errors are recoverable (returns to idle listening).

**Tests:**
- Unit tests for normalization + exact phrase detection
- Unit tests for cooldown behavior
- Unit tests for state transition determinism
- Integration test stub: state transitions with mocked STT adapter

**Docs updates:**
- Phase 12 proposal doc: wake-by-STT MVP described as official baseline
- Glossary entries for wake detection, voice state machine concepts

### Phase 12B — Offline STT (Whisper) Fallback Lane

**Objective:** Guarantee voice works without internet, still hands-free.

**Deliverables:**

1. **Offline STT adapter (Whisper.cpp)**
   - Use `whisper_flutter_plus`
   - Model download manager (on-demand):
     - Downloads on first enable of offline
     - Stores in app documents directory
     - Progress observable for UI
   - Runtime inference off UI thread (isolate/native thread)

2. **Lane selection policy**
   - If online and platform STT available: use platform
   - If offline or platform STT fails: use Whisper
   - Optional: offline re-run on command audio when confidence is low (future)

3. **Unified STT interface**
   - State machine does not care which STT lane is used
   - Both adapters expose: `listenWindow()`, `transcribeCommand()`, `cancel()`

**Acceptance criteria:**
- Offline mode: "hey goblin" wake + command transcription works without network.
- Model download is optional/on-demand and does not block boot.
- No hard crash when model missing; user sees "download required" state.

**Tests:**
- Unit tests for lane selection policy
- Unit tests for model download state machine (mocked HTTP/file I/O)

**Docs updates:**
- Phase 12 doc: offline lane defined + model download policy
- Add "Offline Voice Models" section to docs index if needed

### Phase 12C — Domain Canonicalizer (40k Vocabulary Reliability)

**Objective:** Make STT "good enough" for domain terms by deterministically
mapping transcript to pack entities.

**Deliverables:**

1. **DomainCanonicalizer service**
   - Inputs: raw transcript, active pack vocabulary (from loaded IndexBundles),
     mode context (search vs assistant)
   - Outputs: corrected transcript, list of substitutions, confidence score,
     resolved targets (docIds/canonicalKeys) where applicable

2. **Vocabulary source policy (no frozen changes)**
   - Extract from M9 IndexBundle (canonical keys + docs) and M10 query surface
   - Must reuse existing normalization strategy (delegate; no re-implementation)

3. **Deterministic matching**
   - Token windows (1-5 tokens)
   - Scoring: edit distance + token overlap
   - Tie-break chain (stable):
     1. Higher score
     2. Longer span
     3. canonicalKey lexicographic
     4. docId lexicographic

4. **Diagnostics**
   - "Heard vs interpreted" trace
   - Stable ordering and closed diagnostic set

**Acceptance criteria:**
- Common misrecognitions map correctly (fixture tests):
  - "lemon russ" -> correct unit
  - "eldar" -> Aeldari-equivalent in pack (or alias)
  - "save three plus" -> SV=3+ filter (future)
- Deterministic outputs across runs.

**Tests:**
- Canonicalizer unit tests with fixed vocab set
- Determinism tests: same transcript + vocab -> identical output

**Docs updates:**
- Canonicalizer contract, tie-break rules, and diagnostics catalog added to
  Phase 12 doc
- Glossary entries for canonicalizer terms

### Phase 12D — TTS Baseline + Pronunciation Preprocessor

**Objective:** Speak results clearly offline, with acceptable pronunciation for
domain words.

**Deliverables:**

1. **TTS adapter**
   - Use `flutter_tts` baseline
   - Unified contract: `speak(text)`, `stop()`, `setRate()`, etc.

2. **Pronunciation preprocessor**
   - Deterministic substitutions map
   - Stored as a map with stable ordering
   - Applied before TTS only (does not change underlying queries)

3. **Interruption rules**
   - Saying "stop" cancels speech
   - Wake during speaking cancels and restarts capture

**Acceptance criteria:**
- Offline TTS works.
- Stop/interrupt works reliably.
- Pronunciation map improves key terms.

**Tests:**
- Unit tests for pronunciation map application
- Unit tests for TTS interrupt state transitions (mock adapter)

**Docs updates:**
- Phase 12 doc: TTS policy and pronunciation rules

### Phase 12E — Assistant Mode Intents (No LLM Required)

**Objective:** Assistant mode feels conversational while remaining deterministic
and cheap.

**Deliverables:**

1. **Intent router**
   - Mode toggle selects intent pipeline:
     - Search mode: M10 structured search
     - Assistant mode: bounded intents + retrieval

2. **Assistant intents v1**
   - "What are this unit's abilities?"
   - "Read [rule name]"
   - "What's its toughness/save/wounds?"
   - "Next / previous / repeat / stop"

3. **Session memory (bounded)**
   - "Current subject" docId for follow-ups
   - Follow-up window timer (~5s)

**Acceptance criteria:**
- Assistant can answer core questions hands-free
- Follow-ups work ("repeat", "next")
- Remains deterministic; no invented rules

**Tests:**
- Intent parsing unit tests
- Session memory tests

**Docs updates:**
- Phase 12 doc: list of supported intents + non-goals

### Phase 12F — Wake Word Upgrade (Optional, Later)

Replace wake-by-STT with sherpa_onnx KWS only if:
- Battery usage is too high
- False wake rate unacceptable
- Table noise causes too many misses

Includes data collection, training, evaluation gates (FAR/FRR targets).

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Whisper CPU spikes | Use tiny model + isolate |
| Wake false triggers | Cooldown + exact match |
| STT mishears terms | Canonicalizer |
| App size increase | On-demand model download |
| Battery drain | Foreground-only listening |

---

## Integration Notes (UI and Engine)

### UI approach (minimize churn)

- Minimal UI hooks now: toggle mode, indicator + beep, transcription preview
  (optional)
- Do not redesign home UI until voice behavior is stable.

### Engine boundaries

- Canonicalizer consumes IndexBundle vocabulary and produces M10 requests.
- No modifications to frozen modules are required.

---

## Naming + Docs Workflow (Must Happen Before Code)

### Step 0A — Identify where names live

Coder must update the authoritative naming docs first (per Skills 03/13):
- `docs/glossary.md`
- `docs/name_change_log.md`
- This doc: `docs/phases/phase_12_voice_integration_proposal.md`

### Step 0B — Names-first proposals (required)

Before any code, propose and document names for:
- Voice module folder name and barrel
- State machine enums/types
- Canonicalizer service + models
- STT adapters (platform/offline)
- TTS adapter + pronunciation map
- Voice controller facade used by UI

Approve names in a single batch once the coder posts them.

---

## Milestones

### 2-month demo target

Must include:
- Wake-by-STT
- Offline STT fallback (model download)
- Canonicalizer
- Search mode end-to-end
- Assistant mode with 3-5 intents
- TTS baseline + stop/repeat

### 9-month commercial target

- KWS upgrade if needed
- Enhanced TTS option
- Expanded assistant intents and navigation
- Full voice diagnostics + user-facing controls

---

## What Is NOT in Scope

We are NOT:
- Training custom acoustic models
- Building full conversational LLM assistants
- Depending on expensive APIs
- Modifying frozen modules

We ARE:
- Adding a seam layer
- Using deterministic canonicalization
- Keeping control over vocabulary
- Ensuring offline operation

---

## Documents to Update (Checklist for Coder)

1. `docs/phases/phase_12_voice_integration_proposal.md` (this file)
2. `docs/glossary.md` — voice terms
3. `docs/name_change_log.md` — new public names (voice module + services + models)
4. Optional: README.md docs index — Phase 12 doc link and "Voice Models (Offline)" note

---

## Compatibility Note

Phase 12 must function with:
- Index-only mode (primary, via M9 IndexBundle)
- M10 structured search (for query resolution)
- Optional enrichment layer (external, additive only)

Phase 12 must not require orchestrator output for core voice functionality.

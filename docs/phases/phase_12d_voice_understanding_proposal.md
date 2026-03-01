# Phase 12D — Voice Understanding + Disambiguation + Spoken Response Plan
## Approved Names Proposal

**Date:** 2026-03-01
**Status:** APPROVED
**Phase:** 12D — Voice Understanding, Intent Classification, Disambiguation

---

## Context

Phase 12C delivers audio → raw transcript via `TextCandidate`. Phase 12D turns that transcript
into a deterministic, domain-correct "assistant result":

- Canonicalizes noisy STT text into known entities.
- Groups and presents ambiguous matches with voice-navigable session.
- Allows "next / previous / select / cancel" clamped cycling.
- Returns a `SpokenResponsePlan` (text + structure) for future TTS phases.

No UI redesign. Minimal HomeScreen wiring only.

---

## Goals

| # | Goal |
|---|---|
| G1 | Deterministic understanding: same transcript + bundles ⇒ same matched entities, ordering, response plan text. |
| G2 | Disambiguation that works hands-free: `VoiceSelectionSession` cycling with clamp. |
| G3 | Output a `SpokenResponsePlan` — structure only, no audio (TTS comes in Phase 12E). |
| G4 | No frozen-module changes. All new code uses only existing public surfaces. |

---

## Non-Goals (Deferred)

- Real TTS output (Phase 12E/12F).
- Multi-turn chat memory beyond the current selection session.
- Cross-slot entity merging (slot-local only, per Phase 12A decision).
- Cloud STT improvements (kept behind existing settings).

---

## New Public Names

### 2.1 Models

| Name | Kind | File | Description |
|---|---|---|---|
| `VoiceIntentKind` | `enum` | `lib/voice/models/voice_intent.dart` | Four intent kinds: search, assistantQuestion, disambiguationCommand, unknown. |
| `VoiceIntent` | `sealed class` | `lib/voice/models/voice_intent.dart` | Sealed hierarchy of classified intents (see subtypes below). |
| `SearchIntent` | `final class` (extends VoiceIntent) | `lib/voice/models/voice_intent.dart` | User wants to search by entity name. Carries `queryText`. |
| `AssistantQuestionIntent` | `final class` (extends VoiceIntent) | `lib/voice/models/voice_intent.dart` | User is asking about an entity. Carries `queryText`. |
| `DisambiguationCommandIntent` | `final class` (extends VoiceIntent) | `lib/voice/models/voice_intent.dart` | User issued a navigation command. Carries `DisambiguationCommand`. |
| `UnknownIntent` | `final class` (extends VoiceIntent) | `lib/voice/models/voice_intent.dart` | Transcript did not match any pattern. Carries `rawText`. |
| `DisambiguationCommand` | `enum` | `lib/voice/models/disambiguation_command.dart` | Four commands: next, previous, select, cancel. |
| `SpokenResponsePlan` | `final class` | `lib/voice/models/spoken_response_plan.dart` | Coordinator output: primaryText, entities, selectedIndex, followUps, debugSummary. |

### 2.2 Services

| Name | Kind | File | Description |
|---|---|---|---|
| `VoiceIntentClassifier` | `final class` | `lib/voice/understanding/voice_intent_classifier.dart` | Stateless classifier: exact command match → assistant question heuristic → search default. |
| `DomainCanonicalizer` | `final class` | `lib/voice/understanding/domain_canonicalizer.dart` | Normalizes text; fuzzy-matches against contextHints (normalized Levenshtein ≥ 0.75). |
| `VoiceAssistantCoordinator` | `final class` | `lib/voice/understanding/voice_assistant_coordinator.dart` | Coordinator: classify → canonicalize → search → manage VoiceSelectionSession → emit SpokenResponsePlan. |

---

## Invariants

1. **Determinism**: Given the same transcript, contextHints, and slotBundles, `handleTranscript` always returns the same `SpokenResponsePlan` (same `primaryText`, `debugSummary`, `selectedIndex`, entity order).
2. **No timestamps** in `SpokenResponsePlan.debugSummary` or `primaryText`.
3. **Clamp at bounds**: `next` at last entity stays at last entity; `previous` at 0 stays at 0. No wrap.
4. **Session cleared on select/cancel**: After `select` or `cancel`, `_session` is null. Next transcript starts fresh.
5. **No frozen-module changes**: `IndexBundle`, `VoiceSearchFacade`, `VoiceSelectionSession` are used via existing public API only.

---

## Classification Rules

### Disambiguation commands (exact match, trimmed + lowercased)

| Input | Command |
|---|---|
| "next", "next one" | `DisambiguationCommand.next` |
| "previous", "back", "go back" | `DisambiguationCommand.previous` |
| "select", "choose", "confirm" | `DisambiguationCommand.select` |
| "cancel", "stop", "nevermind", "never mind" | `DisambiguationCommand.cancel` |

### Assistant question (leading keyword heuristic)

Detected if trimmed lowercase starts with one of:
`what `, `show `, `tell me`, `describe `, `how many`, `how much`,
`does it`, `can it`, `list `, `get info`, `abilities`, `stats`, `info `, `info about`

### Default

All other non-empty transcripts → `SearchIntent`.

---

## Canonicalization Rules

1. Normalize: lowercase, strip non-word/non-space characters, collapse whitespace, trim.
2. Fuzzy-match normalized form against each contextHint (up to 50 hints, bounded by caller).
3. Algorithm: normalized Levenshtein similarity = `1.0 - distance / max(len_a, len_b)`.
4. Threshold: ≥ 0.75.
5. Tie-break: first matching hint in iteration order (callers control ordering for determinism).
6. Max string length for Levenshtein: 128 characters (performance guard — longer strings return 0.0 similarity).
7. If no hint matches threshold: return normalized form of raw transcript.

---

## Disambiguation Session Behavior

**When session is created:** `VoiceSearchFacade` returns > 1 `SpokenEntity`.

**Plan emitted:**
```
primaryText: "I found N matches. Say 'next' or 'select'."
selectedIndex: 0
followUps: ['next', 'previous', 'select', 'cancel']
```

**Commands during active session:**
- `next` → `session.nextEntity()` (clamp at last) → updated plan
- `previous` → `session.previousEntity()` (clamp at 0) → updated plan
- `select` → finalize → `"Selected <name>."` → session cleared
- `cancel` → `"Cancelled."` → session cleared

**Command with no active session:** treated as a search query using raw transcript.

---

## Contract Tests (Phase 12D)

| # | Case |
|---|---|
| 1 | Classifier: "next", "previous", "select", "cancel" → correct `DisambiguationCommand` values |
| 2 | Classifier: multiple surface forms ("back", "choose", "stop") map correctly |
| 3 | Classifier: assistant question prefixes ("what ", "show ", "abilities") → `AssistantQuestionIntent` |
| 4 | Classifier: arbitrary phrase → `SearchIntent` |
| 5 | Classifier: empty string → `UnknownIntent` |
| 6 | Canonicalizer: exact match in hints → hint returned verbatim (original casing) |
| 7 | Canonicalizer: no match (score < 0.75) → normalized transcript returned |
| 8 | Canonicalizer: stable → same inputs always produce same output |
| 9 | Coordinator: 0 entities → "No matches for..." plan, no session |
| 10 | Coordinator: 1 entity → plan confirms entity, no session, `selectedIndex == 0` |
| 11 | Coordinator: >1 entities → `selectedIndex == 0`, followUps includes 'next' and 'select' |
| 12 | Coordinator: clamp at first — `previous` at 0 keeps `selectedIndex == 0` |
| 13 | Coordinator: clamp at last — `next` past last keeps `selectedIndex == N-1` |
| 14 | Coordinator: `select` finalizes entity, session cleared, plan confirms name |
| 15 | Coordinator: `cancel` clears session, plan says "Cancelled." |
| 16 | Coordinator: command with no active session → treated as search |
| 17 | Coordinator: assistant question with 1 result → confirmation plan |
| 18 | Coordinator: `debugSummary` contains no timestamps across all plan types |
| 19 | Coordinator: same transcript + same fake results → identical plan (determinism) |

---

## HomeScreen Wiring (Minimal)

Current path:
```
onTextCandidate → VoiceSearchFacade.searchText() → show results
```

New path:
```
onTextCandidate → VoiceAssistantCoordinator.handleTranscript() → SpokenResponsePlan → show plan
```

Changes:
- Add `VoiceAssistantCoordinator _coordinator` initialized in `initState`.
- `_onTextCandidate` becomes async; calls `_coordinator.handleTranscript(...)`.
- Add `SpokenResponsePlan? _voicePlan` state field.
- `_buildResults`: when `_voicePlan != null`, show `plan.primaryText` + entity list (reuse card renderer) + highlight `selectedIndex`.
- Text search (`_search`) clears `_voicePlan`; voice plan arrival clears `_voiceResult`.

---

## Deliverables

- [x] This naming doc (prerequisite)
- [ ] `docs/glossary.md` — 12D terms appended
- [ ] `docs/name_change_log.md` — 12D entries appended
- [ ] 3 model files (`disambiguation_command.dart`, `voice_intent.dart`, `spoken_response_plan.dart`)
- [ ] 3 understanding files (`voice_intent_classifier.dart`, `domain_canonicalizer.dart`, `voice_assistant_coordinator.dart`)
- [ ] `lib/ui/home/home_screen.dart` updated (coordinator wired, plan displayed)
- [ ] `test/voice/phase_12d_voice_assistant_coordinator_test.dart` — all 19 tests passing

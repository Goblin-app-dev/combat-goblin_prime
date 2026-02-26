# Phase 12A — Voice Seam Extraction

**Status:** IMPLEMENTED (2026-02-26)
**Branch:** `claude/github-catalog-picker-Py9xI`
**Approved names:** `docs/phases/phase_12a_voice_seam_proposal.md`

---

## What Was Built

Phase 12A extracts a deterministic voice-oriented search seam so that future
wake-word/STT/TTS layers have a stable, named integration point. No frozen
modules were modified.

### New files

| File | Purpose |
|---|---|
| `lib/voice/models/spoken_variant.dart` | Single M10 hit enriched with slot context |
| `lib/voice/models/spoken_entity.dart` | Grouped voice entity (same canonicalKey, same slot) |
| `lib/voice/models/voice_search_response.dart` | Response returned by facade |
| `lib/voice/models/voice_selection_session.dart` | In-memory cursor for next/previous cycling |
| `lib/voice/services/search_result_grouper.dart` | Pure grouping function |
| `lib/voice/voice_search_facade.dart` | App-layer search entrypoint |
| `test/voice/voice_search_facade_test.dart` | Contract tests |

### Modified files

| File | Change |
|---|---|
| `lib/ui/home/home_screen.dart` | Search path routed through `VoiceSearchFacade`; results render grouped entities |
| `docs/glossary.md` | Added Phase 12A terms |
| `docs/name_change_log.md` | Logged new names |

---

## Grouping Rules

Phase 12A grouping is **slot-local**:

- **Group key:** `(slotId, canonicalKey)`
- Same `canonicalKey` in `slot_0` and `slot_1` produces **two separate entities**
- Cross-slot grouping is explicitly deferred to a future phase

Entity ordering (stable, deterministic):
1. `slotId` ascending
2. `groupKey` ascending
3. First variant `tieBreakKey` ascending

Variant ordering within each entity:
1. `tieBreakKey` ascending

---

## `tieBreakKey` Format

```
'$canonicalKey\x00$docId'
```

- Null-byte (`\x00`) separator
- `canonicalKey` always precedes `docId`
- Both fields are stable: derived from the frozen M9 index

---

## `spokenSummary` Contract

The `spokenSummary` field on `VoiceSearchResponse` is a **pure function** of the
`entities` list:
- No timestamps
- No relative dates
- No randomness
- Identical input → identical output across calls

Examples:
- 0 entities: `'No results for "query".'`
- 1 entity, 1 variant: `'Found "Entity Name".'`
- 1 entity, N>1 variants: `'Found N variants of "Entity Name". Say "next" to cycle.'`
- M>1 entities: `'Found T results across M groups for "query".'`

---

## `VoiceSelectionSession` Cycling Behavior

Cycling is **clamped** (no wrap):
- `nextVariant()` at last variant stays at last variant
- `previousVariant()` at index 0 stays at 0
- `nextEntity()` at last entity stays at last entity
- `previousEntity()` at index 0 stays at 0

`reset()` returns to entity 0, variant 0.
`chooseEntity(i)` jumps to index `i`, clamped to `[0, entities.length - 1]`.

---

## `VoiceSearchFacade` Contract

- Iterates `slotIndexBundles` in **lexicographic key order** (`slot_0` before `slot_1`)
- Calls `StructuredSearchService.search()` per bundle — **does NOT call `MultiPackSearchService.search()`**
- Uses `MultiPackSearchService.suggest()` only for typeahead (strings only; dedup irrelevant)
- Returns `VoiceSearchResponse.empty` for empty query or empty bundles

---

## HomeScreen Changes

- `_multiPackService: MultiPackSearchService` → `_facade: VoiceSearchFacade`
- `_result: MultiPackSearchResult?` → `_voiceResult: VoiceSearchResponse?`
- Results are rendered as `SpokenEntity` groups:
  - Single-variant entity → flat `ListTile`
  - Multi-variant entity → `ExpansionTile` with variant children
- Tap on any variant → `_showVariantDetail()` bottom sheet
- Suggestions typeahead unchanged: `_facade.suggest()` delegates to `MultiPackSearchService.suggest()`

---

## Future Extension Points

- **Cross-slot groups (12B+):** Add an optional `globalSearch` flag to
  `SearchResultGrouper` that groups by `(canonicalKey)` across slots.
- **STT/TTS (12B+):** `VoiceSearchFacade.searchText()` accepts plain `String`
  today; STT output feeds in the same way.
- **Wake word (12C+):** Replaces the keyboard `TextField`; routes through the
  same `VoiceSearchFacade` seam.
- **`VoiceSelectionCommand` dispatch (12B+):** A command enum + handler wraps
  `VoiceSelectionSession` for declarative voice commands.

---

## Non-Goals (Phase 12A)

- Wake word
- STT / TTS integration
- Model downloads
- Cross-slot entity merging
- Persistent session state

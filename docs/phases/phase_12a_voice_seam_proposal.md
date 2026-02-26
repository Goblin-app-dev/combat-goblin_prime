# Phase 12A Voice Seam Proposal — Approved Names

## STATUS: APPROVED (2026-02-26)

## Scope

App-layer voice seam extraction (Phase 12A). No frozen modules modified (M1–M10 +
Orchestrator untouched). No STT/TTS/wake-word. Slot-local grouping only.

## New Public Names

| Name | Kind | Location | Purpose |
|---|---|---|---|
| `SpokenVariant` | class | `lib/voice/models/spoken_variant.dart` | One underlying search hit in a specific catalog slot |
| `SpokenEntity` | class | `lib/voice/models/spoken_entity.dart` | Grouped voice entity: all variants sharing the same canonicalKey in the same slot |
| `VoiceSearchResponse` | class | `lib/voice/models/voice_search_response.dart` | Full response returned by `VoiceSearchFacade.searchText()` |
| `VoiceSelectionSession` | class | `lib/voice/models/voice_selection_session.dart` | In-memory cursor over an entity list; supports next/previous/chooseEntity |
| `SearchResultGrouper` | class | `lib/voice/services/search_result_grouper.dart` | Pure function helper: groups `SearchHit` results into `SpokenEntity` groups |
| `VoiceSearchFacade` | class | `lib/voice/voice_search_facade.dart` | App-layer voice search entrypoint; calls M10 per slot bundle, groups results |

## Invariants (locked for Phase 12A)

- `SpokenVariant.sourceSlotId` is always a concrete slot id (`'slot_0'`, `'slot_1'`);
  never null, never `'multi-slot'`.
- `SpokenVariant.tieBreakKey` is always `'$canonicalKey\x00$docId'`
  (null-byte separator, no other format).
- `SpokenEntity.slotId` is always a concrete slot id. Cross-slot grouping is
  **explicitly deferred** to a future phase.
- All orderings are deterministic and stable: slotId → groupKey → first variant
  tieBreakKey.
- `VoiceSearchResponse.spokenSummary` is a pure function of the entities list;
  no timestamps, no relative dates, no randomness.
- `VoiceSelectionSession` cycling is **clamped** (stop at bounds). No wrap.
- `VoiceSearchFacade` calls `StructuredSearchService.search()` per slot bundle
  directly; it does NOT call `MultiPackSearchService.search()`.

## Not In Scope (Phase 12A)

- `VoiceMode` enum — deferred (not needed without STT/TTS split)
- `VoiceSearchRequest` wrapper — deferred (facade takes plain params for now)
- `VoiceDisambiguator` — deferred (auto-pick is implicit: `primaryVariant = variants.first`)
- `VoiceSelectionCommand` enum — deferred (no command dispatch layer yet)
- Cross-slot `SpokenEntity` groups
- Wake word, STT, TTS

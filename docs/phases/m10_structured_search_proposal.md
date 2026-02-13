# M10 Structured Search — Proposal

**Status:** PROPOSAL (not implemented)
**Date:** 2026-02-13
**Depends on:** M9 Index-Core (frozen)

## Overview

M10 extends M9's raw search indices with structured query capabilities for voice interfaces and player-facing search. While M9 provides the indexed documents and basic query surface, M10 adds:

- Intent parsing (natural language → structured query)
- Fuzzy matching and ranking
- Query composition (AND/OR/NOT)
- Faceted filtering
- Response formatting for voice

## Scope Boundary

M10 does NOT:
- Modify M9 indices (M9 is frozen)
- Execute game rules
- Depend on M6/M7/M8
- Require rosters (pack-level search only)

## Proposed Query Types

### 1. Unit Search

```dart
/// Search for units by name with fuzzy matching.
class UnitSearchQuery {
  final String nameQuery;        // "intercessors" → fuzzy match
  final List<String>? keywords;  // ["infantry", "battleline"]
  final String? faction;         // "space marines"
  final int limit;
}

/// Ranked results with match confidence.
class UnitSearchResult {
  final UnitDoc unit;
  final double score;            // 0.0–1.0
  final MatchReason reason;      // exact, fuzzy, keyword
}
```

### 2. Weapon Search

```dart
/// Search for weapons by name or characteristic.
class WeaponSearchQuery {
  final String? nameQuery;       // "bolt rifle"
  final String? characteristic;  // "S" > 5
  final String? type;            // "ranged", "melee"
  final int limit;
}
```

### 3. Rule Search

```dart
/// Search for rules by name or effect text.
class RuleSearchQuery {
  final String query;            // "leader" or "re-roll"
  final bool searchDescription;  // search effect text too
  final int limit;
}
```

### 4. Composite Query

```dart
/// Combine multiple conditions.
class CompositeQuery {
  final List<QueryCondition> conditions;
  final CompositeOp op;          // and, or
}

enum CompositeOp { and, or }
```

## Proposed Service API

```dart
/// M10 Structured Search service.
///
/// Wraps M9 IndexBundle with structured query capabilities.
class SearchService {
  final IndexBundle index;

  /// Search units with ranking.
  List<UnitSearchResult> searchUnits(UnitSearchQuery query);

  /// Search weapons with ranking.
  List<WeaponSearchResult> searchWeapons(WeaponSearchQuery query);

  /// Search rules with ranking.
  List<RuleSearchResult> searchRules(RuleSearchQuery query);

  /// Parse natural language query into structured form.
  StructuredQuery parseIntent(String naturalLanguage);

  /// Format result for voice response.
  String formatForVoice(SearchResult result);
}
```

## Fuzzy Matching Strategy

Options to evaluate:

1. **Levenshtein distance** — Simple edit distance
2. **Trigram similarity** — Good for typos
3. **Soundex/Metaphone** — Phonetic matching ("intersesor" → "intercessor")
4. **Prefix matching** — Fast for autocomplete

Recommendation: Start with trigram + prefix, add phonetic if voice input is common.

## Intent Parsing Strategy

Options to evaluate:

1. **Keyword extraction** — Simple regex patterns
2. **Rule-based parser** — Grammar for common patterns
3. **ML classifier** — Overkill for v1

Recommended v1 patterns:
- "what is [unit/weapon/rule]?" → lookup query
- "show me [keyword] units" → keyword filter
- "find units with [characteristic] > N" → characteristic filter

## Open Questions

1. **Ranking weights** — How to weight exact vs fuzzy vs keyword matches?
2. **Caching** — Should SearchService cache parsed queries?
3. **Voice formatting** — What's the right verbosity for voice output?
4. **Multi-pack search** — Should M10 support searching across multiple IndexBundles?

## Dependencies

- M9 IndexBundle (frozen) — all doc types, indices, query surface
- No new M9 changes required

## Non-Goals for M10

- Rule execution (M6/M7 territory)
- Roster-aware search (needs M6)
- Real-time updates (M9 is built once per pack-load)
- Cross-catalog deduplication (same unit in multiple catalogs)

## Implementation Notes

This is a **proposal only** — no implementation yet.

Next steps if approved:
1. Finalize query types
2. Choose fuzzy matching algorithm
3. Implement SearchService
4. Add intent parsing
5. Add voice formatting
6. Write tests

## File Structure (Proposed)

```
lib/modules/m10_search/
  m10_search.dart           # barrel export
  models/
    unit_search_query.dart
    weapon_search_query.dart
    rule_search_query.dart
    search_result.dart
  services/
    search_service.dart
    intent_parser.dart
    voice_formatter.dart
```

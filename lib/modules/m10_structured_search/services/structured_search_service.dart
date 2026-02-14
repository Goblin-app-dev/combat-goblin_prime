import 'dart:collection';

import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

import '../models/match_reason.dart';
import '../models/search_config.dart';
import '../models/search_diagnostic.dart';
import '../models/search_doc_type.dart';
import '../models/search_hit.dart';
import '../models/search_request.dart';
import '../models/search_result.dart';
import '../models/search_sort.dart';
import '../models/sort_direction.dart';

/// Deterministic structured search over an M9 [IndexBundle].
///
/// This service is stateless with respect to index data — the [IndexBundle]
/// is passed per-call so the service holds no mutable references.
///
/// ## Determinism guarantees
///
/// All results are deterministically ordered using explicit tie-break rules:
///   1. Score (if applicable, higher first)
///   2. docType (enum index, ascending)
///   3. canonicalKey (lexicographic, ascending)
///   4. docId (lexicographic, ascending)
///
/// No iteration over unordered maps. No time-based or random scoring.
///
/// ## M9 delegation policy
///
/// Delegates to [IndexService.normalize] for all text normalization.
/// Uses M9 lookup methods ([IndexBundle.unitByDocId], etc.) for direct
/// resolution. Uses M9 text-search primitives ([IndexBundle.findUnitsContaining],
/// etc.) where available. Raw doc inspection is used only for filters that
/// M9 does not provide (weapon keyword tokens, characteristic value matching).
///
/// ## Empty-query contract
///
/// A query must have at least one search driver: text, keywords, or
/// characteristicFilters. A request with only docTypes set (and no drivers)
/// is treated as empty and returns [SearchDiagnosticCode.emptyQuery].
class StructuredSearchService {
  /// Optional configuration for search behavior.
  final SearchConfig config;

  StructuredSearchService({this.config = const SearchConfig()});

  // ---------------------------------------------------------------------------
  // resolveByDocId
  // ---------------------------------------------------------------------------

  /// Resolve a single document by its exact [docId].
  ///
  /// Deterministic lookup order: unit → weapon → rule.
  /// Returns null if no document with [docId] exists in [index].
  SearchHit? resolveByDocId(IndexBundle index, String docId) {
    // 1. Try unit
    final unit = index.unitByDocId(docId);
    if (unit != null) {
      return SearchHit(
        docId: unit.docId,
        docType: SearchDocType.unit,
        canonicalKey: unit.canonicalKey,
        displayName: unit.name,
        matchReasons: const [MatchReason.canonicalKeyMatch],
      );
    }

    // 2. Try weapon
    final weapon = index.weaponByDocId(docId);
    if (weapon != null) {
      return SearchHit(
        docId: weapon.docId,
        docType: SearchDocType.weapon,
        canonicalKey: weapon.canonicalKey,
        displayName: weapon.name,
        matchReasons: const [MatchReason.canonicalKeyMatch],
      );
    }

    // 3. Try rule
    final rule = index.ruleByDocId(docId);
    if (rule != null) {
      return SearchHit(
        docId: rule.docId,
        docType: SearchDocType.rule,
        canonicalKey: rule.canonicalKey,
        displayName: rule.name,
        matchReasons: const [MatchReason.canonicalKeyMatch],
      );
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // suggest
  // ---------------------------------------------------------------------------

  /// Suggest canonical keys matching [prefix] for autocomplete.
  ///
  /// Merges unit, weapon, and rule autocomplete results into a single
  /// deduplicated, lexicographically sorted list via [SplayTreeSet].
  /// Returns up to [limit] suggestions.
  List<String> suggest(IndexBundle index, String prefix, {int limit = 10}) {
    final prefixN = IndexService.normalize(prefix);
    if (prefixN.isEmpty) return const [];

    // Fetch from all three doc types. Pass a high per-type limit so we
    // don't accidentally truncate before the cross-type merge.
    final unitKeys = index.autocompleteUnitKeys(prefixN, limit: limit);
    final weaponKeys = index.autocompleteWeaponKeys(prefixN, limit: limit);
    final ruleKeys = index.autocompleteRuleKeys(prefixN, limit: limit);

    // Merge + unique deterministically (SplayTreeSet = lex order).
    final merged = SplayTreeSet<String>()
      ..addAll(unitKeys)
      ..addAll(weaponKeys)
      ..addAll(ruleKeys);

    return merged.take(limit).toList();
  }

  // ---------------------------------------------------------------------------
  // search
  // ---------------------------------------------------------------------------

  /// Execute a structured search against [index].
  ///
  /// Returns a [SearchResult] with deterministically ordered hits.
  /// Emits [SearchDiagnostic]s for empty queries, unsupported filters, or
  /// applied limits.
  SearchResult search(IndexBundle index, SearchRequest request) {
    final diagnostics = <SearchDiagnostic>[];

    // ------------------------------------------------------------------
    // 3.1  Validate + normalize
    // ------------------------------------------------------------------

    final textN = (request.text != null && request.text!.isNotEmpty)
        ? IndexService.normalize(request.text!)
        : null;
    final hasText = textN != null && textN.isNotEmpty;

    // Sorted enum list of doc types to search.
    final docTypesL = _resolveDocTypes(request.docTypes);

    // Normalize keywords: normalize each, remove empties, sort unique.
    final keywordsL = _normalizeKeywords(request.keywords);
    final hasKeywords = keywordsL.isNotEmpty;

    // Normalize characteristic filters: sort by key, normalize values.
    final charsL = _normalizeCharFilters(request.characteristicFilters);
    final hasCharFilters = charsL.isNotEmpty;

    // ------------------------------------------------------------------
    // 3.2  Empty-query rule (docTypes-only is empty)
    // ------------------------------------------------------------------

    if (!hasText && !hasKeywords && !hasCharFilters) {
      diagnostics.add(const SearchDiagnostic(
        code: SearchDiagnosticCode.emptyQuery,
        message:
            'No search driver provided. At least one of text, keywords, or '
            'characteristicFilters is required.',
      ));
      return SearchResult(hits: const [], diagnostics: diagnostics);
    }

    // ------------------------------------------------------------------
    // 3.3  Candidate generation by docType
    // ------------------------------------------------------------------

    // A) Text-driven candidates
    SplayTreeSet<String>? textCandidates;
    if (hasText) {
      textCandidates = SplayTreeSet<String>();
      for (final dt in docTypesL) {
        switch (dt) {
          case SearchDocType.unit:
            for (final doc in index.findUnitsContaining(textN)) {
              textCandidates.add(doc.docId);
            }
          case SearchDocType.weapon:
            for (final doc in index.findWeaponsContaining(textN)) {
              textCandidates.add(doc.docId);
            }
          case SearchDocType.rule:
            for (final doc in index.findRulesContaining(textN)) {
              textCandidates.add(doc.docId);
            }
        }
      }
    }

    // B) Keyword-driven candidates
    SplayTreeSet<String>? keywordCandidates;
    if (hasKeywords) {
      keywordCandidates = SplayTreeSet<String>();
      var firstKeyword = true;

      for (final keyword in keywordsL) {
        final matchesForKeyword = SplayTreeSet<String>();

        for (final dt in docTypesL) {
          switch (dt) {
            case SearchDocType.unit:
              // M9 has unitsByKeyword — use it.
              for (final doc in index.unitsByKeyword(keyword)) {
                matchesForKeyword.add(doc.docId);
              }
            case SearchDocType.weapon:
              // M9 has no weapon keyword index; raw inspection.
              for (final weapon in index.weapons) {
                if (weapon.keywordTokens.contains(keyword)) {
                  matchesForKeyword.add(weapon.docId);
                }
              }
            case SearchDocType.rule:
              // Rules have no keyword tokens — emit diagnostic once.
              diagnostics.add(SearchDiagnostic(
                code: SearchDiagnosticCode.invalidFilter,
                message: 'Keyword filter not supported for rule docs.',
                context: {'keyword': keyword},
              ));
          }
        }

        // Intersect across keywords (AND semantics).
        if (firstKeyword) {
          keywordCandidates = matchesForKeyword;
          firstKeyword = false;
        } else {
          keywordCandidates = SplayTreeSet<String>.from(
              keywordCandidates!.intersection(matchesForKeyword));
        }
      }

      // Deduplicate rule-keyword diagnostics: keep only one per request.
      _deduplicateRuleKeywordDiagnostics(diagnostics);
    }

    // C) Characteristic-driven candidates
    SplayTreeSet<String>? charCandidates;
    if (hasCharFilters) {
      charCandidates = SplayTreeSet<String>();
      var firstFilter = true;

      for (final entry in charsL) {
        final charName = entry.key;
        final charValueN = entry.value;

        // Use M9's docIdsByCharacteristic to narrow by name first.
        final nameMatchDocIds =
            index.docIdsByCharacteristic(charName).toSet();

        // Filter to only the doc types we're searching.
        final matchesForFilter = SplayTreeSet<String>();

        for (final docId in nameMatchDocIds) {
          final dt = _docTypeFromId(docId);
          if (dt == null || !docTypesL.contains(dt)) continue;

          // Raw doc inspection: compare normalized value.
          if (_characteristicValueMatches(
              index, docId, charName, charValueN)) {
            matchesForFilter.add(docId);
          }
        }

        // Intersect across filters (AND semantics).
        if (firstFilter) {
          charCandidates = matchesForFilter;
          firstFilter = false;
        } else {
          charCandidates = SplayTreeSet<String>.from(
              charCandidates!.intersection(matchesForFilter));
        }
      }
    }

    // ------------------------------------------------------------------
    // 3.4  Compose filters deterministically (intersection)
    // ------------------------------------------------------------------

    final candidateSets = <Set<String>>[
      if (textCandidates != null) textCandidates,
      if (keywordCandidates != null) keywordCandidates,
      if (charCandidates != null) charCandidates,
    ];

    SplayTreeSet<String> finalDocIds;
    if (candidateSets.isEmpty) {
      finalDocIds = SplayTreeSet<String>();
    } else if (candidateSets.length == 1) {
      finalDocIds = SplayTreeSet<String>.from(candidateSets.first);
    } else {
      // Intersect all candidate sets.
      var current = candidateSets.first;
      for (var i = 1; i < candidateSets.length; i++) {
        current = current.intersection(candidateSets[i]);
      }
      finalDocIds = SplayTreeSet<String>.from(current);
    }

    // ------------------------------------------------------------------
    // 3.5  Build SearchHit + MatchReason
    // ------------------------------------------------------------------

    final hits = <SearchHit>[];

    for (final docId in finalDocIds) {
      final hit = _buildHit(
        index,
        docId,
        textCandidates: textCandidates,
        keywordCandidates: keywordCandidates,
        charCandidates: charCandidates,
      );
      if (hit != null) hits.add(hit);
    }

    // ------------------------------------------------------------------
    // 3.6  Sorting + tie-breakers
    // ------------------------------------------------------------------

    _sortHits(hits, request.sort, request.sortDirection);

    // ------------------------------------------------------------------
    // 3.7  Limit + diagnostics
    // ------------------------------------------------------------------

    final limited = _applyLimit(hits, request.limit, diagnostics);

    // Sort diagnostics by code enum order, then message.
    diagnostics.sort((a, b) {
      final codeCompare = a.code.index.compareTo(b.code.index);
      if (codeCompare != 0) return codeCompare;
      return a.message.compareTo(b.message);
    });

    return SearchResult(hits: limited, diagnostics: diagnostics);
  }

  // ===========================================================================
  // Private helpers
  // ===========================================================================

  /// Resolves the set of doc types to search. Defaults to all three in
  /// enum order if null or empty.
  List<SearchDocType> _resolveDocTypes(Set<SearchDocType>? docTypes) {
    if (docTypes == null || docTypes.isEmpty) {
      return SearchDocType.values.toList();
    }
    final sorted = docTypes.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted;
  }

  /// Normalizes keyword set: normalize each, remove empties, sort unique.
  List<String> _normalizeKeywords(Set<String>? keywords) {
    if (keywords == null || keywords.isEmpty) return const [];
    final normalized = SplayTreeSet<String>();
    for (final kw in keywords) {
      final n = IndexService.normalize(kw);
      if (n.isNotEmpty) normalized.add(n);
    }
    return normalized.toList();
  }

  /// Normalizes characteristic filters: sort by key, normalize values.
  List<MapEntry<String, String>> _normalizeCharFilters(
      Map<String, String>? filters) {
    if (filters == null || filters.isEmpty) return const [];
    final sorted = SplayTreeMap<String, String>();
    for (final entry in filters.entries) {
      // Keep keys as-is (M9 characteristic names are stored lowercase
      // in the inverted index, and docIdsByCharacteristic lowercases
      // the input). Normalize values for comparison.
      sorted[entry.key] = IndexService.normalize(entry.value);
    }
    // Remove entries with empty normalized values.
    sorted.removeWhere((_, v) => v.isEmpty);
    return sorted.entries.toList();
  }

  /// Infers [SearchDocType] from a docId prefix.
  SearchDocType? _docTypeFromId(String docId) {
    if (docId.startsWith('unit:')) return SearchDocType.unit;
    if (docId.startsWith('weapon:')) return SearchDocType.weapon;
    if (docId.startsWith('rule:')) return SearchDocType.rule;
    return null;
  }

  /// Checks whether a document's characteristic value matches the normalized
  /// filter value. Both sides are compared via [IndexService.normalize].
  bool _characteristicValueMatches(
    IndexBundle index,
    String docId,
    String charName,
    String filterValueN,
  ) {
    final charNameLower = charName.toLowerCase();

    // Resolve the doc to inspect its characteristics.
    final unit = index.unitByDocId(docId);
    if (unit != null) {
      return unit.characteristics.any((c) =>
          c.name.toLowerCase() == charNameLower &&
          IndexService.normalize(c.valueText) == filterValueN);
    }

    final weapon = index.weaponByDocId(docId);
    if (weapon != null) {
      return weapon.characteristics.any((c) =>
          c.name.toLowerCase() == charNameLower &&
          IndexService.normalize(c.valueText) == filterValueN);
    }

    // Rules have no characteristics.
    return false;
  }

  /// Deduplicates rule-keyword diagnostics to emit at most one per request.
  void _deduplicateRuleKeywordDiagnostics(List<SearchDiagnostic> diagnostics) {
    var foundFirst = false;
    diagnostics.removeWhere((d) {
      if (d.code == SearchDiagnosticCode.invalidFilter &&
          d.message == 'Keyword filter not supported for rule docs.') {
        if (foundFirst) return true;
        foundFirst = true;
      }
      return false;
    });
  }

  /// Builds a [SearchHit] from a docId, determining match reasons from
  /// which candidate sets it appeared in.
  SearchHit? _buildHit(
    IndexBundle index,
    String docId, {
    SplayTreeSet<String>? textCandidates,
    SplayTreeSet<String>? keywordCandidates,
    SplayTreeSet<String>? charCandidates,
  }) {
    // Resolve doc — deterministic order: unit → weapon → rule.
    final unit = index.unitByDocId(docId);
    if (unit != null) {
      return SearchHit(
        docId: docId,
        docType: SearchDocType.unit,
        canonicalKey: unit.canonicalKey,
        displayName: unit.name,
        matchReasons: _buildMatchReasons(
            docId, textCandidates, keywordCandidates, charCandidates),
      );
    }

    final weapon = index.weaponByDocId(docId);
    if (weapon != null) {
      return SearchHit(
        docId: docId,
        docType: SearchDocType.weapon,
        canonicalKey: weapon.canonicalKey,
        displayName: weapon.name,
        matchReasons: _buildMatchReasons(
            docId, textCandidates, keywordCandidates, charCandidates),
      );
    }

    final rule = index.ruleByDocId(docId);
    if (rule != null) {
      return SearchHit(
        docId: docId,
        docType: SearchDocType.rule,
        canonicalKey: rule.canonicalKey,
        displayName: rule.name,
        matchReasons: _buildMatchReasons(
            docId, textCandidates, keywordCandidates, charCandidates),
      );
    }

    return null;
  }

  /// Builds match reasons in fixed enum order based on which candidate sets
  /// contain the docId.
  List<MatchReason> _buildMatchReasons(
    String docId,
    SplayTreeSet<String>? textCandidates,
    SplayTreeSet<String>? keywordCandidates,
    SplayTreeSet<String>? charCandidates,
  ) {
    final reasons = <MatchReason>[];
    // Add in enum order for determinism.
    if (textCandidates != null && textCandidates.contains(docId)) {
      reasons.add(MatchReason.canonicalKeyMatch);
    }
    if (keywordCandidates != null && keywordCandidates.contains(docId)) {
      reasons.add(MatchReason.keywordMatch);
    }
    if (charCandidates != null && charCandidates.contains(docId)) {
      reasons.add(MatchReason.characteristicMatch);
    }
    return reasons;
  }

  /// Sorts hits in-place according to the requested sort strategy.
  void _sortHits(
    List<SearchHit> hits,
    SearchSort sort,
    SortDirection direction,
  ) {
    int Function(SearchHit, SearchHit) comparator;

    switch (sort) {
      case SearchSort.alphabetical:
        comparator = (a, b) {
          final keyCompare = a.canonicalKey.compareTo(b.canonicalKey);
          if (keyCompare != 0) return keyCompare;
          final dtCompare = a.docType.index.compareTo(b.docType.index);
          if (dtCompare != 0) return dtCompare;
          return a.docId.compareTo(b.docId);
        };
      case SearchSort.docTypeThenAlphabetical:
        comparator = (a, b) {
          final dtCompare = a.docType.index.compareTo(b.docType.index);
          if (dtCompare != 0) return dtCompare;
          final keyCompare = a.canonicalKey.compareTo(b.canonicalKey);
          if (keyCompare != 0) return keyCompare;
          return a.docId.compareTo(b.docId);
        };
      case SearchSort.relevance:
        comparator = (a, b) {
          final scoreA = _relevanceScore(a);
          final scoreB = _relevanceScore(b);
          // Higher score first.
          final scoreCompare = scoreB.compareTo(scoreA);
          if (scoreCompare != 0) return scoreCompare;
          // Tie-break: docType → canonicalKey → docId.
          final dtCompare = a.docType.index.compareTo(b.docType.index);
          if (dtCompare != 0) return dtCompare;
          final keyCompare = a.canonicalKey.compareTo(b.canonicalKey);
          if (keyCompare != 0) return keyCompare;
          return a.docId.compareTo(b.docId);
        };
    }

    // Apply direction.
    if (direction == SortDirection.descending) {
      final original = comparator;
      comparator = (a, b) => original(b, a);
    }

    hits.sort(comparator);
  }

  /// Deterministic integer relevance score based on match reason count.
  int _relevanceScore(SearchHit hit) {
    return hit.matchReasons.length;
  }

  /// Applies the limit, emitting a diagnostic if truncation occurred.
  List<SearchHit> _applyLimit(
    List<SearchHit> hits,
    int limit,
    List<SearchDiagnostic> diagnostics,
  ) {
    if (hits.length <= limit) return hits;
    diagnostics.add(SearchDiagnostic(
      code: SearchDiagnosticCode.resultLimitApplied,
      message: 'Results truncated from ${hits.length} to $limit.',
    ));
    return hits.sublist(0, limit);
  }
}

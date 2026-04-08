import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

import '../models/disambiguation_command.dart';
import '../models/spoken_entity.dart';
import '../models/spoken_response_plan.dart';
import '../models/voice_intent.dart';
import '../models/voice_selection_session.dart';
import '../voice_search_facade.dart';
import 'canonical_name_resolver.dart';
import 'domain_canonicalizer.dart';
import 'voice_intent_classifier.dart';

/// Maps lowercased question-side synonym phrases → canonical IndexedCharacteristic.name.
///
/// Multi-word keys are listed before single-word keys so that iteration
/// matches the longest phrase first (Dart Maps iterate in insertion order).
///
/// Synonym resolution belongs on the question side; the canonical key (e.g. "BS")
/// is what is matched against IndexedCharacteristic.name in the index data.
const _kAttributeSynonyms = <String, String>{
  'ballistic skill': 'BS', // longest first
  'ballistic': 'BS',
  'bs': 'BS',
};

/// Extracts (weaponName, valueText) pairs for [attributeKey] from [weapons].
///
/// [weapons] must be pre-sorted by the caller for stable output.
/// Returns only pairs where a matching characteristic exists.
///
/// Exposed at package level (no underscore) so that tests can call it directly
/// with constructed [WeaponDoc] fixtures, without needing a full [IndexBundle].
List<(String, String)> extractAttributeValues(
  String attributeKey,
  List<WeaponDoc> weapons,
) {
  final result = <(String, String)>[];
  for (final w in weapons) {
    for (final c in w.characteristics) {
      if (c.name == attributeKey) {
        result.add((w.name, c.valueText));
        break; // one characteristic of this type per weapon profile
      }
    }
  }
  return result;
}

/// Formats a human-readable attribute-answer string.
///
/// Example output: `"Intercessors BS — Bolt Pistol: 3+, Bolt Rifle: 3+"`
///
/// Exposed at package level for deterministic testing of output format.
String formatAttributeAnswer(
  String entityName,
  String attributeKey,
  List<(String, String)> lines,
) {
  final parts = lines.map((l) => '${l.$1}: ${l.$2}').join(', ');
  return '$entityName $attributeKey — $parts';
}

/// Coordinator that turns a voice transcript into a [SpokenResponsePlan].
///
/// Responsibilities (single method [handleTranscript]):
/// 1. Classify transcript intent via [VoiceIntentClassifier].
/// 2. If a disambiguation command arrives with an active session → handle it.
/// 3. If an [AssistantQuestionIntent] is detected → route to attribute Q&A.
/// 4. Otherwise canonicalize the query via [DomainCanonicalizer], then apply
///    [CanonicalNameResolver] to map user-friendly names to BSData names.
/// 5. Run [VoiceSearchFacade.searchText] and interpret results:
///    - 0 results → "No matches" plan, session cleared.
///    - 1 result  → confirm plan, session cleared.
///    - N > 1     → disambiguation plan, new [VoiceSelectionSession] created.
///
/// State:
/// - [_session]: current [VoiceSelectionSession] or null.
/// - [_lastEntities]: entities from the most recent search (for navigation plans).
/// - [_lastSelected]: last entity confirmed via "select".
///
/// The method is `async` for future extensibility (e.g. online STT, async
/// canonicalization). The current implementation is fully synchronous internally.
final class VoiceAssistantCoordinator {
  final VoiceSearchFacade _searchFacade;
  final VoiceIntentClassifier _classifier;
  final DomainCanonicalizer _canonicalizer;
  final CanonicalNameResolver _resolver;

  VoiceSelectionSession? _session;
  List<SpokenEntity> _lastEntities = const [];

  SpokenEntity? _lastSelected;

  VoiceAssistantCoordinator({
    required VoiceSearchFacade searchFacade,
    VoiceIntentClassifier classifier = const VoiceIntentClassifier(),
    DomainCanonicalizer canonicalizer = const DomainCanonicalizer(),
    CanonicalNameResolver resolver = const CanonicalNameResolver(),
  })  : _searchFacade = searchFacade,
        _classifier = classifier,
        _canonicalizer = canonicalizer,
        _resolver = resolver;

  /// Process [transcript] and return a [SpokenResponsePlan].
  ///
  /// [slotBundles] is keyed by slot id (e.g. 'slot_0', 'slot_1').
  /// [contextHints] are domain vocabulary terms for fuzzy canonicalization.
  Future<SpokenResponsePlan> handleTranscript({
    required String transcript,
    required Map<String, IndexBundle> slotBundles,
    required List<String> contextHints,
  }) async {
    final intent = _classifier.classify(transcript);

    // --- Disambiguation command with active session ---
    if (intent is DisambiguationCommandIntent && _session != null) {
      return _handleCommand(intent.command);
    }

    // --- Unknown / empty transcript ---
    if (intent is UnknownIntent) {
      return SpokenResponsePlan(
        primaryText: "Sorry, I didn't catch that. Please say a search term.",
        entities: const [],
        followUps: const [],
        debugSummary: 'unknown-empty',
      );
    }

    // --- Attribute question: intercept before normal search path ---
    if (intent is AssistantQuestionIntent) {
      return _handleAttributeQuestion(
        transcript: transcript,
        slotBundles: slotBundles,
        contextHints: contextHints,
      );
    }

    // --- Resolve query text ---
    // DisambiguationCommandIntent with no active session: use raw transcript as query.
    final String queryText;
    if (intent is SearchIntent) {
      queryText = intent.queryText;
    } else {
      queryText = transcript.trim();
    }

    // Two-phase name resolution:
    // Phase 1 — DomainCanonicalizer: fuzzy-correct STT transcription errors
    //   against known context hints.
    // Phase 2 — CanonicalNameResolver: map user-friendly phrases to BSData
    //   catalog names (faction aliases, reordered unit names, etc.).
    final fuzzyCanonical = _canonicalizer.canonicalizeQuery(
      queryText,
      contextHints: contextHints,
    );
    final canonical = _resolver.resolve(fuzzyCanonical);

    if (canonical.isEmpty) {
      return SpokenResponsePlan(
        primaryText: "Sorry, I didn't catch that. Please say a search term.",
        entities: const [],
        followUps: const [],
        debugSummary: 'empty-canonical',
      );
    }

    return _runSearch(canonical, slotBundles);
  }

  /// Clear the active [VoiceSelectionSession] (e.g. on mode change).
  void clearSession() => _session = null;

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  SpokenResponsePlan _handleAttributeQuestion({
    required String transcript,
    required Map<String, IndexBundle> slotBundles,
    required List<String> contextHints,
  }) {
    final normalized = _normalizeForParsing(transcript);

    // 1. Detect attribute token — multi-word keys checked first (insertion order).
    String? canonicalAttr;
    String? matchedAttrPhrase;
    for (final entry in _kAttributeSynonyms.entries) {
      if (normalized.contains(entry.key)) {
        canonicalAttr = entry.value;
        matchedAttrPhrase = entry.key;
        break;
      }
    }

    // 2. No recognized attribute → fall back to plain search behavior.
    if (canonicalAttr == null) {
      final fuzzyCanonical = _canonicalizer.canonicalizeQuery(
        transcript,
        contextHints: contextHints,
      );
      final canonical = _resolver.resolve(fuzzyCanonical);
      if (canonical.isEmpty) {
        return SpokenResponsePlan(
          primaryText: "Sorry, I didn't catch that. Please say a search term.",
          entities: const [],
          followUps: const [],
          debugSummary: 'empty-canonical',
        );
      }
      return _runSearch(canonical, slotBundles);
    }

    // 3. Extract entity name using the matched synonym phrase (not the canonical key).
    final entityQuery = _extractEntityName(normalized, matchedAttrPhrase!);
    final fuzzyCanonical = _canonicalizer.canonicalizeQuery(
      entityQuery,
      contextHints: contextHints,
    );
    final canonical = _resolver.resolve(fuzzyCanonical);
    if (canonical.isEmpty) {
      return SpokenResponsePlan(
        primaryText: "Sorry, I didn't catch that. Please say a search term.",
        entities: const [],
        followUps: const [],
        debugSummary: 'empty-canonical',
      );
    }

    // 4. Search for the entity — use a broad limit so the post-search quality
    //    filter sees all plausible candidates.
    final response =
        _searchFacade.searchText(slotBundles, canonical, limit: _kSearchLimit);
    final filteredEntities =
        _filterByCanonicalQuality(response.entities, canonical);
    _lastEntities = filteredEntities;

    if (filteredEntities.isEmpty) {
      _session = null;
      return SpokenResponsePlan(
        primaryText: 'No matches for "$canonical".',
        entities: const [],
        followUps: const [],
        debugSummary: 'no-results:$canonical',
      );
    }

    if (filteredEntities.length > 1) {
      _session = VoiceSelectionSession(filteredEntities);
      return SpokenResponsePlan(
        primaryText:
            'I found ${filteredEntities.length} matches. Say "next" or "select".',
        entities: filteredEntities,
        selectedIndex: 0,
        followUps: const ['next', 'previous', 'select', 'cancel'],
        debugSummary: 'disambiguation:${filteredEntities.length}',
      );
    }

    // 5. Exactly 1 result: look up the doc and answer the attribute question.
    final entity = filteredEntities.first;
    _lastSelected = entity;
    _session = null;
    final variant = entity.primaryVariant;
    final bundle = slotBundles[variant.sourceSlotId];

    if (bundle == null) {
      return SpokenResponsePlan(
        primaryText: 'Found ${entity.displayName} but no data bundle is available.',
        entities: filteredEntities,
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'attr-no-bundle:${entity.groupKey}',
      );
    }

    final unitDoc = bundle.unitByDocId(variant.docId);
    if (unitDoc == null) {
      return SpokenResponsePlan(
        primaryText: 'Found ${entity.displayName} but could not load unit data.',
        entities: filteredEntities,
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'attr-no-unit-doc:${entity.groupKey}',
      );
    }

    // Resolve and sort weapons: stable order (name, docId).
    final weapons = unitDoc.weaponDocRefs
        .map(bundle.weaponByDocId)
        .whereType<WeaponDoc>()
        .toList()
      ..sort((a, b) {
        final cmp = a.name.compareTo(b.name);
        return cmp != 0 ? cmp : a.docId.compareTo(b.docId);
      });

    final attrLines = extractAttributeValues(canonicalAttr, weapons);

    if (attrLines.isEmpty) {
      return SpokenResponsePlan(
        primaryText: '${entity.displayName}: no $canonicalAttr values found.',
        entities: filteredEntities,
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'attr-empty:${entity.groupKey}',
      );
    }

    return SpokenResponsePlan(
      primaryText: formatAttributeAnswer(entity.displayName, canonicalAttr, attrLines),
      entities: filteredEntities,
      selectedIndex: 0,
      followUps: const [],
      debugSummary: 'attr-answer:${canonicalAttr.toLowerCase()}:${entity.groupKey}',
    );
  }

  /// Normalizes text for internal question parsing.
  /// Lowercases, strips punctuation, collapses whitespace.
  /// Distinct from [DomainCanonicalizer] which is for entity search matching.
  static String _normalizeForParsing(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Extracts the entity name from a normalized question string.
  ///
  /// Rule 1: If normalized contains " of ", take the substring after the last
  ///         " of " and strip a leading "the ".
  /// Rule 2: Else find [attrPhrase] in the string, take everything after it,
  ///         and strip a leading stopword ("the", "a", "an", etc.).
  static String _extractEntityName(String normalized, String attrPhrase) {
    const stopwords = ['the ', 'a ', 'an ', 'for ', 'on ', 'in ', 'to '];
    final ofIdx = normalized.lastIndexOf(' of ');
    if (ofIdx != -1) {
      var entity = normalized.substring(ofIdx + 4).trim();
      if (entity.startsWith('the ')) entity = entity.substring(4).trim();
      return entity;
    }
    final attrIdx = normalized.indexOf(attrPhrase);
    if (attrIdx != -1) {
      var entity = normalized.substring(attrIdx + attrPhrase.length).trim();
      for (final sw in stopwords) {
        if (entity.startsWith(sw)) {
          entity = entity.substring(sw.length).trim();
          break;
        }
      }
      return entity;
    }
    return normalized;
  }

  SpokenResponsePlan _handleCommand(DisambiguationCommand command) {
    final session = _session!;
    switch (command) {
      case DisambiguationCommand.next:
        session.nextEntity();
        return _planForSession(session);
      case DisambiguationCommand.previous:
        session.previousEntity();
        return _planForSession(session);
      case DisambiguationCommand.select:
        final entity = session.currentEntity;
        _lastSelected = entity;
        _session = null;
        if (entity == null) {
          return SpokenResponsePlan(
            primaryText: 'Nothing to select.',
            entities: const [],
            followUps: const [],
            debugSummary: 'select-empty',
          );
        }
        return SpokenResponsePlan(
          primaryText: 'Selected ${entity.displayName}.',
          entities: [entity],
          selectedIndex: null,
          followUps: const [],
          debugSummary: 'selected:${entity.groupKey}',
        );
      case DisambiguationCommand.cancel:
        _session = null;
        return SpokenResponsePlan(
          primaryText: 'Cancelled.',
          entities: const [],
          followUps: const [],
          debugSummary: 'cancelled',
        );
    }
  }

  SpokenResponsePlan _planForSession(VoiceSelectionSession session) {
    final entity = session.currentEntity;
    if (entity == null) {
      return SpokenResponsePlan(
        primaryText: 'No results to navigate.',
        entities: const [],
        followUps: const [],
        debugSummary: 'navigate-empty',
      );
    }
    return SpokenResponsePlan(
      primaryText:
          'Now on ${entity.displayName}. Say "select" to confirm or "next" to continue.',
      entities: _lastEntities,
      selectedIndex: session.entityIndex,
      followUps: const ['next', 'previous', 'select', 'cancel'],
      debugSummary: 'navigate:${session.entityIndex}/${_lastEntities.length - 1}',
    );
  }

  SpokenResponsePlan _runSearch(
    String canonical,
    Map<String, IndexBundle> slotBundles,
  ) {
    // Use a broad limit so the post-search quality filter sees all plausible
    // candidates before truncation.
    final response =
        _searchFacade.searchText(slotBundles, canonical, limit: _kSearchLimit);
    final filteredEntities =
        _filterByCanonicalQuality(response.entities, canonical);
    _lastEntities = filteredEntities;

    if (filteredEntities.isEmpty) {
      _session = null;
      return SpokenResponsePlan(
        primaryText: 'No matches for "$canonical".',
        entities: const [],
        followUps: const [],
        debugSummary: 'no-results:$canonical',
      );
    }

    if (filteredEntities.length == 1) {
      _lastSelected = filteredEntities.first;
      _session = null;
      return SpokenResponsePlan(
        primaryText: 'Found ${filteredEntities.first.displayName}.',
        entities: filteredEntities,
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'single:${filteredEntities.first.groupKey}',
      );
    }

    // Multiple entities: create disambiguation session.
    _session = VoiceSelectionSession(filteredEntities);
    return SpokenResponsePlan(
      primaryText:
          'I found ${filteredEntities.length} matches. Say "next" or "select".',
      entities: filteredEntities,
      selectedIndex: 0,
      followUps: const ['next', 'previous', 'select', 'cancel'],
      debugSummary: 'disambiguation:${filteredEntities.length}',
    );
  }

  // ---------------------------------------------------------------------------
  // Entity selection
  // ---------------------------------------------------------------------------

  /// Broad search limit used before canonical-quality filtering.
  ///
  /// High enough to ensure all plausible candidates are retrieved before
  /// the post-search quality filter narrows the set. M9/M10 are not changed.
  static const int _kSearchLimit = 200;

  /// Filters [entities] to those with the best canonical match quality
  /// against [query].
  ///
  /// Scores each entity's [SpokenEntity.groupKey] against [query] using
  /// four deterministic tiers:
  ///
  ///   4 — exact match (`groupKey == query`)
  ///   3 — singular/plural match (`groupKey == query + 's'` or vice-versa)
  ///   2 — word-boundary prefix/suffix (groupKey starts/ends with query at
  ///       a word boundary)
  ///   1 — general substring (every M10 hit has at least this)
  ///
  /// Only entities at the highest observed tier are returned, in their
  /// original order (stable). This is a post-search selection step; M9/M10
  /// ranking and the index are not modified.
  ///
  /// If all entities share the same score (tie at any tier) the full list is
  /// returned unchanged so normal disambiguation takes over.
  static List<SpokenEntity> _filterByCanonicalQuality(
    List<SpokenEntity> entities,
    String query,
  ) {
    if (entities.length <= 1) return entities;

    int scoreKey(String groupKey) {
      if (groupKey == query) return 4;
      // Singular ↔ plural: groupKey == query+'s' or groupKey+'s' == query.
      if ('${groupKey}s' == query || groupKey == '${query}s') return 3;
      // Word-boundary prefix: groupKey starts with "query " (space after).
      // Word-boundary suffix: groupKey ends with " query" (space before).
      if (groupKey.startsWith('$query ') || groupKey.endsWith(' $query')) {
        return 2;
      }
      return 1;
    }

    int bestScore = 1;
    for (final e in entities) {
      final s = scoreKey(e.groupKey);
      if (s > bestScore) bestScore = s;
    }

    // If everything is a general substring match, keep all (standard
    // disambiguation). Only filter when there is a strictly better tier.
    if (bestScore == 1) return entities;

    return entities.where((e) => scoreKey(e.groupKey) == bestScore).toList();
  }
}

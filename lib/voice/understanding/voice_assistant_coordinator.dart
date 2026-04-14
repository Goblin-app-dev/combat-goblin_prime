import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

import '../models/disambiguation_command.dart';
import '../models/spoken_entity.dart';
import '../models/spoken_response_plan.dart';
import '../models/voice_intent.dart';
import '../models/voice_selection_session.dart';
import '../voice_search_facade.dart';
import 'domain_canonicalizer.dart';
import 'voice_intent_classifier.dart';

/// Maps lowercased question-side synonym phrases → canonical IndexedCharacteristic.name.
///
/// Multi-word keys are listed before single-word keys so that iteration
/// matches the longest phrase first (Dart Maps iterate in insertion order).
///
/// Synonym resolution belongs on the question side; the canonical key (e.g. "BS")
/// is what is matched against IndexedCharacteristic.name in the index data.
///
/// Unit stats: M (Movement), T (Toughness), SV (Save), W (Wounds), LD (Leadership),
///             OC (Objective Control), WS (Weapon Skill).
/// Weapon stats: Range, A (Attacks), BS (Ballistic Skill), S (Strength), AP, D (Damage).
const _kAttributeSynonyms = <String, String>{
  // Multi-word phrases — longest first
  'objective control': 'OC',
  'weapon skill': 'WS',
  'ballistic skill': 'BS',
  // Long single-word unit stats
  'leadership': 'LD',
  'toughness': 'T',
  'movement': 'M',
  'ballistic': 'BS',
  // Short single-word stats
  'wounds': 'W',
  'save': 'SV',
  'move': 'M', // after 'movement' so 'movement' wins on longer strings
  // Two-letter abbreviations
  'bs': 'BS',
  'oc': 'OC',
  'ld': 'LD',
  'sv': 'SV',
  'ws': 'WS',
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

/// Formats the disambiguation prompt, listing up to 3 entity names inline.
///
/// Examples:
///   2 entities → `'I found 2 matches: Alpha and Beta. Say "next" or "select".'`
///   3 entities → `'I found 3 matches: A, B, and C. Say "next" or "select".'`
///   4 entities → `'I found 4 matches: A, B, and C. Say "next" or "select".'`
///
/// Including names is essential for TTS: "I found 3 matches" alone gives the
/// listener no information about what they are choosing between.
String _formatDisambiguationPrompt(List<SpokenEntity> entities) {
  final count = entities.length;
  final shown = entities.take(3).map((e) => e.displayName).toList();
  final String nameClause;
  if (shown.length == 2) {
    nameClause = '${shown[0]} and ${shown[1]}';
  } else {
    nameClause = '${shown[0]}, ${shown[1]}, and ${shown[2]}';
  }
  return 'I found $count ${count == 1 ? 'match' : 'matches'}: $nameClause. '
      'Say "next" or "select".';
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
/// 4. Otherwise canonicalize the query via [DomainCanonicalizer].
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

  VoiceSelectionSession? _session;
  List<SpokenEntity> _lastEntities = const [];

  SpokenEntity? _lastSelected;

  VoiceAssistantCoordinator({
    required VoiceSearchFacade searchFacade,
    VoiceIntentClassifier classifier = const VoiceIntentClassifier(),
    DomainCanonicalizer canonicalizer = const DomainCanonicalizer(),
  })  : _searchFacade = searchFacade,
        _classifier = classifier,
        _canonicalizer = canonicalizer;

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
        sessionCleared: true,
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

    final canonical = _canonicalizer.canonicalizeQuery(
      queryText,
      contextHints: contextHints,
    );

    if (canonical.isEmpty) {
      return SpokenResponsePlan(
        primaryText: "Sorry, I didn't catch that. Please say a search term.",
        entities: const [],
        followUps: const [],
        debugSummary: 'empty-canonical',
        sessionCleared: true,
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
      final canonical = _canonicalizer.canonicalizeQuery(
        transcript,
        contextHints: contextHints,
      );
      if (canonical.isEmpty) {
        return SpokenResponsePlan(
          primaryText: "Sorry, I didn't catch that. Please say a search term.",
          entities: const [],
          followUps: const [],
          debugSummary: 'empty-canonical',
          sessionCleared: true,
        );
      }
      return _runSearch(canonical, slotBundles);
    }

    // 3. Extract entity name using the matched synonym phrase (not the canonical key).
    final entityQuery = _extractEntityName(normalized, matchedAttrPhrase!);
    final canonical = _canonicalizer.canonicalizeQuery(
      entityQuery,
      contextHints: contextHints,
    );
    if (canonical.isEmpty) {
      return SpokenResponsePlan(
        primaryText: "Sorry, I didn't catch that. Please say a search term.",
        entities: const [],
        followUps: const [],
        debugSummary: 'empty-canonical',
        sessionCleared: true,
      );
    }

    // 4. Search for the entity.
    final response = _searchFacade.searchText(slotBundles, canonical);
    _lastEntities = response.entities;

    if (response.entities.isEmpty) {
      _session = null;
      return SpokenResponsePlan(
        primaryText: 'No matches for "$canonical".',
        entities: const [],
        followUps: const [],
        debugSummary: 'no-results:$canonical',
      );
    }

    if (response.entities.length > 1) {
      _session = VoiceSelectionSession(response.entities);
      return SpokenResponsePlan(
        primaryText: _formatDisambiguationPrompt(response.entities),
        entities: response.entities,
        selectedIndex: 0,
        followUps: const ['next', 'previous', 'select', 'cancel'],
        debugSummary: 'disambiguation:${response.entities.length}',
      );
    }

    // 5. Exactly 1 result: look up the doc and answer the attribute question.
    final entity = response.entities.first;
    _lastSelected = entity;
    _session = null;
    final variant = entity.primaryVariant;
    final bundle = slotBundles[variant.sourceSlotId];

    if (bundle == null) {
      return SpokenResponsePlan(
        primaryText: 'Found ${entity.displayName} but no data bundle is available.',
        entities: response.entities,
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'attr-no-bundle:${entity.groupKey}',
      );
    }

    final unitDoc = bundle.unitByDocId(variant.docId);
    if (unitDoc == null) {
      return SpokenResponsePlan(
        primaryText: 'Found ${entity.displayName} but could not load unit data.',
        entities: response.entities,
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

    // Unit-level characteristics (T, W, M, SV, LD, OC, WS) take priority.
    // If the requested attribute is found on the unit itself, skip weapon lookup.
    final unitLines = <(String, String)>[];
    for (final c in unitDoc.characteristics) {
      if (c.name == canonicalAttr) {
        unitLines.add((entity.displayName, c.valueText));
        break; // one value per unit profile
      }
    }

    final attrLines =
        unitLines.isNotEmpty ? unitLines : extractAttributeValues(canonicalAttr, weapons);

    if (attrLines.isEmpty) {
      return SpokenResponsePlan(
        primaryText: '${entity.displayName}: no $canonicalAttr values found.',
        entities: response.entities,
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'attr-empty:${entity.groupKey}',
      );
    }

    return SpokenResponsePlan(
      primaryText: formatAttributeAnswer(entity.displayName, canonicalAttr, attrLines),
      entities: response.entities,
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
          sessionCleared: true,
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
    final response = _searchFacade.searchText(slotBundles, canonical);
    _lastEntities = response.entities;

    if (response.entities.isEmpty) {
      _session = null;
      return SpokenResponsePlan(
        primaryText: 'No matches for "$canonical".',
        entities: const [],
        followUps: const [],
        debugSummary: 'no-results:$canonical',
      );
    }

    if (response.entities.length == 1) {
      _lastSelected = response.entities.first;
      _session = null;
      return SpokenResponsePlan(
        primaryText: 'Found ${response.entities.first.displayName}.',
        entities: response.entities,
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'single:${response.entities.first.groupKey}',
      );
    }

    // Multiple entities: create disambiguation session.
    _session = VoiceSelectionSession(response.entities);
    return SpokenResponsePlan(
      primaryText: _formatDisambiguationPrompt(response.entities),
      entities: response.entities,
      selectedIndex: 0,
      followUps: const ['next', 'previous', 'select', 'cancel'],
      debugSummary: 'disambiguation:${response.entities.length}',
    );
  }
}

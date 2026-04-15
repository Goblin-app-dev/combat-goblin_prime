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
const _kAttributeSynonyms = <String, String>{
  'objective control': 'OC',
  'weapon skill': 'WS',
  'ballistic skill': 'BS',
  'leadership': 'LD',
  'toughness': 'T',
  'movement': 'M',
  'ballistic': 'BS',
  'wounds': 'W',
  'save': 'SV',
  'move': 'M',
  'bs': 'BS',
  'oc': 'OC',
  'ld': 'LD',
  'sv': 'SV',
  'ws': 'WS',
};

/// Extracts (weaponName, valueText) pairs for [attributeKey] from [weapons].
List<(String, String)> extractAttributeValues(
  String attributeKey,
  List<WeaponDoc> weapons,
) {
  final result = <(String, String)>[];
  for (final w in weapons) {
    for (final c in w.characteristics) {
      if (c.name == attributeKey) {
        result.add((w.name, c.valueText));
        break;
      }
    }
  }
  return result;
}

/// Formats a human-readable attribute-answer string.
///
/// Example: `"Intercessors BS — Bolt Pistol: 3+, Bolt Rifle: 3+"`
String formatAttributeAnswer(
  String entityName,
  String attributeKey,
  List<(String, String)> lines,
) {
  final parts = lines.map((l) => '${l.$1}: ${l.$2}').join(', ');
  return '$entityName $attributeKey — $parts';
}

/// Formats a concise spoken rule-list answer.
///
/// Layer A of the rule answer path: name-only, no descriptions.
///
/// Examples:
///   0 rules → "I couldn't find any surfaced rules for Carnifex."
///   1 rule  → "Carnifex has Synapse."
///   2 rules → "Carnifex has Synapse and Deadly Demise."
///   3+rules → "Carnifex has Synapse, Shadow in the Warp, and Deadly Demise."
///
/// Future layers (B: rule details, C: filtered views, D: interactions) extend
/// by receiving the same [rules] list and rendering differently — not by
/// changing data extraction.
String formatRuleListAnswer(String entityName, List<RuleDoc> rules) {
  if (rules.isEmpty) {
    return "I couldn't find any surfaced rules for $entityName.";
  }
  final names = rules.map((r) => r.name).toList();
  if (names.length == 1) return '$entityName has ${names[0]}.';
  if (names.length == 2) return '$entityName has ${names[0]} and ${names[1]}.';
  final allButLast = names.take(names.length - 1).join(', ');
  return '$entityName has $allButLast, and ${names.last}.';
}

String _formatDisambiguationPrompt(List<SpokenEntity> entities) {
  final count = entities.length;
  final shown = entities.take(3).map((e) => e.displayName).toList();
  final String nameClause;
  if (shown.length == 2) {
    nameClause = '${shown[0]} and ${shown[1]}';
  } else {
    nameClause = '${shown[0]}, ${shown[1]}, and ${shown[2]}';
  }
  return 'I found $count ${count == 1 ? 'match' : 'matches'}: $nameClause. Which one?';
}

/// Coordinator that turns a voice transcript into a [SpokenResponsePlan].
///
/// Query routing (in order):
/// 1. Active session intercept (name match / cancel / fallthrough).
/// 2. Unknown/empty transcript.
/// 3. Rule-list query detection — bounded explicit patterns only.
/// 4. Attribute question (AssistantQuestionIntent).
/// 5. General search.
///
/// Rule answer path (Layer A — unit rule surface lookup):
///   resolved unit → ruleDocRefs → RuleDoc names → formatted answer.
/// Future layers extend on top without changing the pipeline.
final class VoiceAssistantCoordinator {
  final VoiceSearchFacade _searchFacade;
  final VoiceIntentClassifier _classifier;
  final DomainCanonicalizer _canonicalizer;

  VoiceSelectionSession? _session;
  List<SpokenEntity> _lastEntities = const [];
  SpokenEntity? _lastSelected;

  /// True when the active disambiguation session originated from a rule query.
  /// On entity selection, routes to rule answer instead of "Selected X."
  bool _pendingRuleQuery = false;

  VoiceAssistantCoordinator({
    required VoiceSearchFacade searchFacade,
    VoiceIntentClassifier classifier = const VoiceIntentClassifier(),
    DomainCanonicalizer canonicalizer = const DomainCanonicalizer(),
  })  : _searchFacade = searchFacade,
        _classifier = classifier,
        _canonicalizer = canonicalizer;

  Future<SpokenResponsePlan> handleTranscript({
    required String transcript,
    required Map<String, IndexBundle> slotBundles,
    required List<String> contextHints,
  }) async {
    final intent = _classifier.classify(transcript);

    // 1. Active session: name match → select (or rule answer); cancel; fallthrough.
    if (_session != null) {
      final matched = _matchEntityName(transcript, _lastEntities);
      if (matched != null) {
        final wasRuleQuery = _pendingRuleQuery;
        _session = null;
        _pendingRuleQuery = false;
        _lastSelected = matched;
        if (wasRuleQuery) {
          return _buildRuleListAnswer(matched, slotBundles);
        }
        return SpokenResponsePlan(
          primaryText: 'Selected ${matched.displayName}.',
          entities: [matched],
          selectedIndex: null,
          followUps: const [],
          debugSummary: 'selected:${matched.groupKey}',
        );
      }
      if (intent is DisambiguationCommandIntent &&
          intent.command == DisambiguationCommand.cancel) {
        _session = null;
        _pendingRuleQuery = false;
        return SpokenResponsePlan(
          primaryText: 'Cancelled.',
          entities: const [],
          followUps: const [],
          debugSummary: 'cancelled',
          sessionCleared: true,
        );
      }
      _session = null;
      _pendingRuleQuery = false;
    }

    // 2. Unknown / empty transcript.
    if (intent is UnknownIntent) {
      return SpokenResponsePlan(
        primaryText: "Sorry, I didn't catch that. Please say a search term.",
        entities: const [],
        followUps: const [],
        debugSummary: 'unknown-empty',
        sessionCleared: true,
      );
    }

    // 3. Rule-list query: intercept before attribute handler.
    final ruleEntityQuery = _detectRuleQuery(transcript);
    if (ruleEntityQuery != null) {
      return _handleRuleListQuestion(
        entityQuery: ruleEntityQuery,
        slotBundles: slotBundles,
        contextHints: contextHints,
      );
    }

    // 4. Attribute question.
    if (intent is AssistantQuestionIntent) {
      return _handleAttributeQuestion(
        transcript: transcript,
        slotBundles: slotBundles,
        contextHints: contextHints,
      );
    }

    // 5. General search.
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

  void clearSession() {
    _session = null;
    _pendingRuleQuery = false;
  }

  // ---------------------------------------------------------------------------
  // Rule-query path (Layer A)
  // ---------------------------------------------------------------------------

  /// Detects bounded rule/ability query patterns and returns the entity-name
  /// substring, or null if the transcript is not a rule query.
  ///
  /// Supported patterns (case-insensitive, punctuation-stripped):
  ///   "rules for X"         → X
  ///   "rules of X"          → X
  ///   "what rules does X have"      → X
  ///   "what abilities does X have"  → X
  ///   "abilities for X"     → X
  ///   "abilities of X"      → X
  ///
  /// Only explicit, bounded patterns are matched. No fuzzy or open-ended NLP.
  static String? _detectRuleQuery(String transcript) {
    final cleaned = transcript
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // "what rules does X have" / "what abilities does X have"
    final m1 =
        RegExp(r'^what (?:rules|abilities) does (.+?) have$').firstMatch(cleaned);
    if (m1 != null) return m1.group(1)!.trim();

    // "rules for X" / "rules of X"
    final m2 = RegExp(r'^rules (?:for|of) (.+)$').firstMatch(cleaned);
    if (m2 != null) return m2.group(1)!.trim();

    // "abilities for X" / "abilities of X"
    final m3 = RegExp(r'^abilities (?:for|of) (.+)$').firstMatch(cleaned);
    if (m3 != null) return m3.group(1)!.trim();

    return null;
  }

  /// Handles a rule-list query: resolves entity, then calls [_buildRuleListAnswer].
  ///
  /// Uses the existing entity-resolution path (canonicalize → search →
  /// single/disambig/no-match). If multiple entities match, opens a
  /// disambiguation session with [_pendingRuleQuery] = true so the follow-up
  /// name selection routes back to the rule answer, not "Selected X."
  SpokenResponsePlan _handleRuleListQuestion({
    required String entityQuery,
    required Map<String, IndexBundle> slotBundles,
    required List<String> contextHints,
  }) {
    final canonical = _canonicalizer.canonicalizeQuery(
      entityQuery,
      contextHints: contextHints,
    );
    if (canonical.isEmpty) {
      return SpokenResponsePlan(
        primaryText: "Sorry, I didn't catch that. Please say a unit name.",
        entities: const [],
        followUps: const [],
        debugSummary: 'rule-empty-canonical',
        sessionCleared: true,
      );
    }

    final response = _searchFacade.searchText(slotBundles, canonical);
    _lastEntities = response.entities;

    if (response.entities.isEmpty) {
      _session = null;
      return SpokenResponsePlan(
        primaryText: 'Couldn\'t find "$canonical".',
        entities: const [],
        followUps: const [],
        debugSummary: 'rule-no-results:$canonical',
      );
    }

    if (response.entities.length > 1) {
      _session = VoiceSelectionSession(response.entities);
      _pendingRuleQuery = true;
      return SpokenResponsePlan(
        primaryText: _formatDisambiguationPrompt(response.entities),
        entities: response.entities,
        selectedIndex: 0,
        followUps: response.entities
            .take(3)
            .map((e) => e.displayName.toLowerCase())
            .toList(),
        debugSummary: 'rule-disambiguation:${response.entities.length}',
      );
    }

    final entity = response.entities.first;
    _lastSelected = entity;
    _session = null;
    _pendingRuleQuery = false;
    return _buildRuleListAnswer(entity, slotBundles);
  }

  /// Resolves rule docs for [entity] and returns a formatted rule-list plan.
  ///
  /// This is the Layer A output step. Future layers (detail, filtering,
  /// interaction) extend here by receiving the same [List<RuleDoc>] and
  /// rendering differently.
  SpokenResponsePlan _buildRuleListAnswer(
    SpokenEntity entity,
    Map<String, IndexBundle> slotBundles,
  ) {
    final variant = entity.primaryVariant;
    final bundle = slotBundles[variant.sourceSlotId];

    if (bundle == null) {
      return SpokenResponsePlan(
        primaryText:
            'Found ${entity.displayName} but no data bundle is available.',
        entities: [entity],
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'rule-no-bundle:${entity.groupKey}',
      );
    }

    final unitDoc = bundle.unitByDocId(variant.docId);
    if (unitDoc == null) {
      return SpokenResponsePlan(
        primaryText:
            'Found ${entity.displayName} but could not load unit data.',
        entities: [entity],
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'rule-no-unit-doc:${entity.groupKey}',
      );
    }

    final rules = _extractRulesForUnit(unitDoc, bundle);
    return SpokenResponsePlan(
      primaryText: formatRuleListAnswer(entity.displayName, rules),
      entities: [entity],
      selectedIndex: 0,
      followUps: const [],
      debugSummary: 'rule-answer:${rules.length}:${entity.groupKey}',
    );
  }

  /// Layer A extraction: resolves ruleDocRefs → RuleDocs.
  ///
  /// Refs that don't resolve in this bundle are silently skipped (already
  /// surfaced as IndexDiagnostics during index build). Preserves ref order.
  static List<RuleDoc> _extractRulesForUnit(
    UnitDoc unitDoc,
    IndexBundle bundle,
  ) {
    return unitDoc.ruleDocRefs
        .map(bundle.ruleByDocId)
        .whereType<RuleDoc>()
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Attribute question path
  // ---------------------------------------------------------------------------

  SpokenResponsePlan _handleAttributeQuestion({
    required String transcript,
    required Map<String, IndexBundle> slotBundles,
    required List<String> contextHints,
  }) {
    final normalized = _normalizeForParsing(transcript);

    String? canonicalAttr;
    String? matchedAttrPhrase;
    for (final entry in _kAttributeSynonyms.entries) {
      if (normalized.contains(entry.key)) {
        canonicalAttr = entry.value;
        matchedAttrPhrase = entry.key;
        break;
      }
    }

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

    final response = _searchFacade.searchText(slotBundles, canonical);
    _lastEntities = response.entities;

    if (response.entities.isEmpty) {
      _session = null;
      return SpokenResponsePlan(
        primaryText: 'Couldn\'t find "$canonical".',
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
        followUps: response.entities
            .take(3)
            .map((e) => e.displayName.toLowerCase())
            .toList(),
        debugSummary: 'disambiguation:${response.entities.length}',
      );
    }

    final entity = response.entities.first;
    _lastSelected = entity;
    _session = null;
    final variant = entity.primaryVariant;
    final bundle = slotBundles[variant.sourceSlotId];

    if (bundle == null) {
      return SpokenResponsePlan(
        primaryText:
            'Found ${entity.displayName} but no data bundle is available.',
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

    final weapons = unitDoc.weaponDocRefs
        .map(bundle.weaponByDocId)
        .whereType<WeaponDoc>()
        .toList()
      ..sort((a, b) {
        final cmp = a.name.compareTo(b.name);
        return cmp != 0 ? cmp : a.docId.compareTo(b.docId);
      });

    final unitLines = <(String, String)>[];
    for (final c in unitDoc.characteristics) {
      if (c.name == canonicalAttr) {
        unitLines.add((entity.displayName, c.valueText));
        break;
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

  static String _normalizeForParsing(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

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

  static SpokenEntity? _matchEntityName(
    String transcript,
    List<SpokenEntity> entities,
  ) {
    final lower = transcript.trim().toLowerCase();
    var stripped = lower;
    for (final filler in const ['the ', 'a ', 'an ']) {
      if (stripped.startsWith(filler)) {
        stripped = stripped.substring(filler.length).trim();
        break;
      }
    }
    for (final entity in entities) {
      final name = entity.displayName.toLowerCase();
      if (lower == name || stripped == name) return entity;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // General search path
  // ---------------------------------------------------------------------------

  SpokenResponsePlan _runSearch(
    String canonical,
    Map<String, IndexBundle> slotBundles,
  ) {
    final response = _searchFacade.searchText(slotBundles, canonical);
    _lastEntities = response.entities;

    if (response.entities.isEmpty) {
      _session = null;
      return SpokenResponsePlan(
        primaryText: 'Couldn\'t find "$canonical".',
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

    _session = VoiceSelectionSession(response.entities);
    return SpokenResponsePlan(
      primaryText: _formatDisambiguationPrompt(response.entities),
      entities: response.entities,
      selectedIndex: 0,
      followUps: response.entities
          .take(3)
          .map((e) => e.displayName.toLowerCase())
          .toList(),
      debugSummary: 'disambiguation:${response.entities.length}',
    );
  }
}

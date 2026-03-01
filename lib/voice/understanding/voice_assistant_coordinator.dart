import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

import '../models/disambiguation_command.dart';
import '../models/spoken_entity.dart';
import '../models/spoken_response_plan.dart';
import '../models/voice_intent.dart';
import '../models/voice_selection_session.dart';
import '../voice_search_facade.dart';
import 'domain_canonicalizer.dart';
import 'voice_intent_classifier.dart';

/// Coordinator that turns a voice transcript into a [SpokenResponsePlan].
///
/// Responsibilities (single method [handleTranscript]):
/// 1. Classify transcript intent via [VoiceIntentClassifier].
/// 2. If a disambiguation command arrives with an active session → handle it.
/// 3. Otherwise canonicalize the query via [DomainCanonicalizer].
/// 4. Run [VoiceSearchFacade.searchText] and interpret results:
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
/// canonicalization in Phase 12E). The current implementation is synchronous
/// internally.
final class VoiceAssistantCoordinator {
  final VoiceSearchFacade _searchFacade;
  final VoiceIntentClassifier _classifier;
  final DomainCanonicalizer _canonicalizer;

  VoiceSelectionSession? _session;
  List<SpokenEntity> _lastEntities = const [];

  // ignore: unused_field — reserved for Phase 12E entity detail responses.
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
      return const SpokenResponsePlan(
        primaryText: "Sorry, I didn't catch that. Please say a search term.",
        entities: [],
        followUps: [],
        debugSummary: 'unknown-empty',
      );
    }

    // --- Resolve query text ---
    // DisambiguationCommandIntent with no active session: use raw transcript as query.
    final String queryText;
    if (intent is SearchIntent) {
      queryText = intent.queryText;
    } else if (intent is AssistantQuestionIntent) {
      queryText = intent.queryText;
    } else {
      queryText = transcript.trim();
    }

    final canonical = _canonicalizer.canonicalizeQuery(
      queryText,
      contextHints: contextHints,
    );

    if (canonical.isEmpty) {
      return const SpokenResponsePlan(
        primaryText: "Sorry, I didn't catch that. Please say a search term.",
        entities: [],
        followUps: [],
        debugSummary: 'empty-canonical',
      );
    }

    final plan = _runSearch(canonical, slotBundles);

    // For assistant questions with exactly one result, provide confirmation text.
    if (intent is AssistantQuestionIntent && plan.entities.length == 1) {
      final entity = plan.entities.first;
      _lastSelected = entity;
      return SpokenResponsePlan(
        primaryText:
            'Selected ${entity.displayName}. Detailed spoken stats will come in Phase 12E.',
        entities: plan.entities,
        selectedIndex: 0,
        followUps: const [],
        debugSummary: 'assistant-single:${entity.groupKey}',
      );
    }

    return plan;
  }

  /// Clear the active [VoiceSelectionSession] (e.g. on mode change).
  void clearSession() => _session = null;

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

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
          return const SpokenResponsePlan(
            primaryText: 'Nothing to select.',
            entities: [],
            followUps: [],
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
        return const SpokenResponsePlan(
          primaryText: 'Cancelled.',
          entities: [],
          followUps: [],
          debugSummary: 'cancelled',
        );
    }
  }

  SpokenResponsePlan _planForSession(VoiceSelectionSession session) {
    final entity = session.currentEntity;
    if (entity == null) {
      return const SpokenResponsePlan(
        primaryText: 'No results to navigate.',
        entities: [],
        followUps: [],
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
      primaryText:
          'I found ${response.entities.length} matches. Say "next" or "select".',
      entities: response.entities,
      selectedIndex: 0,
      followUps: const ['next', 'previous', 'select', 'cancel'],
      debugSummary: 'disambiguation:${response.entities.length}',
    );
  }
}

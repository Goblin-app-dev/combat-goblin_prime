import '../models/disambiguation_command.dart';
import '../models/voice_intent.dart';

/// Classifies a raw STT transcript string into a [VoiceIntent].
///
/// Classification order (deterministic):
/// 1. Exact disambiguation command matching (trimmed + lowercased).
///    Multiple surface forms are recognized (e.g. "back" → [DisambiguationCommand.previous]).
/// 2. Assistant-question heuristic: transcript starts with a known question keyword.
/// 3. Default: [SearchIntent] for any non-empty transcript.
/// 4. [UnknownIntent] for empty transcripts only.
///
/// This class is stateless — a single `const` instance can be shared.
final class VoiceIntentClassifier {
  const VoiceIntentClassifier();

  /// Maps exact (trimmed, lowercased) surface forms to [DisambiguationCommand].
  ///
  /// This map is also used by [DomainCanonicalizer.parseCommand].
  static const Map<String, DisambiguationCommand> commandMap = {
    'next': DisambiguationCommand.next,
    'next one': DisambiguationCommand.next,
    'previous': DisambiguationCommand.previous,
    'back': DisambiguationCommand.previous,
    'go back': DisambiguationCommand.previous,
    'select': DisambiguationCommand.select,
    'choose': DisambiguationCommand.select,
    'confirm': DisambiguationCommand.select,
    'cancel': DisambiguationCommand.cancel,
    'stop': DisambiguationCommand.cancel,
    'nevermind': DisambiguationCommand.cancel,
    'never mind': DisambiguationCommand.cancel,
  };

  /// Leading strings (on lowercased transcript) that signal an assistant question.
  static const List<String> _questionPrefixes = [
    'what ',
    'show ',
    'tell me',
    'describe ',
    'how many',
    'how much',
    'does it',
    'can it',
    'list ',
    'get info',
    'abilities',
    'stats',
    'info ',
    'info about',
  ];

  /// Classify [transcript] into a [VoiceIntent].
  VoiceIntent classify(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return UnknownIntent(trimmed);

    final lower = trimmed.toLowerCase();

    // 1. Exact command match.
    final command = commandMap[lower];
    if (command != null) return DisambiguationCommandIntent(command);

    // 2. Assistant-question heuristic.
    for (final prefix in _questionPrefixes) {
      if (lower.startsWith(prefix)) return AssistantQuestionIntent(trimmed);
    }

    // 3. Default: search.
    return SearchIntent(trimmed);
  }
}

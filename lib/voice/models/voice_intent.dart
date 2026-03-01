import 'disambiguation_command.dart';

/// Coarse classification of a voice transcript produced by
/// [VoiceIntentClassifier].
enum VoiceIntentKind {
  /// Transcript is a domain entity search query.
  search,

  /// Transcript is an assistant question about an entity.
  assistantQuestion,

  /// Transcript is a disambiguation navigation command.
  disambiguationCommand,

  /// Transcript did not match any recognized pattern.
  unknown,
}

/// Sealed hierarchy of classified voice intents.
///
/// Produced by [VoiceIntentClassifier.classify]. The [kind] getter provides
/// the enum equivalent for contexts where exhaustive switching is not needed.
sealed class VoiceIntent {
  const VoiceIntent();

  VoiceIntentKind get kind;
}

/// User wants to search for a domain entity by name.
final class SearchIntent extends VoiceIntent {
  final String queryText;
  const SearchIntent(this.queryText);

  @override
  VoiceIntentKind get kind => VoiceIntentKind.search;
}

/// User is asking about an entity (e.g. "what are its abilities?").
final class AssistantQuestionIntent extends VoiceIntent {
  final String queryText;
  const AssistantQuestionIntent(this.queryText);

  @override
  VoiceIntentKind get kind => VoiceIntentKind.assistantQuestion;
}

/// User issued a [DisambiguationCommand] during an active selection session.
final class DisambiguationCommandIntent extends VoiceIntent {
  final DisambiguationCommand command;
  const DisambiguationCommandIntent(this.command);

  @override
  VoiceIntentKind get kind => VoiceIntentKind.disambiguationCommand;
}

/// Transcript did not match any recognized pattern.
///
/// Treated as a search by the coordinator as a fallback, so this kind
/// is only returned for empty transcripts.
final class UnknownIntent extends VoiceIntent {
  final String rawText;
  const UnknownIntent(this.rawText);

  @override
  VoiceIntentKind get kind => VoiceIntentKind.unknown;
}

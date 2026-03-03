import 'text_to_speech_engine.dart';

/// [TextToSpeechEngine] that does nothing.
///
/// Returned by [VoicePlatformFactory.createTtsEngine] on platforms where TTS
/// is unsupported (Web, Desktop). Keeps the voice runtime functional without
/// audio output.
final class NoopTextToSpeechEngine implements TextToSpeechEngine {
  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

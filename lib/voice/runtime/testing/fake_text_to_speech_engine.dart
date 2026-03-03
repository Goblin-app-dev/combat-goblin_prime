import '../text_to_speech_engine.dart';

/// Configurable fake [TextToSpeechEngine] for deterministic testing.
///
/// Records all calls as a flat list of strings:
///   - `'speak:$text'` for each [speak] call
///   - `'stop'` for each [stop] call
///
/// Set [speakDelay] to simulate in-progress playback so that cancellation
/// tests can interleave a [stop] call before [speak] resolves.
final class FakeTextToSpeechEngine implements TextToSpeechEngine {
  /// All calls made to this engine, in order.
  final List<String> calls = [];

  /// If non-null, [speak] waits this duration before returning.
  final Duration? speakDelay;

  FakeTextToSpeechEngine({this.speakDelay});

  @override
  Future<void> speak(String text) async {
    if (speakDelay != null) await Future.delayed(speakDelay!);
    calls.add('speak:$text');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> dispose() async {}
}

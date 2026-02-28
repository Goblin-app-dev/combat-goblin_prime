import 'dart:typed_data';

import 'package:combat_goblin_prime/voice/models/text_candidate.dart';
import 'package:combat_goblin_prime/voice/runtime/speech_to_text_engine.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_listen_mode.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_listen_trigger.dart';

/// Configurable fake [SpeechToTextEngine] for tests.
///
/// Returns a fixed [TextCandidate] on every [transcribe] call.
/// [VoiceRuntimeController] overwrites [TextCandidate.sessionId], [mode],
/// and [trigger] with the actual session context before forwarding the result.
///
/// [callCount] lets tests assert STT was called exactly once per session.
final class FakeSpeechToTextEngine implements SpeechToTextEngine {
  /// Text returned by every [transcribe] call.
  final String fixedText;

  /// Confidence returned by every [transcribe] call.
  final double fixedConfidence;

  FakeSpeechToTextEngine({
    this.fixedText = 'fake transcript',
    this.fixedConfidence = 0.95,
  });

  /// Number of times [transcribe] was called.
  int callCount = 0;

  @override
  Future<TextCandidate> transcribe(
    Uint8List pcm, {
    required List<String> contextHints,
  }) async {
    callCount++;
    // Placeholder sessionId / mode / trigger — controller overwrites them.
    return TextCandidate(
      text: fixedText,
      confidence: fixedConfidence,
      isFinal: true,
      sessionId: 0,
      mode: VoiceListenMode.pushToTalkSearch,
      trigger: VoiceListenTrigger.pushToTalk,
    );
  }
}

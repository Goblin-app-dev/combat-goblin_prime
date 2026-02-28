import 'dart:typed_data';

import '../models/text_candidate.dart';
import '../runtime/speech_to_text_engine.dart';

/// Stub [SpeechToTextEngine] for Phase 12D online ASR.
///
/// Always throws [UnsupportedError]. If [VoiceSettings.onlineSttEnabled] is
/// `true` and this engine is wired, [VoiceRuntimeController] catches the
/// error and transitions to [ErrorState(VoiceStopReason.sttFailed)].
///
/// Replace this class with a real implementation in Phase 12D.
final class OnlineSpeechToTextEngine implements SpeechToTextEngine {
  @override
  Future<TextCandidate> transcribe(
    Uint8List pcm, {
    required List<String> contextHints,
  }) {
    throw UnsupportedError(
      'OnlineSpeechToTextEngine is not implemented in Phase 12C. '
      'Set VoiceSettings.onlineSttEnabled = false or provide a Phase 12D engine.',
    );
  }
}

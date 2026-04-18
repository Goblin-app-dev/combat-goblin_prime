import 'package:flutter/foundation.dart';

import 'runtime/spoken_plan_player.dart';
import 'runtime/voice_listen_trigger.dart';
import 'runtime/voice_runtime_controller.dart';
import 'runtime/voice_runtime_state.dart';
import 'runtime/voice_stop_reason.dart';

/// Implements the single-button voice tap policy: strict finite-state toggle.
///
/// This is the **sole** place that decides what a button tap does. It is called
/// from `_MicButton.onTap` in the UI, and is also directly testable.
///
/// | Runtime state         | TTS active? | Action                              |
/// |-----------------------|-------------|-------------------------------------|
/// | any                   | yes         | await stop TTS → beginListening     |
/// | idle / error          | no          | beginListening                      |
/// | listening             | no          | endListening (→ processing)         |
/// | arming / processing   | no          | **ignored** (in-flight)             |
///
/// **Sequential guarantee (Rule 4):** when [player.isSpeakingNotifier.value]
/// is true, [player.stop()] is fully awaited before
/// [controller.beginListening] is called. Mic capture and TTS playback can
/// never overlap through this path.
///
/// **Defence-in-depth:** both this function and [VoiceRuntimeController]
/// enforce the same invariants independently.  The controller's
/// `beginListening` is a no-op from non-idle states, and `endListening` is a
/// no-op from non-listening states, so a misfired call through any path is
/// harmless.
Future<void> handleVoiceButtonTap({
  required VoiceRuntimeController controller,
  required SpokenPlanPlayer player,
}) async {
  final rs0 = controller.state.value;
  final isSpeaking = player.isSpeakingNotifier.value;
  debugPrint('[VOICE TAP] received — state: ${rs0.runtimeType}, isSpeaking: $isSpeaking');

  if (isSpeaking) {
    debugPrint('[VOICE TAP] action: stop_tts_then_listen');
    await player.stop();
    final rs = controller.state.value;
    if (rs is IdleState || rs is ErrorState) {
      await controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
    }
    return;
  }

  final rs = controller.state.value;
  if (rs is ListeningState) {
    debugPrint('[VOICE TAP] action: stop_listening');
    await controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
  } else if (rs is IdleState || rs is ErrorState) {
    debugPrint('[VOICE TAP] action: start_listening');
    await controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
  } else {
    debugPrint('[VOICE TAP] action: noop (${rs.runtimeType})');
  }
}

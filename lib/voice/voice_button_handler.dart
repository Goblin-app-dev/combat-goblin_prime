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
  // Speaking takes priority regardless of controller state: stop TTS first,
  // then begin listening only if the controller is in a startable state.
  // The two awaits are sequential — no concurrent mic + TTS overlap.
  if (player.isSpeakingNotifier.value) {
    await player.stop();
    final rs = controller.state.value;
    if (rs is IdleState || rs is ErrorState) {
      await controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
    }
    return;
  }

  final rs = controller.state.value;
  if (rs is ListeningState) {
    await controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
  } else if (rs is IdleState || rs is ErrorState) {
    await controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
  }
  // ArmingState, ProcessingState → no-op.
  // Controller guards also fire (beginListening/endListening from wrong state
  // are no-ops), providing a second layer of protection.
}

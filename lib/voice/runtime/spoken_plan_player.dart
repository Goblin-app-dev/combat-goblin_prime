import 'package:flutter/foundation.dart';

import '../models/spoken_response_plan.dart';
import '../settings/voice_settings.dart';
import 'text_to_speech_engine.dart';

/// Converts a [SpokenResponsePlan] into deterministic audible speech.
///
/// **Concurrency rule:** at most one playback active at a time. Calling
/// [play] while speech is in progress cancels the previous playback
/// immediately before starting the new one. No queueing.
///
/// **Cancellation:** a monotonic [_activePlaybackToken] is incremented on
/// every [play] and [stop] call. After each async suspension point the
/// in-flight call checks whether its token is still current; if not, it
/// returns without speaking further text. No randomness, no DateTime stored.
///
/// **Boot safety:** [TextToSpeechEngine.speak] is never called during
/// construction. The engine lazy-initialises on first use inside the adapter.
///
/// **Speaking state:** [isSpeakingNotifier] reflects whether TTS is actively
/// playing. Set to `true` at the start of [play] (when output is enabled),
/// set to `false` synchronously by [stop] and at natural completion of [play].
/// UI can subscribe to rebuild the voice button without a separate listener.
final class SpokenPlanPlayer {
  final TextToSpeechEngine _engine;
  final VoiceSettings _settings;

  int _activePlaybackToken = 0;

  /// Whether TTS output is currently active.
  ///
  /// `true` from the start of [play] (when [VoiceSettings.isSpokenOutputEnabled]
  /// is true) until [stop] is called or [play] completes naturally.
  /// Never true when [VoiceSettings.isSpokenOutputEnabled] is false.
  final ValueNotifier<bool> isSpeakingNotifier = ValueNotifier(false);

  SpokenPlanPlayer({
    required TextToSpeechEngine engine,
    required VoiceSettings settings,
  })  : _engine = engine,
        _settings = settings;

  /// Speaks [plan.primaryText] and, if [VoiceSettings.speakFollowUps] is
  /// enabled, each follow-up in list order.
  ///
  /// If [VoiceSettings.isSpokenOutputEnabled] is false this is a no-op.
  /// Any previously active playback is stopped first.
  Future<void> play(SpokenResponsePlan plan) async {
    if (!_settings.isSpokenOutputEnabled) return;

    isSpeakingNotifier.value = true;
    final myToken = ++_activePlaybackToken;

    // Enforce concurrency rule: cancel any in-flight playback.
    await _engine.stop();
    if (myToken != _activePlaybackToken) return;

    await _engine.speak(plan.primaryText);
    if (myToken != _activePlaybackToken) return;

    if (_settings.speakFollowUps) {
      for (final followUp in plan.followUps) {
        if (myToken != _activePlaybackToken) return;
        await _engine.speak(followUp);
      }
    }

    // Natural completion: clear speaking state only if we're still the
    // active playback (not preempted by a newer play() or stop() call).
    if (myToken == _activePlaybackToken) {
      isSpeakingNotifier.value = false;
    }
  }

  /// Stops any ongoing playback immediately.
  ///
  /// Part of the stop funnel: must be called whenever the voice runtime
  /// transitions to listening or the user explicitly cancels.
  /// Clears [isSpeakingNotifier] synchronously before awaiting the engine.
  Future<void> stop() async {
    isSpeakingNotifier.value = false;
    _activePlaybackToken++;
    await _engine.stop();
  }

  /// Stops playback and releases all engine resources.
  Future<void> dispose() async {
    isSpeakingNotifier.value = false;
    isSpeakingNotifier.dispose();
    _activePlaybackToken++;
    await _engine.dispose();
  }
}

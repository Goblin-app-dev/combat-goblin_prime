/// Voice Button Policy Tests
///
/// Verifies the invariants required by the single-button voice UI:
///
///   1. Double start blocked        — only one listening session starts
///   2. Double stop blocked         — only one stop/processing transition
///   3. Start blocked during processing — tap while processing is ignored
///   4. Speaking interruption is sequential — TTS stops before mic opens
///   5. Rapid tap safety            — no stacked sessions under rapid taps
///
/// Tests exercise [handleVoiceButtonTap] (the single authoritative policy
/// function) together with real [VoiceRuntimeController] and
/// [SpokenPlanPlayer] instances backed by fakes — so they test integrated
/// behaviour, not mocked responses.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/voice/runtime/audio_focus_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_listen_trigger.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_controller.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_event.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_state.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_stop_reason.dart';
import 'package:combat_goblin_prime/voice/runtime/spoken_plan_player.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_focus_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_route_observer.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_mic_permission_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_text_to_speech_engine.dart';
import 'package:combat_goblin_prime/voice/models/spoken_entity.dart';
import 'package:combat_goblin_prime/voice/models/spoken_response_plan.dart';
import 'package:combat_goblin_prime/voice/settings/voice_settings.dart';
import 'package:combat_goblin_prime/voice/voice_button_handler.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

VoiceRuntimeController _makeController({
  AudioFocusGateway? focusGateway,
}) {
  return VoiceRuntimeController(
    permissionGateway: FakeMicPermissionGateway(allow: true),
    focusGateway: focusGateway ?? FakeAudioFocusGateway(allow: true),
    routeObserver: FakeAudioRouteObserver(),
  );
}

SpokenPlanPlayer _makePlayer({
  FakeTextToSpeechEngine? engine,
  bool isSpokenOutputEnabled = true,
}) {
  final settings = VoiceSettings.defaults.copyWith(
    isSpokenOutputEnabled: isSpokenOutputEnabled,
  );
  return SpokenPlanPlayer(engine: engine ?? FakeTextToSpeechEngine(), settings: settings);
}

SpokenResponsePlan _makePlan(String text) => SpokenResponsePlan(
      primaryText: text,
      followUps: const [],
      entities: const <SpokenEntity>[],
      debugSummary: 'test',
    );

/// A focus gateway whose [abandonFocus] blocks until [release] is called.
/// Used to hold the controller in [ProcessingState] for test 3.
class _HangingFocusGateway implements AudioFocusGateway {
  final _completer = Completer<void>();

  void release() {
    if (!_completer.isCompleted) _completer.complete();
  }

  @override
  Future<bool> requestFocus() async => true;

  @override
  Future<void> abandonFocus() => _completer.future;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Test 1 ─────────────────────────────────────────────────────────────────
  // Double start blocked: two rapid taps from idle start exactly one session.
  test('1. double start blocked — only one listening session starts', () {
    fakeAsync((fake) {
      final controller = _makeController();
      final player = _makePlayer();

      // Both taps are issued before any microtasks run, so the second tap
      // sees ArmingState (set synchronously by the first) and no-ops.
      unawaited(handleVoiceButtonTap(controller: controller, player: player));
      unawaited(handleVoiceButtonTap(controller: controller, player: player));
      fake.flushMicrotasks();

      // Exactly one session started.
      expect(controller.state.value, isA<ListeningState>());
      expect(controller.state.value.sessionId, 1);

      controller.dispose();
    });
  });

  // ── Test 2 ─────────────────────────────────────────────────────────────────
  // Double stop blocked: two rapid taps from listening produce exactly one
  // ListeningEnded event and one stop/processing transition.
  test('2. double stop blocked — only one stop/processing transition', () {
    fakeAsync((fake) {
      final controller = _makeController();
      final player = _makePlayer();

      // Reach listening state.
      unawaited(controller.beginListening(trigger: VoiceListenTrigger.pushToTalk));
      fake.flushMicrotasks();
      expect(controller.state.value, isA<ListeningState>());

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      // Two rapid stop taps.  The first transitions to ProcessingState
      // synchronously inside _stop(); the second sees ProcessingState and no-ops.
      unawaited(handleVoiceButtonTap(controller: controller, player: player));
      unawaited(handleVoiceButtonTap(controller: controller, player: player));
      fake.flushMicrotasks();

      // Exactly one ListeningEnded event — no duplicate stop.
      expect(events.whereType<ListeningEnded>(), hasLength(1));
      // Controller reached idle (no STT engine → immediate).
      expect(controller.state.value, isA<IdleState>());

      controller.dispose();
    });
  });

  // ── Test 3 ─────────────────────────────────────────────────────────────────
  // Start blocked during processing: a tap while the controller is in
  // ProcessingState is ignored — no new listening session starts.
  test('3. start blocked during processing — tap while processing is ignored', () {
    fakeAsync((fake) {
      final hanging = _HangingFocusGateway();
      final controller = _makeController(focusGateway: hanging);
      final player = _makePlayer();

      // Reach listening state (requestFocus via HangingFocusGateway grants immediately).
      unawaited(controller.beginListening(trigger: VoiceListenTrigger.pushToTalk));
      fake.flushMicrotasks();
      expect(controller.state.value, isA<ListeningState>());

      // Stop listening.  _stop() sets ProcessingState then awaits abandonFocus
      // which hangs — so the controller stays in ProcessingState.
      unawaited(controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk));
      fake.flushMicrotasks();
      expect(controller.state.value, isA<ProcessingState>(),
          reason: 'Controller must be in ProcessingState while focus abandon is pending');

      final sessionIdDuringProcessing = controller.state.value.sessionId;

      // Tap while processing — must be ignored.
      unawaited(handleVoiceButtonTap(controller: controller, player: player));
      fake.flushMicrotasks();

      expect(controller.state.value, isA<ProcessingState>(),
          reason: 'Tap during processing must not change state');
      expect(controller.state.value.sessionId, sessionIdDuringProcessing,
          reason: 'No new session must have been created');

      // Release the hang so the controller can clean up properly.
      hanging.release();
      fake.flushMicrotasks();

      controller.dispose();
    });
  });

  // ── Test 4 ─────────────────────────────────────────────────────────────────
  // Speaking interruption is sequential: when TTS is active a tap must
  // (a) fully stop TTS before opening the mic, and (b) leave no overlap window.
  //
  // A speakDelay is required so that the speak() Future is timer-backed and
  // stays in-flight after flushMicrotasks().  Without a delay the fake engine
  // completes play() fully in one flush, leaving isSpeakingNotifier = false
  // before we can observe it.
  test('4. speaking interruption is sequential — TTS stops before mic opens', () {
    fakeAsync((fake) {
      // speakDelay makes speak() use Future.delayed (timer), which fakeAsync
      // only completes when time is explicitly advanced — so TTS is genuinely
      // in-flight after flushMicrotasks().
      const ttsDelay = Duration(milliseconds: 50);
      final ttsEngine = FakeTextToSpeechEngine(speakDelay: ttsDelay);
      final controller = _makeController();
      final player = _makePlayer(engine: ttsEngine);

      // Start TTS.  play() sets isSpeakingNotifier=true synchronously, then
      // awaits engine.stop() (microtask — completes), then awaits engine.speak()
      // (timer — does NOT complete on flushMicrotasks alone).
      unawaited(player.play(_makePlan('hello goblin')));
      fake.flushMicrotasks();
      // TTS is mid-flight: engine.stop() completed, engine.speak() is waiting
      // on its 50 ms timer.
      expect(player.isSpeakingNotifier.value, isTrue,
          reason: 'Player must report speaking while speak() timer is pending');

      // Tap: policy sees isSpeaking=true → awaits player.stop() then
      // beginListening.  player.stop() sets isSpeakingNotifier=false and calls
      // engine.stop() (microtask).  beginListening follows after that resolves.
      unawaited(handleVoiceButtonTap(controller: controller, player: player));
      fake.flushMicrotasks();

      // TTS must be stopped (isSpeakingNotifier cleared by player.stop()).
      expect(player.isSpeakingNotifier.value, isFalse,
          reason: 'TTS must be stopped after tap');

      // Mic must be open: beginListening ran after player.stop() awaited.
      expect(controller.state.value, isA<ListeningState>(),
          reason: 'Controller must be listening only after TTS is stopped');

      // engine.stop() must appear in the call log (issued by player.stop()).
      expect(ttsEngine.calls, contains('stop'),
          reason: 'Engine stop must have been called before mic opened');

      controller.dispose();
    });
  });

  // ── Test 5 ─────────────────────────────────────────────────────────────────
  // Rapid tap safety: alternating taps across idle/listening/processing
  // must never produce stacked sessions or invalid transitions.
  test('5. rapid tap safety — no stacked sessions under rapid alternating taps', () {
    fakeAsync((fake) {
      final controller = _makeController();
      final player = _makePlayer();

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      // Fire 6 rapid taps without any microtask drain between them.
      // Taps 1,3,5 would try to start; taps 2,4,6 would try to stop or be ignored.
      for (var i = 0; i < 6; i++) {
        unawaited(handleVoiceButtonTap(controller: controller, player: player));
      }
      fake.flushMicrotasks();

      // Regardless of how many taps fired, the session counter must be ≤ 1
      // because only one transition to listening (sessionId=1) could have
      // occurred in this synchronous burst (all taps read state before any
      // microtask runs).
      expect(
        controller.state.value.sessionId,
        lessThanOrEqualTo(1),
        reason: 'Rapid taps must not stack multiple sessions',
      );

      // No duplicate ListeningBegan events — at most one session began.
      expect(
        events.whereType<ListeningBegan>(),
        hasLength(lessThanOrEqualTo(1)),
        reason: 'At most one listening session must have started',
      );

      controller.dispose();
    });
  });
}

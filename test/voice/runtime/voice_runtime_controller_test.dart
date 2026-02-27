import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/voice/runtime/voice_listen_mode.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_listen_trigger.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_controller.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_event.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_state.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_stop_reason.dart';
import 'package:combat_goblin_prime/voice/runtime/wake_word_detector.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_focus_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_route_observer.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_mic_permission_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_wake_word_detector.dart';

/// Helper: build a controller with all-grant fakes and optional overrides.
VoiceRuntimeController _makeController({
  bool allowPermission = true,
  bool allowFocus = true,
  FakeWakeWordDetector? wakeDetector,
  FakeAudioRouteObserver? routeObserver,
  Duration listenTimeout = const Duration(seconds: 6),
}) {
  return VoiceRuntimeController(
    permissionGateway: FakeMicPermissionGateway(allow: allowPermission),
    focusGateway: FakeAudioFocusGateway(allow: allowFocus),
    routeObserver: routeObserver ?? FakeAudioRouteObserver(),
    wakeWordDetector: wakeDetector,
    listenTimeout: listenTimeout,
  );
}

void main() {
  // ── Test 1 ────────────────────────────────────────────────────────────────
  test('1. initial state is IdleState', () {
    final controller = _makeController();
    expect(controller.state.value, isA<IdleState>());
    controller.dispose();
  });

  // ── Test 2 ────────────────────────────────────────────────────────────────
  test('2. setMode changes mode without side effects when idle', () {
    final controller = _makeController();
    expect(controller.mode, VoiceListenMode.pushToTalkSearch);

    controller.setMode(VoiceListenMode.handsFreeAssistant);

    expect(controller.mode, VoiceListenMode.handsFreeAssistant);
    expect(controller.modeNotifier.value, VoiceListenMode.handsFreeAssistant);
    // State must still be idle — setMode does not open a session.
    expect(controller.state.value, isA<IdleState>());
    controller.dispose();
  });

  // ── Test 3 ────────────────────────────────────────────────────────────────
  test('3. beginListening transitions idle → arming → listening', () {
    fakeAsync((fake) {
      final controller = _makeController();
      final states = <Type>[];
      controller.state.addListener(() {
        states.add(controller.state.value.runtimeType);
      });

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);

      // Drain microtasks so async awaits inside beginListening complete.
      fake.flushMicrotasks();

      // ArmingState → ListeningState (IdleState is initial, not notified)
      expect(states, [ArmingState, ListeningState]);
      expect(controller.state.value, isA<ListeningState>());

      final listening = controller.state.value as ListeningState;
      expect(listening.mode, VoiceListenMode.pushToTalkSearch);
      expect(listening.trigger, VoiceListenTrigger.pushToTalk);

      controller.dispose();
    });
  });

  // ── Test 4 ────────────────────────────────────────────────────────────────
  test('4. endListening produces ListeningEnded with correct stop reason', () {
    fakeAsync((fake) {
      final controller = _makeController();
      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      expect(controller.state.value, isA<ListeningState>());

      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      expect(controller.state.value, isA<IdleState>());

      final ended = events.whereType<ListeningEnded>().single;
      expect(ended.reason, VoiceStopReason.userReleasedPushToTalk);

      controller.dispose();
    });
  });

  // ── Test 5 ────────────────────────────────────────────────────────────────
  test('5. handsFreeAssistant: wake event triggers beginListening', () {
    fakeAsync((fake) {
      final fakeDetector = FakeWakeWordDetector();
      final controller = _makeController(wakeDetector: fakeDetector);
      controller.setMode(VoiceListenMode.handsFreeAssistant);

      fakeDetector.simulateWake(const WakeEvent(phrase: 'hey goblin'));
      fake.flushMicrotasks();

      expect(controller.state.value, isA<ListeningState>());
      final listening = controller.state.value as ListeningState;
      expect(listening.trigger, VoiceListenTrigger.wakeWord);

      controller.dispose();
    });
  });

  // ── Test 6 ────────────────────────────────────────────────────────────────
  test('6. pushToTalkSearch: wake event is ignored (no state change)', () {
    fakeAsync((fake) {
      final fakeDetector = FakeWakeWordDetector();
      final controller = _makeController(wakeDetector: fakeDetector);
      // Default mode is pushToTalkSearch.
      expect(controller.mode, VoiceListenMode.pushToTalkSearch);

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      fakeDetector.simulateWake(const WakeEvent(phrase: 'hey goblin'));
      fake.flushMicrotasks();

      // State must remain idle; no ListeningBegan event.
      expect(controller.state.value, isA<IdleState>());
      expect(events.whereType<ListeningBegan>(), isEmpty);

      controller.dispose();
    });
  });

  // ── Test 7 ────────────────────────────────────────────────────────────────
  test('7. timeout stop reason is wakeTimeout in handsFreeAssistant', () {
    fakeAsync((fake) {
      final controller = _makeController(
        listenTimeout: const Duration(seconds: 1),
      );
      controller.setMode(VoiceListenMode.handsFreeAssistant);

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      controller.beginListening(trigger: VoiceListenTrigger.wakeWord);
      fake.flushMicrotasks();
      expect(controller.state.value, isA<ListeningState>());

      // Advance time past the 1-second timeout.
      fake.elapse(const Duration(seconds: 2));
      fake.flushMicrotasks();

      expect(controller.state.value, isA<IdleState>());
      final ended = events.whereType<ListeningEnded>().single;
      expect(ended.reason, VoiceStopReason.wakeTimeout);

      controller.dispose();
    });
  });

  // ── Test 8 ────────────────────────────────────────────────────────────────
  test('8. routeChanged while listening stops with routeChanged', () {
    fakeAsync((fake) {
      final routeObserver = FakeAudioRouteObserver();
      final controller = _makeController(routeObserver: routeObserver);

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      expect(controller.state.value, isA<ListeningState>());

      routeObserver.simulateRouteChange();
      fake.flushMicrotasks();

      expect(controller.state.value, isA<IdleState>());
      final ended = events.whereType<ListeningEnded>().single;
      expect(ended.reason, VoiceStopReason.routeChanged);

      controller.dispose();
    });
  });

  // ── Test 9 ────────────────────────────────────────────────────────────────
  test('9. permissionDenied transitions to ErrorState with permissionDenied reason', () {
    fakeAsync((fake) {
      final controller = _makeController(allowPermission: false);

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();

      expect(controller.state.value, isA<ErrorState>());
      final error = controller.state.value as ErrorState;
      expect(error.reason, VoiceStopReason.permissionDenied);

      expect(events.whereType<PermissionDenied>(), isNotEmpty);
      expect(events.whereType<ErrorRaised>().single.reason,
          VoiceStopReason.permissionDenied);

      controller.dispose();
    });
  });

  // ── Test 10 ───────────────────────────────────────────────────────────────
  test('10. focusDenied: AudioFocusDenied event emitted, state becomes ErrorState', () {
    fakeAsync((fake) {
      final controller = _makeController(allowFocus: false);

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();

      expect(controller.state.value, isA<ErrorState>());
      final error = controller.state.value as ErrorState;
      expect(error.reason, VoiceStopReason.focusLost);

      expect(events.whereType<AudioFocusDenied>(), isNotEmpty);
      expect(events.whereType<ErrorRaised>().single.reason,
          VoiceStopReason.focusLost);

      controller.dispose();
    });
  });

  // ── Test 11 ───────────────────────────────────────────────────────────────
  test('11. determinism: same event sequence produces same final state', () {
    fakeAsync((fake) {
      VoiceRuntimeState runSequence() {
        final routeObserver = FakeAudioRouteObserver();
        final controller = _makeController(routeObserver: routeObserver);
        controller.setMode(VoiceListenMode.pushToTalkSearch);

        controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
        fake.flushMicrotasks();

        controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
        fake.flushMicrotasks();

        final result = controller.state.value;
        controller.dispose();
        return result;
      }

      final stateA = runSequence();
      final stateB = runSequence();

      expect(stateA.runtimeType, stateB.runtimeType);
      expect(stateA, isA<IdleState>());
      expect(stateB, isA<IdleState>());
    });
  });

  // ── Test 12 ───────────────────────────────────────────────────────────────
  test('12. endListening in IdleState is a no-op', () {
    fakeAsync((fake) {
      final controller = _makeController();
      expect(controller.state.value, isA<IdleState>());

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      // endListening while idle must be a complete no-op.
      controller.endListening(reason: VoiceStopReason.userCancelled);
      fake.flushMicrotasks();

      expect(controller.state.value, isA<IdleState>());
      expect(events, isEmpty);

      controller.dispose();
    });
  });
}

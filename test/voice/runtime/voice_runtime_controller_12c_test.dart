import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/voice/models/text_candidate.dart';
import 'package:combat_goblin_prime/voice/runtime/speech_to_text_engine.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_capture_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_focus_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_audio_route_observer.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_mic_permission_gateway.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_speech_to_text_engine.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_wake_word_detector.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_listen_mode.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_listen_trigger.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_controller.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_event.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_runtime_state.dart';
import 'package:combat_goblin_prime/voice/runtime/voice_stop_reason.dart';

/// Helper: standard all-grant controller with 12C adapters.
VoiceRuntimeController _make({
  bool allowPermission = true,
  bool allowFocus = true,
  FakeAudioCaptureGateway? capture,
  SpeechToTextEngine? stt,
  FakeWakeWordDetector? wakeDetector,
  FakeAudioRouteObserver? routeObserver,
  Duration listenTimeout = const Duration(seconds: 6),
  Duration maxCaptureDuration = const Duration(seconds: 15),
}) {
  return VoiceRuntimeController(
    permissionGateway: FakeMicPermissionGateway(allow: allowPermission),
    focusGateway: FakeAudioFocusGateway(allow: allowFocus),
    routeObserver: routeObserver ?? FakeAudioRouteObserver(),
    captureGateway: capture,
    sttEngine: stt,
    wakeWordDetector: wakeDetector,
    listenTimeout: listenTimeout,
    maxCaptureDuration: maxCaptureDuration,
  );
}

void main() {
  // ── Test 16 ───────────────────────────────────────────────────────────────
  test('16. captureGateway.start called when beginListening succeeds', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final controller = _make(capture: capture);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();

      expect(controller.state.value, isA<ListeningState>());
      expect(capture.startCallCount, 1);

      controller.dispose();
    });
  });

  // ── Test 17 ───────────────────────────────────────────────────────────────
  test('17. captureGateway.stop called on endListening', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final controller = _make(capture: capture);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();

      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      expect(capture.stopCallCount, 1);

      controller.dispose();
    });
  });

  // ── Test 18 ───────────────────────────────────────────────────────────────
  test('18. STT called once per session; TextCandidateProducedEvent emitted', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final stt = FakeSpeechToTextEngine(fixedText: 'space marines');
      final controller = _make(capture: capture, stt: stt);

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      TextCandidate? receivedCandidate;
      controller.onTextCandidate = (c) => receivedCandidate = c;

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();

      // Push one non-empty frame so the buffer is non-empty.
      capture.pushFrame(Uint8List.fromList(List.filled(32, 0)));

      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      // STT was called exactly once.
      expect(stt.callCount, 1);

      // TextCandidateProducedEvent was emitted.
      final produced = events.whereType<TextCandidateProducedEvent>().single;
      expect(produced.candidate.text, 'space marines');

      // onTextCandidate callback was invoked.
      expect(receivedCandidate, isNotNull);
      expect(receivedCandidate!.text, 'space marines');

      // Final state is IdleState.
      expect(controller.state.value, isA<IdleState>());

      controller.dispose();
    });
  });

  // ── Test 19 ───────────────────────────────────────────────────────────────
  test('19. capture limit: exceeds maxCaptureDuration → captureLimitReached', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final controller = _make(
        capture: capture,
        maxCaptureDuration: const Duration(seconds: 3),
      );

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      expect(controller.state.value, isA<ListeningState>());

      // Advance past the 3-second capture limit.
      fake.elapse(const Duration(seconds: 4));
      fake.flushMicrotasks();

      expect(controller.state.value, isA<IdleState>());
      final ended = events.whereType<ListeningEnded>().single;
      expect(ended.reason, VoiceStopReason.captureLimitReached);

      controller.dispose();
    });
  });

  // ── Test 20 ───────────────────────────────────────────────────────────────
  test('20. STT empty buffer: no STT call; state → IdleState', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final stt = FakeSpeechToTextEngine();
      final controller = _make(capture: capture, stt: stt);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();

      // End without pushing any frames → empty buffer.
      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      // STT must NOT be called for empty buffer.
      expect(stt.callCount, 0);
      expect(controller.state.value, isA<IdleState>());

      controller.dispose();
    });
  });

  // ── Test 21 ───────────────────────────────────────────────────────────────
  test('21. STT failure → ErrorState(sttFailed)', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final stt = _ThrowingSttEngine();
      final controller = _make(capture: capture, stt: stt);

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();

      capture.pushFrame(Uint8List.fromList(List.filled(32, 0)));

      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      expect(controller.state.value, isA<ErrorState>());
      final error = controller.state.value as ErrorState;
      expect(error.reason, VoiceStopReason.sttFailed);

      final raised = events.whereType<ErrorRaised>().single;
      expect(raised.reason, VoiceStopReason.sttFailed);

      controller.dispose();
    });
  });

  // ── Test 22 ───────────────────────────────────────────────────────────────
  test('22. TextCandidate.sessionId matches the session that produced it', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final stt = FakeSpeechToTextEngine();
      final controller = _make(capture: capture, stt: stt);

      int? candidateSessionId;
      controller.onTextCandidate = (c) => candidateSessionId = c.sessionId;

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      capture.pushFrame(Uint8List.fromList(List.filled(32, 0)));
      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      expect(candidateSessionId, isNotNull);
      // sessionId is 1 because this is the first session.
      expect(candidateSessionId, 1);

      controller.dispose();
    });
  });

  // ── Test 23 ───────────────────────────────────────────────────────────────
  test('23. TextCandidate.mode and trigger match the session context', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final stt = FakeSpeechToTextEngine();
      final controller = _make(capture: capture, stt: stt);

      TextCandidate? receivedCandidate;
      controller.onTextCandidate = (c) => receivedCandidate = c;

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      capture.pushFrame(Uint8List.fromList(List.filled(32, 0)));
      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      expect(receivedCandidate!.mode, VoiceListenMode.pushToTalkSearch);
      expect(receivedCandidate!.trigger, VoiceListenTrigger.pushToTalk);

      controller.dispose();
    });
  });

  // ── Test 24 ───────────────────────────────────────────────────────────────
  test('24. ordering: state is IdleState when TextCandidateProducedEvent fires (Rule A)', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final stt = FakeSpeechToTextEngine();
      final controller = _make(capture: capture, stt: stt);

      VoiceRuntimeState? stateAtProduced;
      controller.events.listen((event) {
        if (event is TextCandidateProducedEvent) {
          stateAtProduced = controller.state.value;
        }
      });

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      capture.pushFrame(Uint8List.fromList(List.filled(32, 0)));
      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      // Rule A: state must already be IdleState at the moment event fires.
      expect(stateAtProduced, isA<IdleState>());

      controller.dispose();
    });
  });

  // ── Test 25 ───────────────────────────────────────────────────────────────
  test('25. second session: new sessionId; STT called once per session', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final stt = FakeSpeechToTextEngine();
      final controller = _make(capture: capture, stt: stt);

      final sessionIds = <int>[];
      controller.onTextCandidate = (c) => sessionIds.add(c.sessionId);

      // Session 1
      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      capture.pushFrame(Uint8List.fromList(List.filled(16, 1)));
      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      // Session 2
      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      capture.pushFrame(Uint8List.fromList(List.filled(16, 2)));
      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();

      expect(stt.callCount, 2);
      expect(sessionIds, [1, 2]);

      controller.dispose();
    });
  });

  // ── Test 26 ───────────────────────────────────────────────────────────────
  test('26. wakeEngineUnavailable: setMode(handsFreeAssistant) without detector emits ErrorRaised then returns to IdleState', () {
    fakeAsync((fake) {
      // No wakeDetector injected.
      final controller = _make();
      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      controller.setMode(VoiceListenMode.handsFreeAssistant);
      fake.flushMicrotasks();

      // Mode is set.
      expect(controller.mode, VoiceListenMode.handsFreeAssistant);
      // Final state is IdleState (momentary ErrorState resolved).
      expect(controller.state.value, isA<IdleState>());
      // ErrorRaised was emitted with wakeEngineUnavailable.
      final raised = events.whereType<ErrorRaised>().single;
      expect(raised.reason, VoiceStopReason.wakeEngineUnavailable);

      controller.dispose();
    });
  });

  // ── Test 27 ───────────────────────────────────────────────────────────────
  test('27. wakeEngineUnavailable: PTT still works after setMode(handsFreeAssistant) without detector', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final stt = FakeSpeechToTextEngine();
      final controller = _make(capture: capture, stt: stt);

      controller.setMode(VoiceListenMode.handsFreeAssistant);
      fake.flushMicrotasks();
      expect(controller.state.value, isA<IdleState>());

      // PTT beginListening must still work despite no wake engine.
      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      expect(controller.state.value, isA<ListeningState>());

      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();
      expect(controller.state.value, isA<IdleState>());

      controller.dispose();
    });
  });

  // ── Test 28 ───────────────────────────────────────────────────────────────
  test('28. frames from previous session are not included in next session buffer', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final stt = FakeSpeechToTextEngine();
      final controller = _make(capture: capture, stt: stt);

      final bufferSizes = <int>[];
      int capturedBytes = 0;
      controller.onAudioCaptured = (buf) => capturedBytes = buf.length;

      // Session 1: push 32 bytes.
      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      capture.pushFrame(Uint8List.fromList(List.filled(32, 1)));
      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();
      bufferSizes.add(capturedBytes);

      // Session 2: push 16 bytes. Buffer must NOT include session 1 bytes.
      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      capture.pushFrame(Uint8List.fromList(List.filled(16, 2)));
      controller.endListening(reason: VoiceStopReason.userReleasedPushToTalk);
      fake.flushMicrotasks();
      bufferSizes.add(capturedBytes);

      expect(bufferSizes[0], 32);
      expect(bufferSizes[1], 16); // Must NOT be 48

      controller.dispose();
    });
  });

  // ── Test 29 ───────────────────────────────────────────────────────────────
  test('29. capture limit fires in pushToTalk mode too', () {
    fakeAsync((fake) {
      final capture = FakeAudioCaptureGateway();
      final controller = _make(
        capture: capture,
        maxCaptureDuration: const Duration(seconds: 2),
      );

      final events = <VoiceRuntimeEvent>[];
      controller.events.listen(events.add);

      // PTT mode (default).
      expect(controller.mode, VoiceListenMode.pushToTalkSearch);

      controller.beginListening(trigger: VoiceListenTrigger.pushToTalk);
      fake.flushMicrotasks();
      expect(controller.state.value, isA<ListeningState>());

      // Advance past the 2-second capture cap without releasing PTT.
      fake.elapse(const Duration(seconds: 3));
      fake.flushMicrotasks();

      expect(controller.state.value, isA<IdleState>());
      final ended = events.whereType<ListeningEnded>().single;
      expect(ended.reason, VoiceStopReason.captureLimitReached);

      controller.dispose();
    });
  });
}

// ---------------------------------------------------------------------------
// Helper: STT engine that always throws
// ---------------------------------------------------------------------------

class _ThrowingSttEngine implements SpeechToTextEngine {
  @override
  Future<TextCandidate> transcribe(
    Uint8List pcm, {
    required List<String> contextHints,
  }) async {
    throw StateError('STT engine crashed');
  }
}

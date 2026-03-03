import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:combat_goblin_prime/voice/models/spoken_entity.dart';
import 'package:combat_goblin_prime/voice/models/spoken_response_plan.dart';
import 'package:combat_goblin_prime/voice/runtime/spoken_plan_player.dart';
import 'package:combat_goblin_prime/voice/runtime/testing/fake_text_to_speech_engine.dart';
import 'package:combat_goblin_prime/voice/settings/voice_settings.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SpokenResponsePlan _makePlan(
  String primaryText, {
  List<String> followUps = const [],
}) {
  return SpokenResponsePlan(
    primaryText: primaryText,
    followUps: followUps,
    entities: const <SpokenEntity>[],
    debugSummary: 'test-plan',
  );
}

SpokenPlanPlayer _makePlayer(
  FakeTextToSpeechEngine engine, {
  bool isSpokenOutputEnabled = true,
  bool speakFollowUps = false,
}) {
  final settings = VoiceSettings.defaults.copyWith(
    isSpokenOutputEnabled: isSpokenOutputEnabled,
    speakFollowUps: speakFollowUps,
  );
  return SpokenPlanPlayer(engine: engine, settings: settings);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Test 1 ────────────────────────────────────────────────────────────────
  test('1. speaks only primaryText when speakFollowUps is disabled', () {
    fakeAsync((fake) {
      final engine = FakeTextToSpeechEngine();
      final player = _makePlayer(engine); // speakFollowUps=false by default
      final plan = _makePlan('hello', followUps: ['one', 'two']);

      unawaited(player.play(plan));
      fake.flushMicrotasks();

      expect(engine.calls, ['stop', 'speak:hello']);
      player.dispose();
    });
  });

  // ── Test 2 ────────────────────────────────────────────────────────────────
  test('2. speaks primaryText then followUps in order when enabled', () {
    fakeAsync((fake) {
      final engine = FakeTextToSpeechEngine();
      final player = _makePlayer(engine, speakFollowUps: true);
      final plan = _makePlan('hello', followUps: ['one', 'two']);

      unawaited(player.play(plan));
      fake.flushMicrotasks();

      expect(engine.calls, ['stop', 'speak:hello', 'speak:one', 'speak:two']);
      player.dispose();
    });
  });

  // ── Test 3 ────────────────────────────────────────────────────────────────
  test('3. new plan preempts in-flight plan; only new plan is spoken', () {
    fakeAsync((fake) {
      final engine = FakeTextToSpeechEngine();
      final player = _makePlayer(engine, speakFollowUps: true);
      final planA = _makePlan('plan A', followUps: ['a1']);
      final planB = _makePlan('plan B', followUps: ['b1']);

      // Start both plays without awaiting — planB increments token before
      // planA's continuation runs, so planA is cancelled at the token check.
      unawaited(player.play(planA));
      unawaited(player.play(planB));
      fake.flushMicrotasks();

      // planA was preempted — its text must not appear.
      final speakCalls = engine.calls.where((c) => c.startsWith('speak:')).toList();
      expect(speakCalls, isNot(contains('speak:plan A')));
      expect(speakCalls, isNot(contains('speak:a1')));

      // planB completes in full.
      expect(speakCalls, containsAll(['speak:plan B', 'speak:b1']));

      // At least one stop() was issued (planB's initial stop + planA's stop).
      expect(engine.calls.where((c) => c == 'stop').length,
          greaterThanOrEqualTo(1));
      player.dispose();
    });
  });

  // ── Test 4 ────────────────────────────────────────────────────────────────
  test('4. stop() cancels follow-ups; no further speech after in-flight completes', () {
    fakeAsync((fake) {
      const speakTime = Duration(milliseconds: 50);
      final engine = FakeTextToSpeechEngine(speakDelay: speakTime);
      final player = _makePlayer(engine, speakFollowUps: true);
      final plan = _makePlan('hello', followUps: ['one', 'two']);

      unawaited(player.play(plan));
      fake.flushMicrotasks(); // _engine.stop() (sync) completes; play awaits speak('hello') timer

      // Let primary text complete.
      fake.elapse(speakTime);
      // play() is now awaiting speak('one') timer (not yet fired).

      // Cancel before 'one' timer fires.
      unawaited(player.stop()); // token incremented to 2
      fake.flushMicrotasks(); // stop()'s engine.stop() records 'stop'

      // Advance past speak('one') timer so that its Future.delayed resolves;
      // speak() records the call, then play() checks the token and aborts.
      fake.elapse(speakTime);

      expect(engine.calls, contains('speak:hello')); // primary was spoken
      expect(engine.calls, isNot(contains('speak:two'))); // follow-up 'two' cancelled

      player.dispose();
      fake.flushMicrotasks();
    });
  });

  // ── Test 5 ────────────────────────────────────────────────────────────────
  test('5. isSpokenOutputEnabled=false results in zero speak calls', () {
    fakeAsync((fake) {
      final engine = FakeTextToSpeechEngine();
      final player = _makePlayer(engine, isSpokenOutputEnabled: false, speakFollowUps: true);
      final plan = _makePlan('hello', followUps: ['one', 'two']);

      unawaited(player.play(plan));
      fake.flushMicrotasks();

      expect(engine.calls.where((c) => c.startsWith('speak:')), isEmpty);
      player.dispose();
    });
  });

  // ── Test 6 ────────────────────────────────────────────────────────────────
  test('6. empty followUps list produces no follow-up speak calls', () {
    fakeAsync((fake) {
      final engine = FakeTextToSpeechEngine();
      final player = _makePlayer(engine, speakFollowUps: true);
      final plan = _makePlan('hello'); // no followUps

      unawaited(player.play(plan));
      fake.flushMicrotasks();

      expect(engine.calls, ['stop', 'speak:hello']);
      player.dispose();
    });
  });
}

# Phase 12B — Audio Runtime Proposal: Approved Names

## STATUS: APPROVED (2026-02-27)

## Scope

App-layer audio session + wake/listen control. No frozen modules modified (M1–M10,
Orchestrator). No STT/TTS/real platform mic I/O in this phase. Injectable gateway
interfaces only; real platform adapters deferred to Phase 12C+.

## Decisions From Review

| Q | Decision |
|---|---|
| Q1 — VoiceRuntimeEvent type | `sealed class` hierarchy (Dart 3, exhaustive switch) |
| Q2 — VoiceRuntimeState type | `sealed class` with attached data per state |
| Q3 — Controller output API | `Stream<VoiceRuntimeEvent> events` + `ValueNotifier<VoiceRuntimeState> state` |
| Q4 — AudioFrameStream | `typedef AudioFrameStream = Stream<Uint8List>` |
| Q5 — Platform audio | Injectable gateway interfaces only; no real packages in 12B |
| Q6 — WakeWordDetector | Stream-based: `Stream<WakeEvent> get wakeEvents`; `WakeEvent` is a named type |
| Q7 — PTT surface | `beginListening(trigger:)` / `endListening(reason:)` only; toggle is UI concern |
| Q8 — Output port | `onAudioCaptured` callback; no `onTextCandidate` |
| Q9 — Listen timeout | Constructor-injected `Duration listenTimeout` with a default |
| Q10 — Route changes | Injectable `AudioRouteObserver` interface |
| Q11 — Fake WakeWordDetector | `FakeWakeWordDetector` in `lib/voice/runtime/testing/` |
| Q12 — UI wiring | New `VoiceControlBar` widget in `lib/ui/voice/voice_control_bar.dart` |
| Q13 — Controller methods | `setMode`, `beginListening`, `endListening`, `dispose` |
| Q14 — Event subtype names | See table below |
| Q15 — Test count | 12 required contract tests |
| Extra — VoiceListenTrigger | New enum `VoiceListenTrigger` approved for Q13 explainability |

---

## New Public Names

### Enums

| Name | Kind | File | Purpose |
|------|------|------|---------|
| `VoiceStopReason` | `enum` (closed) | `voice_stop_reason.dart` | Closed set of reasons for leaving `ListeningState` |
| `VoiceListenMode` | `enum` | `voice_listen_mode.dart` | User-selected interaction mode |
| `VoiceListenTrigger` | `enum` | `voice_listen_trigger.dart` | Who/what triggered `beginListening` |

`VoiceStopReason` values (closed — no `unknown` or `other`):
`userReleasedPushToTalk`, `userCancelled`, `wakeTimeout`, `permissionDenied`,
`focusLost`, `engineError`, `modeDisabled`, `routeChanged`

`VoiceListenMode` values: `pushToTalkSearch`, `handsFreeAssistant`

`VoiceListenTrigger` values: `pushToTalk`, `wakeWord`

---

### State sealed class

| Name | Kind | File | Attached data |
|------|------|------|---------------|
| `VoiceRuntimeState` | `sealed class` | `voice_runtime_state.dart` | — (base) |
| `IdleState` | `final class` | `voice_runtime_state.dart` | none |
| `ArmingState` | `final class` | `voice_runtime_state.dart` | `mode`, `trigger` |
| `ListeningState` | `final class` | `voice_runtime_state.dart` | `mode`, `trigger` |
| `ProcessingState` | `final class` | `voice_runtime_state.dart` | `mode` |
| `ErrorState` | `final class` | `voice_runtime_state.dart` | `reason`, `message` |

---

### Event sealed class

| Name | Kind | File | Fields |
|------|------|------|--------|
| `VoiceRuntimeEvent` | `sealed class` | `voice_runtime_event.dart` | — (base) |
| `WakeDetected` | `final class` | `voice_runtime_event.dart` | `wakeEvent: WakeEvent` |
| `ListeningBegan` | `final class` | `voice_runtime_event.dart` | `mode`, `trigger` |
| `ListeningEnded` | `final class` | `voice_runtime_event.dart` | `reason: VoiceStopReason` |
| `StopRequested` | `final class` | `voice_runtime_event.dart` | `reason: VoiceStopReason` |
| `ErrorRaised` | `final class` | `voice_runtime_event.dart` | `reason`, `message` |
| `RouteChanged` | `final class` | `voice_runtime_event.dart` | none |
| `PermissionDenied` | `final class` | `voice_runtime_event.dart` | none |
| `AudioFocusDenied` | `final class` | `voice_runtime_event.dart` | none |

---

### Audio type

| Name | Kind | File | Purpose |
|------|------|------|---------|
| `AudioFrameStream` | `typedef` | `audio_frame_stream.dart` | `= Stream<Uint8List>`; placeholder for mic frame delivery |

---

### WakeWordDetector interface + data class

| Name | Kind | File | Purpose |
|------|------|------|---------|
| `WakeWordDetector` | `abstract interface class` | `wake_word_detector.dart` | Plug point for Sherpa (Phase 12C); exposes `Stream<WakeEvent> wakeEvents` + `dispose()` |
| `WakeEvent` | `class` | `wake_word_detector.dart` | Wake detection data: `phrase`, optional `confidence` |

---

### Gateway interfaces (injectable — no platform I/O in 12B)

| Name | Kind | File | Purpose |
|------|------|------|---------|
| `MicPermissionGateway` | `abstract interface class` | `mic_permission_gateway.dart` | `requestPermission()` / `hasPermission()` |
| `AudioFocusGateway` | `abstract interface class` | `audio_focus_gateway.dart` | `requestFocus()` / `abandonFocus()` |
| `AudioRouteObserver` | `abstract interface class` | `audio_route_observer.dart` | `Stream<void> routeChanges` + `dispose()` |

---

### Controller

| Name | Kind | File | Purpose |
|------|------|------|---------|
| `VoiceRuntimeController` | `class` | `voice_runtime_controller.dart` | State machine owner; manages mic lifecycle |

**Public API on `VoiceRuntimeController`:**

| Member | Signature | Notes |
|--------|-----------|-------|
| `state` | `ValueNotifier<VoiceRuntimeState>` | UI rebuilds via `ValueListenableBuilder` |
| `events` | `Stream<VoiceRuntimeEvent>` | Broadcast stream; tests assert ordering |
| `mode` | `VoiceListenMode get mode` | Current mode getter |
| `modeNotifier` | `ValueNotifier<VoiceListenMode>` | Notifies UI when mode changes |
| `onAudioCaptured` | `void Function(AudioFrameStream)? onAudioCaptured` | Placeholder; called on `endListening` (empty stream in 12B) |
| `setMode` | `void setMode(VoiceListenMode mode)` | Stops listening (modeDisabled) if currently listening |
| `beginListening` | `Future<void> beginListening({required VoiceListenTrigger trigger})` | idle → arming → listening (or error) |
| `endListening` | `Future<void> endListening({required VoiceStopReason reason})` | listening → processing → idle; no-op if not listening |
| `dispose` | `void dispose()` | Cancels subscriptions; closes stream |

**Constructor:**
```
VoiceRuntimeController({
  required MicPermissionGateway permissionGateway,
  required AudioFocusGateway focusGateway,
  required AudioRouteObserver routeObserver,
  WakeWordDetector? wakeWordDetector,
  Duration listenTimeout = const Duration(seconds: 6),
})
```

---

### Testing helpers (lib/voice/runtime/testing/)

| Name | Kind | File | Purpose |
|------|------|------|---------|
| `FakeWakeWordDetector` | `class` | `testing/fake_wake_word_detector.dart` | Configurable fake; `simulateWake(WakeEvent)` method |
| `FakeMicPermissionGateway` | `class` | `testing/fake_mic_permission_gateway.dart` | Configurable allow/deny |
| `FakeAudioFocusGateway` | `class` | `testing/fake_audio_focus_gateway.dart` | Configurable allow/deny |
| `FakeAudioRouteObserver` | `class` | `testing/fake_audio_route_observer.dart` | `simulateRouteChange()` method |

---

### UI widget

| Name | Kind | File | Purpose |
|------|------|------|---------|
| `VoiceControlBar` | `StatefulWidget` | `lib/ui/voice/voice_control_bar.dart` | Mode toggle + PTT button; observes `VoiceRuntimeController` |

---

## File Structure

```
lib/voice/runtime/
  voice_stop_reason.dart
  voice_listen_mode.dart
  voice_listen_trigger.dart
  voice_runtime_state.dart
  voice_runtime_event.dart
  audio_frame_stream.dart
  wake_word_detector.dart
  mic_permission_gateway.dart
  audio_focus_gateway.dart
  audio_route_observer.dart
  voice_runtime_controller.dart
  testing/
    fake_wake_word_detector.dart
    fake_mic_permission_gateway.dart
    fake_audio_focus_gateway.dart
    fake_audio_route_observer.dart
lib/ui/voice/
  voice_control_bar.dart
test/voice/runtime/
  voice_runtime_controller_test.dart
```

---

## 12 Required Contract Tests

| # | Test case |
|---|---|
| 1 | Initial state is `IdleState` |
| 2 | `setMode` changes mode without side effects when idle |
| 3 | `beginListening` transitions idle → arming → listening (granted permission + focus) |
| 4 | `endListening` produces `ListeningEnded` with correct `VoiceStopReason` |
| 5 | `handsFreeAssistant`: wake event triggers `beginListening` |
| 6 | `pushToTalkSearch`: wake event is ignored |
| 7 | Timeout stop reason is `wakeTimeout` (handsFree mode) |
| 8 | `routeChanged` while listening stops with `routeChanged` |
| 9 | `permissionDenied` → `ErrorState(reason: permissionDenied)` |
| 10 | `focusDenied` → `AudioFocusDenied` event emitted, state becomes `ErrorState` |
| 11 | Determinism: same event sequence → same final state |
| 12 | `endListening` in `IdleState` is a no-op (no state change, no events) |

---

## Invariants

- `VoiceStopReason` is closed: no `unknown` or `other` values.
- `stop reason` is always set when leaving `ListeningState`.
- `WakeDetected` events in `pushToTalkSearch` mode are silently ignored (no state change).
- `beginListening` is a no-op if state is not `IdleState`.
- `endListening` is a no-op if state is not `ListeningState`.
- `ProcessingState` is transient in 12B: controller immediately returns to `IdleState`
  (no STT pipeline yet).
- No M1–M10 imports; no Orchestrator imports.

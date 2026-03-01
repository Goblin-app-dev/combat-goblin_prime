# Phase 12C — Platform Audio + Wake Word + Offline STT Bridge
## Approved Names Proposal

**Date:** 2026-02-28
**Status:** APPROVED
**Phase:** 12C — Real Audio Capture + Wake Word + STT Bridge

---

## Context

Phase 12B delivered `VoiceRuntimeController` (frozen, 15 tests passing) with injectable gateway
interfaces and fakes only — no real platform I/O. Phase 12C wires real platform audio capture,
Sherpa ONNX wake-word detection, and an offline STT bridge that produces `TextCandidate` and
feeds `VoiceSearchFacade`.

Phase 12C performs a **narrow unfreeze** of `VoiceRuntimeController` to add:
- Two new optional constructor parameters (`captureGateway`, `sttEngine`)
- One new optional callback (`onTextCandidate`)
- Real `_stop()` behavior (frame buffering → STT → candidate event)
- Capture-limit timer (both modes)
- Perf logging (`[VOICE PERF]` prefix)

All other controller behavior from 12B is preserved. Controller is re-frozen at end of phase.

---

## New Public Names

### Data Models

| Name | Kind | File | Description |
|---|---|---|---|
| `TextCandidate` | `final class` | `lib/voice/models/text_candidate.dart` | STT output carrying text, confidence, sessionId, mode, trigger |

### Runtime Interfaces

| Name | Kind | File | Description |
|---|---|---|---|
| `AudioCaptureGateway` | `abstract interface class` | `lib/voice/runtime/audio_capture_gateway.dart` | Mic stream boundary (start/stop/audioFrames/isActive) |
| `SpeechToTextEngine` | `abstract interface class` | `lib/voice/runtime/speech_to_text_engine.dart` | STT boundary: `transcribe(Uint8List, {contextHints})` → `TextCandidate` |

### Runtime Events (additions to existing sealed class)

| Name | Kind | File | Description |
|---|---|---|---|
| `TextCandidateProducedEvent` | `final class extends VoiceRuntimeEvent` | `lib/voice/runtime/voice_runtime_event.dart` | Emitted once per session when STT produces a candidate |

### VoiceStopReason additions (to existing closed enum)

| Value | When |
|---|---|
| `sttFailed` | STT engine threw during transcription |
| `captureLimitReached` | Hard capture limit (`maxCaptureDuration`) exceeded |
| `wakeEngineUnavailable` | `PlatformWakeWordDetector` failed init; hands-free requested |

### Test Fakes (in `lib/voice/runtime/testing/`)

| Name | Kind | File | Description |
|---|---|---|---|
| `FakeAudioCaptureGateway` | `final class` | `lib/voice/runtime/testing/fake_audio_capture_gateway.dart` | Configurable fake; `pushFrame()` injects frames; counts calls |
| `FakeSpeechToTextEngine` | `final class` | `lib/voice/runtime/testing/fake_speech_to_text_engine.dart` | Returns fixed `TextCandidate`; counts `transcribe()` calls |

### Platform Adapters (in `lib/voice/adapters/`)

| Name | Kind | File | Description |
|---|---|---|---|
| `PlatformMicPermissionGateway` | `final class` | `lib/voice/adapters/platform_mic_permission_gateway.dart` | `permission_handler`-backed mic permission |
| `PlatformAudioFocusGateway` | `final class` | `lib/voice/adapters/platform_audio_focus_gateway.dart` | `audio_session`-backed focus acquire/release |
| `PlatformAudioRouteObserver` | `final class` | `lib/voice/adapters/platform_audio_route_observer.dart` | `audio_session` device-change stream |
| `PlatformAudioCaptureGateway` | `final class` | `lib/voice/adapters/platform_audio_capture_gateway.dart` | `record`-backed PCM16/16kHz/mono capture stream |
| `PlatformWakeWordDetector` | `final class` | `lib/voice/adapters/platform_wake_word_detector.dart` | `sherpa_onnx` KWS; bundled model assets; async factory |
| `OfflineSpeechToTextEngine` | `final class` | `lib/voice/adapters/offline_speech_to_text_engine.dart` | `sherpa_onnx` offline ASR; bundled model assets |
| `OnlineSpeechToTextEngine` | `final class` | `lib/voice/adapters/online_speech_to_text_engine.dart` | Stub: throws `UnsupportedError`; ready for 12D |
| `VoicePlatformFactory` | `final class` | `lib/voice/adapters/voice_platform_factory.dart` | Synchronous factory: real adapters on Android/iOS, fakes elsewhere |

### Settings

| Name | Kind | File | Description |
|---|---|---|---|
| `VoiceSettings` | `final class` | `lib/voice/settings/voice_settings.dart` | Immutable persisted voice prefs: lastMode, onlineSttEnabled, wakeWordEnabled, maxCaptureDurationSeconds |
| `VoiceSettingsService` | `final class` | `lib/voice/settings/voice_settings_service.dart` | Save/load `voice_settings.json` (atomic write, same pattern as SessionPersistenceService) |

---

## Controller: Narrow Unfreeze Summary

**Allowed additions to `VoiceRuntimeController` in 12C:**

```dart
// New optional constructor parameters:
AudioCaptureGateway? captureGateway
SpeechToTextEngine? sttEngine
Duration maxCaptureDuration   // default: 15 seconds

// New optional callback (mirrors onAudioCaptured):
void Function(TextCandidate)? onTextCandidate

// New mutable field (set by UI layer):
List<String> contextHints   // passed to transcribe()

// New private fields:
List<Uint8List> _sessionFrames    // accumulates frames during ListeningState
StreamSubscription? _frameSub     // subscription to captureGateway.audioFrames
Timer? _captureLimitTimer         // fires captureLimitReached; both modes
int _listenBeganMs                // perf: timestamp when listening started
int _wakeDetectedMs               // perf: timestamp when wake event fired
```

**Updated `_stop()` behavior (Rule A preserved):**
1. Stop capture gateway; collect `_sessionFrames` into `Uint8List buffer`
2. `_setState(ProcessingState)` → `_emit(ListeningEnded)` → `onAudioCaptured(buffer)`
3. `await _focusGateway.abandonFocus()`
4. If `_sttEngine != null && buffer.isNotEmpty`: `await sttEngine.transcribe(buffer)`
   - On success: `_setState(IdleState)` → `_emit(TextCandidateProducedEvent)` → `onTextCandidate(candidate)`
   - On error: `_setState(ErrorState(sttFailed))` → `_emit(ErrorRaised)`
5. If no engine: `_setState(IdleState)` (existing 12B behavior)

**Updated `setMode()` behavior:**
- If switching to `handsFreeAssistant` with `_wakeWordDetector == null`:
  momentarily `_setState(ErrorState(wakeEngineUnavailable))` → `_emit(ErrorRaised)` → `_setState(IdleState)`
  PTT remains functional.

---

## Audio Format (Canonical — Locked)

- Encoding: PCM 16-bit signed little-endian
- Sample rate: 16 000 Hz
- Channels: 1 (mono)
- Frame type: `Uint8List` chunks
- Conversion: resampling and channel-mixing happen inside adapters, never in the controller

---

## Wake Word: Sherpa ONNX KWS

- Model family: `sherpa-onnx-kws-zipformer-gigaspeech-3.3M` (English, BPE tokens)
- Keywords file format: BPE token sequences from model vocabulary
- "hey goblin" tokenization: derived by developer using model's `bpe.model` / sentencepiece, committed to `assets/voice/kws/keywords.txt`
- Model files bundled as Flutter assets in `assets/voice/kws/`
- Graceful degradation: if init fails → log `[VOICE] wake engine unavailable` → never emit `WakeEvent` → `wakeEngineUnavailable` error in hands-free mode

## ASR: Sherpa ONNX Offline

- Model files bundled as Flutter assets in `assets/voice/asr/`
- Input: buffered PCM16/16kHz/mono from completed session
- Output: `TextCandidate.text` string + confidence
- Graceful degradation: if init fails → `transcribe()` throws → controller catches → `ErrorState(sttFailed)`

---

## Platform Targets

| Platform | Audio Capture | Wake Word | STT |
|---|---|---|---|
| Android | Full | Full (sherpa_onnx FFI) | Full (sherpa_onnx) |
| iOS | Full | Full (sherpa_onnx CocoaPods) | Full (sherpa_onnx) |
| Web/Desktop | Disabled (no-op) | Disabled | Disabled |

---

## Asset Structure

```
assets/voice/kws/
  README.md            — instructions for placing model files
  keywords.txt         — BPE token sequences for "hey goblin" (committed)
  encoder.onnx         — KWS encoder (developer must obtain)
  decoder.onnx         — KWS decoder (developer must obtain)
  joiner.onnx          — KWS joiner (developer must obtain)
  tokens.txt           — vocabulary tokens (developer must obtain)

assets/voice/asr/
  README.md            — instructions for placing model files
  encoder.onnx         — ASR encoder (developer must obtain)
  decoder.onnx         — ASR decoder (developer must obtain)
  joiner.onnx          — ASR joiner (developer must obtain)
  tokens.txt           — vocabulary tokens (developer must obtain)
```

---

## Contract Tests (12C, tests 16–28)

| # | Case |
|---|---|
| 16 | Session guard: late frame after stop → ignored, no state change |
| 17 | PTT cycle: begin → listening → end → `onAudioCaptured` once → STT called once → `TextCandidateProducedEvent` once |
| 18 | Hands-free: wake → arming → listening → stop → `IdleState`; wake detector still subscribed |
| 19 | Capture limit: exceeds `maxCaptureDuration` → stop with `captureLimitReached` |
| 20 | Permission denied → `ErrorState(permissionDenied)` + `PermissionDenied` event; mic never starts |
| 21 | Focus denied → `ErrorState(focusLost)` + `AudioFocusDenied` event |
| 22 | Route change during listening → `routeChanged` reason + `ListeningEnded` |
| 23 | STT called exactly once per session with correct buffered PCM bytes |
| 24 | `TextCandidateProducedEvent` emitted once, after state = `IdleState` (Rule A) |
| 25 | Mode drift: `state.mode == modeNotifier.value` across all transitions |
| 26 | Deterministic transcript: fixed fake STT → same `TextCandidate` every run |
| 27 | Callback ordering: `onTextCandidate` fires after `TextCandidateProducedEvent` (same turn) |
| 28 | Wake engine unavailable: `ErrorRaised(wakeEngineUnavailable)` then `IdleState`; PTT still works |
| 29 | Perf smoke: `[VOICE PERF]` lines printed in order for a complete PTT session |

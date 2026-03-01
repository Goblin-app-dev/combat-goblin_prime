import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_capture_gateway.dart';
import 'audio_focus_gateway.dart';
import 'audio_route_observer.dart';
import 'mic_permission_gateway.dart';
import 'speech_to_text_engine.dart';
import 'voice_listen_mode.dart';
import 'voice_listen_trigger.dart';
import 'voice_runtime_event.dart';
import 'voice_runtime_state.dart';
import 'voice_stop_reason.dart';
import 'wake_word_detector.dart';
import '../models/text_candidate.dart';

/// State machine controller for the voice mic lifecycle.
///
/// Owns:
/// - Listen state ([state]) as a [ValueNotifier] for UI observation.
/// - Event stream ([events]) for deterministic test assertions (Skill 10).
/// - Mode ([modeNotifier]) as a [ValueNotifier] so UI can rebuild on change.
///
/// All platform I/O is injectable via gateway interfaces (Skill 06).
///
/// **Session guard:** every listen attempt increments [_currentSessionId].
/// Async gateway callbacks and timer callbacks capture this ID at registration
/// time and compare it before acting, preventing zombie transitions from
/// stale async callbacks.
///
/// **Stop funnel:** all stop paths route through [_stop] to guarantee
/// consistent cleanup and deterministic event/state ordering.
///
/// **Ordering invariant (Rule A):** state is updated FIRST, then the
/// corresponding event is emitted. Listeners can safely read [state.value]
/// inside an event callback and observe the post-transition state.
///
/// **Other invariants:**
/// - [beginListening] is a no-op if state is not [IdleState].
/// - [endListening] is a no-op if state is not [ListeningState].
/// - [VoiceStopReason] is always set when leaving [ListeningState].
/// - [ProcessingState] is transient: becomes [IdleState] after STT completes
///   (or immediately if no STT engine is wired).
class VoiceRuntimeController {
  final MicPermissionGateway _permissionGateway;
  final AudioFocusGateway _focusGateway;
  final AudioRouteObserver _routeObserver;
  final WakeWordDetector? _wakeWordDetector;
  final AudioCaptureGateway? _captureGateway;
  final SpeechToTextEngine? _sttEngine;

  /// Maximum listen window for [VoiceListenMode.handsFreeAssistant].
  ///
  /// Constructor-injected so tests can pass a short duration (Skill 10).
  final Duration listenTimeout;

  /// Hard cap on mic capture duration for both modes.
  ///
  /// When exceeded, the session stops with [VoiceStopReason.captureLimitReached].
  final Duration maxCaptureDuration;

  /// Monotonically increasing session counter.
  ///
  /// Incremented by [_nextSessionId] at the start of each listen attempt.
  int _currentSessionId = 0;

  final ValueNotifier<VoiceListenMode> _modeNotifier =
      ValueNotifier(VoiceListenMode.pushToTalkSearch);

  late final ValueNotifier<VoiceRuntimeState> _stateNotifier;

  /// Synchronous broadcast so Rule A is testable: listeners observe the
  /// post-transition [state.value] synchronously when an event fires.
  final StreamController<VoiceRuntimeEvent> _eventController =
      StreamController<VoiceRuntimeEvent>.broadcast(sync: true);

  StreamSubscription<void>? _routeSub;
  StreamSubscription<WakeEvent>? _wakeSub;
  Timer? _listenTimer;

  // 12C additions ──────────────────────────────────────────────────────────────

  /// Accumulated PCM16 frames for the current listen session.
  final List<Uint8List> _sessionFrames = [];

  /// Subscription to [AudioCaptureGateway.audioFrames].
  StreamSubscription<Uint8List>? _frameSub;

  /// Hard capture-duration timer; fires [VoiceStopReason.captureLimitReached].
  Timer? _captureLimitTimer;

  /// Timestamp (ms) when listening began; used for [VOICE PERF] log.
  int _listenBeganMs = 0;

  /// Timestamp (ms) when wake event was detected; used for [VOICE PERF] log.
  int _wakeDetectedMs = 0;

  // ────────────────────────────────────────────────────────────────────────────

  /// Session-complete callback for the full session audio.
  ///
  /// Called once per session at the stop boundary with the full buffered PCM.
  /// In Phase 12C this carries real audio when [_captureGateway] is wired.
  void Function(Uint8List audio)? onAudioCaptured;

  /// Called once per session when the STT engine produces a [TextCandidate].
  ///
  /// Fires after [TextCandidateProducedEvent] is emitted (same synchronous
  /// turn) and after state has transitioned to [IdleState] (Rule A).
  void Function(TextCandidate candidate)? onTextCandidate;

  /// Domain terms passed to [SpeechToTextEngine.transcribe] as vocabulary bias.
  ///
  /// Set by the UI layer before or during a session. Thread-safe as long as
  /// writes happen on the platform thread (standard Flutter constraint).
  List<String> contextHints = const [];

  VoiceRuntimeController({
    required MicPermissionGateway permissionGateway,
    required AudioFocusGateway focusGateway,
    required AudioRouteObserver routeObserver,
    WakeWordDetector? wakeWordDetector,
    AudioCaptureGateway? captureGateway,
    SpeechToTextEngine? sttEngine,
    this.listenTimeout = const Duration(seconds: 6),
    this.maxCaptureDuration = const Duration(seconds: 15),
  })  : _permissionGateway = permissionGateway,
        _focusGateway = focusGateway,
        _routeObserver = routeObserver,
        _wakeWordDetector = wakeWordDetector,
        _captureGateway = captureGateway,
        _sttEngine = sttEngine {
    _stateNotifier = ValueNotifier(
      IdleState(mode: VoiceListenMode.pushToTalkSearch, sessionId: 0),
    );
    _routeSub = _routeObserver.routeChanges.listen((_) => _handleRouteChange());
    if (wakeWordDetector != null) {
      _wakeSub = wakeWordDetector.wakeEvents.listen(_handleWakeEvent);
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Current listen state. UI rebuilds via [ValueListenableBuilder].
  ValueNotifier<VoiceRuntimeState> get state => _stateNotifier;

  /// Broadcast stream of controller events. Tests assert event ordering.
  Stream<VoiceRuntimeEvent> get events => _eventController.stream;

  /// Current interaction mode.
  VoiceListenMode get mode => _modeNotifier.value;

  /// Notifier for interaction mode. UI rebuilds on mode change.
  ValueNotifier<VoiceListenMode> get modeNotifier => _modeNotifier;

  /// Change the interaction mode.
  ///
  /// If currently [ListeningState], routes through [_stop] with
  /// [VoiceStopReason.modeDisabled].
  ///
  /// If switching to [VoiceListenMode.handsFreeAssistant] without a
  /// [WakeWordDetector], emits [ErrorRaised(wakeEngineUnavailable)] then
  /// immediately returns to [IdleState]. PTT remains functional.
  void setMode(VoiceListenMode newMode) {
    if (_modeNotifier.value == newMode) return;
    _modeNotifier.value = newMode;
    if (_stateNotifier.value is ListeningState) {
      unawaited(_stop(VoiceStopReason.modeDisabled));
    } else if (newMode == VoiceListenMode.handsFreeAssistant &&
        _wakeWordDetector == null) {
      _handleNoWakeEngine();
    }
  }

  /// Attempt to open a listen session.
  ///
  /// No-op if state is not [IdleState]. Delegates to [_beginListeningInternal].
  Future<void> beginListening({required VoiceListenTrigger trigger}) async {
    if (_stateNotifier.value is! IdleState) return;
    await _beginListeningInternal(
        trigger: trigger, sessionId: _nextSessionId());
  }

  /// Close the active listen session.
  ///
  /// No-op if state is not [ListeningState]. All stop paths funnel through
  /// [_stop] for consistent cleanup and ordering.
  Future<void> endListening({required VoiceStopReason reason}) async {
    await _stop(reason);
  }

  /// Release all resources. Must be called when the controller is no longer needed.
  void dispose() {
    _listenTimer?.cancel();
    _listenTimer = null;
    _captureLimitTimer?.cancel();
    _captureLimitTimer = null;
    _frameSub?.cancel();
    _frameSub = null;
    _routeSub?.cancel();
    _wakeSub?.cancel();
    _routeObserver.dispose();
    _wakeWordDetector?.dispose();
    _captureGateway?.dispose();
    _stateNotifier.dispose();
    _modeNotifier.dispose();
    _eventController.close();
  }

  // ---------------------------------------------------------------------------
  // Private: session management
  // ---------------------------------------------------------------------------

  int _nextSessionId() => ++_currentSessionId;

  /// Core listen startup. Separated from [beginListening] so that
  /// [_handleWakeEvent] can pre-allocate the session ID and share it between
  /// the [WakeDetected] event and the resulting listen session for correlation.
  Future<void> _beginListeningInternal({
    required VoiceListenTrigger trigger,
    required int sessionId,
  }) async {
    _setState(ArmingState(
      mode: _modeNotifier.value,
      trigger: trigger,
      sessionId: sessionId,
    ));

    final permitted = await _permissionGateway.requestPermission();
    if (_currentSessionId != sessionId) return; // Session guard

    if (!permitted) {
      // Rule A: update state FIRST, then emit events.
      _setState(ErrorState(
        mode: _modeNotifier.value,
        trigger: trigger,
        sessionId: sessionId,
        reason: VoiceStopReason.permissionDenied,
        message: 'Microphone permission denied',
      ));
      _emit(PermissionDenied(sessionId: sessionId));
      _emit(ErrorRaised(
        reason: VoiceStopReason.permissionDenied,
        message: 'Microphone permission denied',
        sessionId: sessionId,
      ));
      return;
    }

    final focused = await _focusGateway.requestFocus();
    if (_currentSessionId != sessionId) return; // Session guard

    if (!focused) {
      // Rule A: update state FIRST, then emit events.
      _setState(ErrorState(
        mode: _modeNotifier.value,
        trigger: trigger,
        sessionId: sessionId,
        reason: VoiceStopReason.focusLost,
        message: 'Audio focus denied',
      ));
      _emit(AudioFocusDenied(sessionId: sessionId));
      _emit(ErrorRaised(
        reason: VoiceStopReason.focusLost,
        message: 'Audio focus denied',
        sessionId: sessionId,
      ));
      return;
    }

    // Rule A: state → ListeningState, THEN emit ListeningBegan.
    _sessionFrames.clear();
    _listenBeganMs = DateTime.now().millisecondsSinceEpoch;
    _setState(ListeningState(
      mode: _modeNotifier.value,
      trigger: trigger,
      sessionId: sessionId,
    ));
    _emit(ListeningBegan(
      mode: _modeNotifier.value,
      trigger: trigger,
      sessionId: sessionId,
    ));

    // Start mic capture and accumulate frames.
    final capture = _captureGateway;
    if (capture != null) {
      final started = await capture.start();
      if (_currentSessionId != sessionId) return; // Session guard
      if (started) {
        _frameSub = capture.audioFrames.listen((frame) {
          if (_currentSessionId == sessionId) {
            _sessionFrames.add(frame);
          }
          // Frames from stale sessions are silently dropped.
        });
      }
    }

    // Hands-free: enforce listen timeout (wakeTimeout).
    if (_modeNotifier.value == VoiceListenMode.handsFreeAssistant) {
      final capturedId = sessionId;
      _listenTimer = Timer(listenTimeout, () {
        if (_currentSessionId == capturedId) {
          unawaited(_stop(VoiceStopReason.wakeTimeout));
        }
      });
    }

    // Both modes: hard capture-duration cap.
    final capturedId = sessionId;
    _captureLimitTimer = Timer(maxCaptureDuration, () {
      if (_currentSessionId == capturedId) {
        unawaited(_stop(VoiceStopReason.captureLimitReached));
      }
    });
  }

  /// Single stop funnel: all paths that end a listen session route here.
  ///
  /// No-op if state is not [ListeningState].
  ///
  /// Transition sequence (Rule A: state before event):
  /// 1. Cancel timers; stop capture gateway; collect frames.
  /// 2. state → [ProcessingState] → emit [ListeningEnded] → [onAudioCaptured]
  /// 3. await focus release
  /// 4a. If STT engine wired and buffer non-empty: transcribe
  ///     - Success: state → [IdleState] → emit [TextCandidateProducedEvent]
  ///                → [onTextCandidate]
  ///     - Failure: state → [ErrorState(sttFailed)] → emit [ErrorRaised]
  /// 4b. No engine: state → [IdleState] (session-guarded)
  Future<void> _stop(VoiceStopReason reason) async {
    if (_stateNotifier.value is! ListeningState) return;

    final sessionId = _currentSessionId;
    final priorState = _stateNotifier.value as ListeningState;
    final trigger = priorState.trigger!; // Always non-null for ListeningState.

    _listenTimer?.cancel();
    _listenTimer = null;
    _captureLimitTimer?.cancel();
    _captureLimitTimer = null;

    // Stop capture and collect accumulated frames.
    _frameSub?.cancel();
    _frameSub = null;
    await _captureGateway?.stop();

    // Concatenate frames into a single buffer.
    final buffer = _buildBuffer();
    _sessionFrames.clear();

    final stopMs = DateTime.now().millisecondsSinceEpoch;
    final listenDuration = stopMs - _listenBeganMs;

    // Rule A: state update before event emit.
    _setState(ProcessingState(
      mode: priorState.mode,
      trigger: trigger,
      sessionId: sessionId,
    ));
    _emit(ListeningEnded(reason: reason, sessionId: sessionId));

    onAudioCaptured?.call(buffer);

    await _focusGateway.abandonFocus();

    // Only proceed with STT if the session is still current.
    if (_stateNotifier.value is! ProcessingState ||
        _currentSessionId != sessionId) {
      return;
    }

    final sttEngine = _sttEngine;
    if (sttEngine != null && buffer.isNotEmpty) {
      try {
        final rawCandidate = await sttEngine.transcribe(
          buffer,
          contextHints: contextHints,
        );
        if (_stateNotifier.value is! ProcessingState ||
            _currentSessionId != sessionId) {
          return;
        }
        // Fill in actual session context (engine returns placeholder values).
        final candidate = TextCandidate(
          text: rawCandidate.text,
          confidence: rawCandidate.confidence,
          isFinal: rawCandidate.isFinal,
          sessionId: sessionId,
          mode: priorState.mode,
          trigger: trigger,
        );
        final candidateMs = DateTime.now().millisecondsSinceEpoch;

        // Perf logging — state-machine timings.
        if (_wakeDetectedMs > 0) {
          debugPrint(
            '[VOICE PERF] wake→listen: ${_listenBeganMs - _wakeDetectedMs}ms',
          );
          _wakeDetectedMs = 0;
        }
        debugPrint('[VOICE PERF] listen duration: ${listenDuration}ms');
        debugPrint(
          '[VOICE PERF] stop→candidate: ${candidateMs - stopMs}ms',
        );

        // Rule A: IdleState before TextCandidateProducedEvent.
        _setState(IdleState(
          mode: _modeNotifier.value,
          trigger: trigger,
          sessionId: sessionId,
        ));
        _emit(TextCandidateProducedEvent(
          candidate: candidate,
          sessionId: sessionId,
        ));
        onTextCandidate?.call(candidate);
      } catch (e) {
        if (_stateNotifier.value is! ProcessingState ||
            _currentSessionId != sessionId) {
          return;
        }
        _setState(ErrorState(
          mode: _modeNotifier.value,
          trigger: trigger,
          sessionId: sessionId,
          reason: VoiceStopReason.sttFailed,
          message: 'STT failed: $e',
        ));
        _emit(ErrorRaised(
          reason: VoiceStopReason.sttFailed,
          message: 'STT failed: $e',
          sessionId: sessionId,
        ));
      }
    } else {
      // No engine or empty buffer: return to idle (existing 12B behavior).
      if (_stateNotifier.value is ProcessingState &&
          _currentSessionId == sessionId) {
        _setState(IdleState(
          mode: _modeNotifier.value,
          trigger: trigger,
          sessionId: sessionId,
        ));
      }
    }
  }

  /// Concatenates all accumulated [_sessionFrames] into a single [Uint8List].
  Uint8List _buildBuffer() {
    if (_sessionFrames.isEmpty) return Uint8List(0);
    final totalBytes =
        _sessionFrames.fold<int>(0, (sum, f) => sum + f.length);
    final buffer = Uint8List(totalBytes);
    var offset = 0;
    for (final frame in _sessionFrames) {
      buffer.setRange(offset, offset + frame.length, frame);
      offset += frame.length;
    }
    return buffer;
  }

  // ---------------------------------------------------------------------------
  // Private: event handlers
  // ---------------------------------------------------------------------------

  void _handleWakeEvent(WakeEvent event) {
    if (_modeNotifier.value == VoiceListenMode.pushToTalkSearch) return;
    if (_stateNotifier.value is! IdleState) return;

    _wakeDetectedMs = DateTime.now().millisecondsSinceEpoch;

    // Pre-allocate session ID so WakeDetected and the listen session share it.
    final sessionId = _nextSessionId();
    _emit(WakeDetected(wakeEvent: event, sessionId: sessionId));
    unawaited(_beginListeningInternal(
      trigger: VoiceListenTrigger.wakeWord,
      sessionId: sessionId,
    ));
  }

  void _handleRouteChange() {
    // Informational event: emitted before the resulting stop (if any).
    _emit(RouteChanged(sessionId: _currentSessionId));
    if (_stateNotifier.value is ListeningState) {
      unawaited(_stop(VoiceStopReason.routeChanged));
    }
  }

  /// Emits a momentary [ErrorState(wakeEngineUnavailable)] then [IdleState].
  ///
  /// Called when switching to [VoiceListenMode.handsFreeAssistant] without a
  /// [WakeWordDetector]. PTT mode remains functional.
  void _handleNoWakeEngine() {
    final sessionId = _currentSessionId;
    _setState(ErrorState(
      mode: _modeNotifier.value,
      trigger: null,
      sessionId: sessionId,
      reason: VoiceStopReason.wakeEngineUnavailable,
      message: 'Wake-word engine unavailable; falling back to PTT',
    ));
    _emit(ErrorRaised(
      reason: VoiceStopReason.wakeEngineUnavailable,
      message: 'Wake-word engine unavailable; falling back to PTT',
      sessionId: sessionId,
    ));
    _setState(IdleState(
      mode: _modeNotifier.value,
      trigger: null,
      sessionId: sessionId,
    ));
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _setState(VoiceRuntimeState next) => _stateNotifier.value = next;

  void _emit(VoiceRuntimeEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }
}

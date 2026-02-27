import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'audio_focus_gateway.dart';
import 'audio_route_observer.dart';
import 'mic_permission_gateway.dart';
import 'voice_listen_mode.dart';
import 'voice_listen_trigger.dart';
import 'voice_runtime_event.dart';
import 'voice_runtime_state.dart';
import 'voice_stop_reason.dart';
import 'wake_word_detector.dart';

/// State machine controller for the voice mic lifecycle.
///
/// Owns:
/// - Listen state ([state]) as a [ValueNotifier] for UI observation.
/// - Event stream ([events]) for deterministic test assertions (Skill 10).
/// - Mode ([modeNotifier]) as a [ValueNotifier] so UI can rebuild on change.
///
/// All platform I/O is injectable via gateway interfaces (Skill 06).
/// No direct mic/permission/focus platform calls in Phase 12B.
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
/// - [ProcessingState] is transient in 12B: immediately becomes [IdleState].
class VoiceRuntimeController {
  final MicPermissionGateway _permissionGateway;
  final AudioFocusGateway _focusGateway;
  final AudioRouteObserver _routeObserver;
  final WakeWordDetector? _wakeWordDetector;

  /// Maximum listen window for [VoiceListenMode.handsFreeAssistant].
  ///
  /// Constructor-injected so tests can pass a short duration (Skill 10).
  final Duration listenTimeout;

  /// Monotonically increasing session counter.
  ///
  /// Incremented by [_nextSessionId] at the start of each listen attempt.
  /// Async gateway callbacks and timer callbacks guard themselves with this.
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

  /// Session-complete callback for future STT engines (Phase 12D+).
  ///
  /// Called once per session, at the stop boundary, with the full buffered
  /// session audio. In Phase 12B receives an empty [Uint8List] (no real
  /// capture yet). Real mic accumulation is wired in Phase 12C+.
  ///
  /// Streaming transcription is a separate port; do not overload this
  /// callback with incremental frame chunks.
  void Function(Uint8List audio)? onAudioCaptured;

  VoiceRuntimeController({
    required MicPermissionGateway permissionGateway,
    required AudioFocusGateway focusGateway,
    required AudioRouteObserver routeObserver,
    WakeWordDetector? wakeWordDetector,
    this.listenTimeout = const Duration(seconds: 6),
  })  : _permissionGateway = permissionGateway,
        _focusGateway = focusGateway,
        _routeObserver = routeObserver,
        _wakeWordDetector = wakeWordDetector {
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
  void setMode(VoiceListenMode newMode) {
    if (_modeNotifier.value == newMode) return;
    _modeNotifier.value = newMode;
    if (_stateNotifier.value is ListeningState) {
      unawaited(_stop(VoiceStopReason.modeDisabled));
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
    _routeSub?.cancel();
    _wakeSub?.cancel();
    _routeObserver.dispose();
    _wakeWordDetector?.dispose();
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

    if (_modeNotifier.value == VoiceListenMode.handsFreeAssistant) {
      final capturedId = sessionId;
      _listenTimer = Timer(listenTimeout, () {
        if (_currentSessionId == capturedId) {
          unawaited(_stop(VoiceStopReason.wakeTimeout));
        }
      });
    }
  }

  /// Single stop funnel: all paths that end a listen session route here.
  ///
  /// No-op if state is not [ListeningState].
  ///
  /// Transition sequence (Rule A: state before event):
  /// 1. state → [ProcessingState]
  /// 2. emit [ListeningEnded]
  /// 3. invoke [onAudioCaptured] with full session audio (empty [Uint8List] in 12B)
  /// 4. await focus release
  /// 5. state → [IdleState] (session-guarded)
  Future<void> _stop(VoiceStopReason reason) async {
    if (_stateNotifier.value is! ListeningState) return;

    final sessionId = _currentSessionId;
    final priorState = _stateNotifier.value as ListeningState;
    final trigger = priorState.trigger!; // Always non-null for ListeningState.

    _listenTimer?.cancel();
    _listenTimer = null;

    // Rule A: state update before event emit.
    _setState(ProcessingState(
      mode: priorState.mode,
      trigger: trigger,
      sessionId: sessionId,
    ));
    _emit(ListeningEnded(reason: reason, sessionId: sessionId));

    // Phase 12B: empty buffer — real accumulation wired in 12C.
    onAudioCaptured?.call(Uint8List(0));

    await _focusGateway.abandonFocus();

    // Session guard: only idle if no new session started during the await.
    if (_stateNotifier.value is ProcessingState &&
        _currentSessionId == sessionId) {
      _setState(IdleState(
        mode: _modeNotifier.value,
        trigger: trigger,
        sessionId: sessionId,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Private: event handlers
  // ---------------------------------------------------------------------------

  void _handleWakeEvent(WakeEvent event) {
    if (_modeNotifier.value == VoiceListenMode.pushToTalkSearch) return;
    if (_stateNotifier.value is! IdleState) return;

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

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _setState(VoiceRuntimeState next) => _stateNotifier.value = next;

  void _emit(VoiceRuntimeEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }
}

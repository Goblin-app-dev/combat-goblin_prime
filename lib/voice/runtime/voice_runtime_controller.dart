import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_focus_gateway.dart';
import 'audio_frame_stream.dart';
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
/// Invariants:
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

  final ValueNotifier<VoiceRuntimeState> _stateNotifier =
      ValueNotifier(const IdleState());

  final ValueNotifier<VoiceListenMode> _modeNotifier =
      ValueNotifier(VoiceListenMode.pushToTalkSearch);

  final StreamController<VoiceRuntimeEvent> _eventController =
      StreamController<VoiceRuntimeEvent>.broadcast();

  StreamSubscription<void>? _routeSub;
  StreamSubscription<WakeEvent>? _wakeSub;
  Timer? _listenTimer;

  /// Placeholder callback for future STT engines (Phase 12D+).
  ///
  /// Called with an empty [AudioFrameStream] when [endListening] completes in
  /// Phase 12B. Real mic frame delivery is wired in Phase 12C+.
  void Function(AudioFrameStream stream)? onAudioCaptured;

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
    _routeSub = _routeObserver.routeChanges.listen((_) => _handleRouteChange());
    if (wakeWordDetector != null) {
      _wakeSub =
          wakeWordDetector.wakeEvents.listen((e) => _handleWakeEvent(e));
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
  /// If currently [ListeningState], stops with [VoiceStopReason.modeDisabled].
  void setMode(VoiceListenMode newMode) {
    if (_modeNotifier.value == newMode) return;
    _modeNotifier.value = newMode;
    if (_stateNotifier.value is ListeningState) {
      endListening(reason: VoiceStopReason.modeDisabled);
    }
  }

  /// Attempt to open a listen session.
  ///
  /// No-op if state is not [IdleState].
  ///
  /// Transition sequence:
  /// 1. idle → [ArmingState]
  /// 2a. Permission denied → emit [PermissionDenied], emit [ErrorRaised],
  ///     → [ErrorState]
  /// 2b. Focus denied → emit [AudioFocusDenied], emit [ErrorRaised],
  ///     → [ErrorState]
  /// 3. arming → [ListeningState], emit [ListeningBegan]
  /// 4. Start timeout timer if [VoiceListenMode.handsFreeAssistant]
  Future<void> beginListening({required VoiceListenTrigger trigger}) async {
    if (_stateNotifier.value is! IdleState) return;

    final currentMode = _modeNotifier.value;
    _setState(ArmingState(mode: currentMode, trigger: trigger));

    final permitted = await _permissionGateway.requestPermission();
    if (permitted == false) {
      _emit(const PermissionDenied());
      _emit(ErrorRaised(
        reason: VoiceStopReason.permissionDenied,
        message: 'Microphone permission denied',
      ));
      _setState(ErrorState(
        reason: VoiceStopReason.permissionDenied,
        message: 'Microphone permission denied',
      ));
      return;
    }

    final focused = await _focusGateway.requestFocus();
    if (focused == false) {
      _emit(const AudioFocusDenied());
      _emit(ErrorRaised(
        reason: VoiceStopReason.focusLost,
        message: 'Audio focus denied',
      ));
      _setState(ErrorState(
        reason: VoiceStopReason.focusLost,
        message: 'Audio focus denied',
      ));
      return;
    }

    _setState(ListeningState(mode: currentMode, trigger: trigger));
    _emit(ListeningBegan(mode: currentMode, trigger: trigger));

    if (currentMode == VoiceListenMode.handsFreeAssistant) {
      _listenTimer = Timer(listenTimeout, () {
        endListening(reason: VoiceStopReason.wakeTimeout);
      });
    }
  }

  /// Close the active listen session.
  ///
  /// No-op if state is not [ListeningState].
  ///
  /// Transition sequence:
  /// 1. listening → [ProcessingState], emit [ListeningEnded]
  /// 2. Invoke [onAudioCaptured] placeholder (empty stream in 12B)
  /// 3. processing → [IdleState] (no STT pipeline in 12B)
  Future<void> endListening({required VoiceStopReason reason}) async {
    if (_stateNotifier.value is! ListeningState) return;

    _listenTimer?.cancel();
    _listenTimer = null;

    final mode = (_stateNotifier.value as ListeningState).mode;

    _setState(ProcessingState(mode: mode));
    _emit(ListeningEnded(reason: reason));

    // Placeholder: inform future STT engine of the captured audio.
    onAudioCaptured?.call(const Stream.empty());

    await _focusGateway.abandonFocus();

    // Phase 12B: no STT pipeline — immediately return to idle.
    if (_stateNotifier.value is ProcessingState) {
      _setState(const IdleState());
    }
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
  // Private helpers
  // ---------------------------------------------------------------------------

  void _setState(VoiceRuntimeState next) {
    _stateNotifier.value = next;
  }

  void _emit(VoiceRuntimeEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void _handleWakeEvent(WakeEvent event) {
    // In pushToTalkSearch mode, wake events are silently ignored.
    if (_modeNotifier.value == VoiceListenMode.pushToTalkSearch) return;
    // Only react when idle.
    if (_stateNotifier.value is! IdleState) return;

    _emit(WakeDetected(wakeEvent: event));
    // Fire-and-forget; state transitions are guarded inside beginListening.
    beginListening(trigger: VoiceListenTrigger.wakeWord);
  }

  void _handleRouteChange() {
    _emit(const RouteChanged());
    if (_stateNotifier.value is ListeningState) {
      endListening(reason: VoiceStopReason.routeChanged);
    }
  }
}

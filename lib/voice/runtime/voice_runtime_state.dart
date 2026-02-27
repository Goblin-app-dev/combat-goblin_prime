import 'voice_listen_mode.dart';
import 'voice_listen_trigger.dart';
import 'voice_stop_reason.dart';

/// Sealed state hierarchy for [VoiceRuntimeController].
///
/// Deterministic: same sequence of inputs → same state transitions (Skill 10).
/// Every subtype carries [mode], [trigger], and [sessionId]:
/// - [mode]: currently configured listen mode (always non-null).
/// - [trigger]: originator of the current/last session (null only for the
///   initial [IdleState] before any session has started).
/// - [sessionId]: monotonically increasing counter — controller callbacks
///   compare their captured ID against the current value to reject stale
///   deliveries (session guard).
sealed class VoiceRuntimeState {
  /// The currently configured interaction mode.
  final VoiceListenMode mode;

  /// What triggered the current or last completed listen session.
  ///
  /// Null only for the initial [IdleState] before any session has started.
  /// Non-null for all in-session and post-session state subtypes.
  final VoiceListenTrigger? trigger;

  /// Monotonically increasing session counter (0 = before first session).
  ///
  /// Incremented once per [VoiceRuntimeController.beginListening] call.
  /// Timer callbacks and async gateway responses capture this value at
  /// registration time and compare it against the controller's current
  /// session counter before acting (session guard).
  final int sessionId;

  const VoiceRuntimeState({
    required this.mode,
    this.trigger,
    required this.sessionId,
  });
}

/// No audio session active. Controller is ready to arm.
///
/// [trigger] is null on initial construction; carries the last-used trigger
/// after any session completes (for log correlation).
final class IdleState extends VoiceRuntimeState {
  const IdleState({
    required super.mode,
    super.trigger,
    required super.sessionId,
  });
}

/// Preparing audio session: requesting mic permission and audio focus.
///
/// Transient: transitions to [ListeningState] on success or [ErrorState] on
/// permission/focus denial. [trigger] is always non-null.
final class ArmingState extends VoiceRuntimeState {
  const ArmingState({
    required super.mode,
    required VoiceListenTrigger trigger,
    required super.sessionId,
  }) : super(trigger: trigger);
}

/// Mic is open and collecting audio.
///
/// The listen-window timer runs while in this state when
/// [VoiceListenMode.handsFreeAssistant] is active. [trigger] is always
/// non-null.
final class ListeningState extends VoiceRuntimeState {
  const ListeningState({
    required super.mode,
    required VoiceListenTrigger trigger,
    required super.sessionId,
  }) : super(trigger: trigger);
}

/// Mic closed; downstream pipeline processing (stub in Phase 12B).
///
/// Transient in 12B: immediately transitions to [IdleState] since no STT
/// pipeline is wired yet. [trigger] is always non-null.
final class ProcessingState extends VoiceRuntimeState {
  const ProcessingState({
    required super.mode,
    required VoiceListenTrigger trigger,
    required super.sessionId,
  }) : super(trigger: trigger);
}

/// A recoverable error occurred during session setup.
///
/// Controller can be retried via [VoiceRuntimeController.beginListening] once
/// the error condition resolves. [trigger] carries the trigger from the failed
/// session attempt.
final class ErrorState extends VoiceRuntimeState {
  /// Structured reason code — always present (Skill 11).
  final VoiceStopReason reason;

  /// Human-readable detail for debugging.
  final String message;

  const ErrorState({
    required super.mode,
    super.trigger,
    required super.sessionId,
    required this.reason,
    required this.message,
  });
}

import 'voice_listen_mode.dart';
import 'voice_listen_trigger.dart';
import 'voice_stop_reason.dart';

/// Sealed state hierarchy for [VoiceRuntimeController].
///
/// Deterministic: same sequence of inputs → same state transitions (Skill 10).
/// UI observes via [VoiceRuntimeController.state] (`ValueNotifier`).
sealed class VoiceRuntimeState {
  const VoiceRuntimeState();
}

/// No audio session active. Controller is ready to arm.
final class IdleState extends VoiceRuntimeState {
  const IdleState();
}

/// Preparing audio session: requesting mic permission and audio focus.
///
/// Transient: transitions to [ListeningState] on success or [ErrorState] on denial.
final class ArmingState extends VoiceRuntimeState {
  /// The mode active when arming began.
  final VoiceListenMode mode;

  /// What triggered this listen attempt.
  final VoiceListenTrigger trigger;

  const ArmingState({required this.mode, required this.trigger});
}

/// Mic is open and collecting audio frames.
///
/// The listen window timer (if in [VoiceListenMode.handsFreeAssistant]) is
/// running while in this state.
final class ListeningState extends VoiceRuntimeState {
  /// The mode active when listening began.
  final VoiceListenMode mode;

  /// What triggered this listen session.
  final VoiceListenTrigger trigger;

  const ListeningState({required this.mode, required this.trigger});
}

/// Mic closed; downstream pipeline processing (stub in Phase 12B).
///
/// Transient in 12B: immediately transitions to [IdleState] since no STT
/// pipeline is wired yet.
final class ProcessingState extends VoiceRuntimeState {
  /// The mode that was active during the listen session.
  final VoiceListenMode mode;

  const ProcessingState({required this.mode});
}

/// A recoverable error occurred. Controller can return to [IdleState] after
/// user grants permission or the error condition resolves.
final class ErrorState extends VoiceRuntimeState {
  /// Structured reason code — always present (Skill 11).
  final VoiceStopReason reason;

  /// Human-readable detail for debugging.
  final String message;

  const ErrorState({required this.reason, required this.message});
}

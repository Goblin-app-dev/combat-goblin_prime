import '../models/text_candidate.dart';
import 'voice_listen_mode.dart';
import 'voice_listen_trigger.dart';
import 'voice_stop_reason.dart';
import 'wake_word_detector.dart';

/// Sealed event hierarchy emitted by [VoiceRuntimeController.events].
///
/// Tests assert event ordering deterministically (Skill 10).
/// Every stop/deny/error carries a reason code (Skill 11).
/// Every event carries [sessionId] for log correlation and session guard
/// verification — matches the [VoiceRuntimeState.sessionId] of the state
/// active when the event was emitted.
sealed class VoiceRuntimeEvent {
  /// Session counter value at the moment this event was emitted.
  ///
  /// Correlates events with state snapshots and allows consumers to detect
  /// events from stale sessions (e.g. delayed network callbacks).
  final int sessionId;

  const VoiceRuntimeEvent({required this.sessionId});
}

/// A [WakeWordDetector] detected the configured wake phrase.
///
/// In [VoiceListenMode.handsFreeAssistant] this is followed by idle →
/// listening transitions. In [VoiceListenMode.pushToTalkSearch] wake events
/// are silently discarded (no state change, no event emitted).
///
/// [sessionId] matches the session that will be started by this wake event —
/// the WakeDetected event and the subsequent [ListeningBegan] share the same
/// [sessionId].
final class WakeDetected extends VoiceRuntimeEvent {
  final WakeEvent wakeEvent;
  const WakeDetected({required this.wakeEvent, required super.sessionId});
}

/// Mic session opened successfully; controller entered [ListeningState].
///
/// Ordering invariant (Rule A): state is already [ListeningState] when this
/// event is received by any listener.
final class ListeningBegan extends VoiceRuntimeEvent {
  final VoiceListenMode mode;
  final VoiceListenTrigger trigger;
  const ListeningBegan({
    required this.mode,
    required this.trigger,
    required super.sessionId,
  });
}

/// Mic session closed; always carries the stop reason (Skill 11).
///
/// Ordering invariant (Rule A): state is already [ProcessingState] when this
/// event is received by any listener.
final class ListeningEnded extends VoiceRuntimeEvent {
  final VoiceStopReason reason;
  const ListeningEnded({required this.reason, required super.sessionId});
}

/// A stop was explicitly requested (e.g. user tapped cancel in UI).
///
/// Emitted before [ListeningEnded] when stop is user-initiated.
final class StopRequested extends VoiceRuntimeEvent {
  final VoiceStopReason reason;
  const StopRequested({required this.reason, required super.sessionId});
}

/// A recoverable error put the controller into [ErrorState].
///
/// Ordering invariant (Rule A): state is already [ErrorState] when this
/// event is received by any listener.
final class ErrorRaised extends VoiceRuntimeEvent {
  final VoiceStopReason reason;
  final String message;
  const ErrorRaised({
    required this.reason,
    required this.message,
    required super.sessionId,
  });
}

/// Audio route changed (Bluetooth connect/disconnect, headphone plug, etc.).
///
/// Informational event: emitted when the route change is detected, before
/// the resulting [ListeningEnded] (if any).
final class RouteChanged extends VoiceRuntimeEvent {
  const RouteChanged({required super.sessionId});
}

/// Microphone permission was denied; controller entered [ErrorState].
///
/// Informational event: emitted just before [ErrorRaised] and [ErrorState].
final class PermissionDenied extends VoiceRuntimeEvent {
  const PermissionDenied({required super.sessionId});
}

/// Audio focus was denied; controller entered [ErrorState].
///
/// Informational event: emitted just before [ErrorRaised] and [ErrorState].
final class AudioFocusDenied extends VoiceRuntimeEvent {
  const AudioFocusDenied({required super.sessionId});
}

/// STT engine produced a [TextCandidate] from the session audio.
///
/// Ordering invariant (Rule A): state is already [IdleState] when this event
/// is received by any listener. [onTextCandidate] callback fires after this
/// event is emitted, within the same synchronous turn.
final class TextCandidateProducedEvent extends VoiceRuntimeEvent {
  final TextCandidate candidate;
  const TextCandidateProducedEvent({
    required this.candidate,
    required super.sessionId,
  });
}

import 'voice_listen_mode.dart';
import 'voice_listen_trigger.dart';
import 'voice_stop_reason.dart';
import 'wake_word_detector.dart';

/// Sealed event hierarchy emitted by [VoiceRuntimeController.events].
///
/// Tests assert event ordering deterministically (Skill 10).
/// Every stop/deny/error carries a reason code (Skill 11).
sealed class VoiceRuntimeEvent {
  const VoiceRuntimeEvent();
}

/// A [WakeWordDetector] detected the configured wake phrase.
///
/// In [VoiceListenMode.handsFreeAssistant] this transitions idle → listening.
/// In [VoiceListenMode.pushToTalkSearch] this event is emitted but ignored
/// (no state change).
final class WakeDetected extends VoiceRuntimeEvent {
  final WakeEvent wakeEvent;
  const WakeDetected({required this.wakeEvent});
}

/// Mic session opened successfully; controller entered [ListeningState].
final class ListeningBegan extends VoiceRuntimeEvent {
  final VoiceListenMode mode;
  final VoiceListenTrigger trigger;
  const ListeningBegan({required this.mode, required this.trigger});
}

/// Mic session closed; always carries the stop reason (Skill 11).
final class ListeningEnded extends VoiceRuntimeEvent {
  final VoiceStopReason reason;
  const ListeningEnded({required this.reason});
}

/// A stop was explicitly requested (e.g. user tapped cancel in UI).
///
/// Emitted before [ListeningEnded] when stop is user-initiated.
final class StopRequested extends VoiceRuntimeEvent {
  final VoiceStopReason reason;
  const StopRequested({required this.reason});
}

/// A recoverable error put the controller into [ErrorState].
final class ErrorRaised extends VoiceRuntimeEvent {
  final VoiceStopReason reason;
  final String message;
  const ErrorRaised({required this.reason, required this.message});
}

/// Audio route changed (Bluetooth connect/disconnect, headphone plug, etc.).
///
/// If the controller is [ListeningState], this triggers [ListeningEnded] with
/// [VoiceStopReason.routeChanged].
final class RouteChanged extends VoiceRuntimeEvent {
  const RouteChanged();
}

/// Microphone permission was denied; controller entered [ErrorState].
final class PermissionDenied extends VoiceRuntimeEvent {
  const PermissionDenied();
}

/// Audio focus was denied; controller entered [ErrorState].
final class AudioFocusDenied extends VoiceRuntimeEvent {
  const AudioFocusDenied();
}

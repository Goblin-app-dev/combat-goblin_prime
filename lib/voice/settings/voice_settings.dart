import '../runtime/voice_listen_mode.dart';

/// Immutable persisted voice preferences.
///
/// Stored as `voice_settings.json` by [VoiceSettingsService].
final class VoiceSettings {
  /// The last-used interaction mode. Restored on next launch.
  final VoiceListenMode lastMode;

  /// Whether to use online STT when available. Default: false.
  ///
  /// Phase 12D wires the real engine. In Phase 12C, setting this to true
  /// causes [OnlineSpeechToTextEngine] to throw [UnsupportedError], which
  /// the controller catches and converts to [ErrorState(sttFailed)].
  final bool onlineSttEnabled;

  /// Whether to attempt wake-word engine initialization. Default: true.
  ///
  /// When false, [VoicePlatformFactory] skips [PlatformWakeWordDetector]
  /// initialization entirely, running PTT-only mode.
  final bool wakeWordEnabled;

  /// Hard cap on mic capture duration, in seconds. Default: 15.
  ///
  /// Both PTT and hands-free sessions fire
  /// [VoiceStopReason.captureLimitReached] when this duration is exceeded.
  final int maxCaptureDurationSeconds;

  /// Whether to speak [SpokenResponsePlan] output via TTS. Default: true.
  ///
  /// Set to false to silence all TTS output while keeping voice search active.
  final bool isSpokenOutputEnabled;

  /// Whether to speak the follow-up suggestions after [SpokenResponsePlan.primaryText].
  /// Default: false (primary text only).
  final bool speakFollowUps;

  const VoiceSettings({
    this.lastMode = VoiceListenMode.pushToTalkSearch,
    this.onlineSttEnabled = false,
    this.wakeWordEnabled = true,
    this.maxCaptureDurationSeconds = 15,
    this.isSpokenOutputEnabled = true,
    this.speakFollowUps = false,
  });

  static const VoiceSettings defaults = VoiceSettings();

  Map<String, dynamic> toJson() => {
        'lastMode': lastMode.name,
        'onlineSttEnabled': onlineSttEnabled,
        'wakeWordEnabled': wakeWordEnabled,
        'maxCaptureDurationSeconds': maxCaptureDurationSeconds,
        'isSpokenOutputEnabled': isSpokenOutputEnabled,
        'speakFollowUps': speakFollowUps,
      };

  factory VoiceSettings.fromJson(Map<String, dynamic> json) {
    return VoiceSettings(
      lastMode: VoiceListenMode.values.firstWhere(
        (m) => m.name == json['lastMode'],
        orElse: () => VoiceListenMode.pushToTalkSearch,
      ),
      onlineSttEnabled: json['onlineSttEnabled'] as bool? ?? false,
      wakeWordEnabled: json['wakeWordEnabled'] as bool? ?? true,
      maxCaptureDurationSeconds:
          json['maxCaptureDurationSeconds'] as int? ?? 15,
      isSpokenOutputEnabled: json['isSpokenOutputEnabled'] as bool? ?? true,
      speakFollowUps: json['speakFollowUps'] as bool? ?? false,
    );
  }

  VoiceSettings copyWith({
    VoiceListenMode? lastMode,
    bool? onlineSttEnabled,
    bool? wakeWordEnabled,
    int? maxCaptureDurationSeconds,
    bool? isSpokenOutputEnabled,
    bool? speakFollowUps,
  }) {
    return VoiceSettings(
      lastMode: lastMode ?? this.lastMode,
      onlineSttEnabled: onlineSttEnabled ?? this.onlineSttEnabled,
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      maxCaptureDurationSeconds:
          maxCaptureDurationSeconds ?? this.maxCaptureDurationSeconds,
      isSpokenOutputEnabled:
          isSpokenOutputEnabled ?? this.isSpokenOutputEnabled,
      speakFollowUps: speakFollowUps ?? this.speakFollowUps,
    );
  }
}

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

  const VoiceSettings({
    this.lastMode = VoiceListenMode.pushToTalkSearch,
    this.onlineSttEnabled = false,
    this.wakeWordEnabled = true,
    this.maxCaptureDurationSeconds = 15,
  });

  static const VoiceSettings defaults = VoiceSettings();

  Map<String, dynamic> toJson() => {
        'lastMode': lastMode.name,
        'onlineSttEnabled': onlineSttEnabled,
        'wakeWordEnabled': wakeWordEnabled,
        'maxCaptureDurationSeconds': maxCaptureDurationSeconds,
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
    );
  }

  VoiceSettings copyWith({
    VoiceListenMode? lastMode,
    bool? onlineSttEnabled,
    bool? wakeWordEnabled,
    int? maxCaptureDurationSeconds,
  }) {
    return VoiceSettings(
      lastMode: lastMode ?? this.lastMode,
      onlineSttEnabled: onlineSttEnabled ?? this.onlineSttEnabled,
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      maxCaptureDurationSeconds:
          maxCaptureDurationSeconds ?? this.maxCaptureDurationSeconds,
    );
  }
}

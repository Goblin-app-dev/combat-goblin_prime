import 'dart:io';

import 'package:flutter/foundation.dart';

import '../runtime/audio_capture_gateway.dart';
import '../runtime/audio_focus_gateway.dart';
import '../runtime/audio_route_observer.dart';
import '../runtime/mic_permission_gateway.dart';
import '../runtime/speech_to_text_engine.dart';
import '../runtime/testing/fake_audio_capture_gateway.dart';
import '../runtime/testing/fake_audio_focus_gateway.dart';
import '../runtime/testing/fake_audio_route_observer.dart';
import '../runtime/testing/fake_mic_permission_gateway.dart';
import '../runtime/testing/fake_speech_to_text_engine.dart';
import '../runtime/wake_word_detector.dart';
import '../settings/voice_settings.dart';
import 'offline_speech_to_text_engine.dart';
import 'online_speech_to_text_engine.dart';
import 'platform_audio_capture_gateway.dart';
import 'platform_audio_focus_gateway.dart';
import 'platform_audio_route_observer.dart';
import 'platform_mic_permission_gateway.dart';
import 'platform_wake_word_detector.dart';

/// Synchronous factory that creates platform adapters based on the runtime
/// target and [VoiceSettings].
///
/// Returns real adapters on Android/iOS; no-op fakes on Web/Desktop.
/// Wake-word detector requires async initialization — use
/// [createWakeWordDetector] separately and inject into the controller.
final class VoicePlatformFactory {
  final VoiceSettings settings;

  VoicePlatformFactory({required this.settings});

  bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  MicPermissionGateway createPermissionGateway() {
    if (_isMobile) return PlatformMicPermissionGateway();
    return FakeMicPermissionGateway(allow: false);
  }

  AudioFocusGateway createFocusGateway() {
    if (_isMobile) return PlatformAudioFocusGateway();
    return FakeAudioFocusGateway(allow: true);
  }

  AudioRouteObserver createRouteObserver() {
    if (_isMobile) return PlatformAudioRouteObserver();
    return FakeAudioRouteObserver();
  }

  AudioCaptureGateway createCaptureGateway() {
    if (_isMobile) return PlatformAudioCaptureGateway();
    return FakeAudioCaptureGateway(allowStart: false);
  }

  SpeechToTextEngine createSttEngine() {
    if (!_isMobile) return FakeSpeechToTextEngine();
    if (settings.onlineSttEnabled) return OnlineSpeechToTextEngine();
    return OfflineSpeechToTextEngine();
  }

  /// Async factory for wake-word detector.
  ///
  /// Returns `null` if:
  /// - Not on Android/iOS, or
  /// - [VoiceSettings.wakeWordEnabled] is false, or
  /// - [PlatformWakeWordDetector] fails to initialize (missing model assets,
  ///   FFI error, etc.) — logs `[VOICE] wake engine unavailable`.
  Future<WakeWordDetector?> createWakeWordDetector({
    required AudioCaptureGateway captureGateway,
  }) async {
    if (!_isMobile || !settings.wakeWordEnabled) return null;
    return PlatformWakeWordDetector.create(captureGateway: captureGateway);
  }
}

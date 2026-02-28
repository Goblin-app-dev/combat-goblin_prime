import 'package:audio_session/audio_session.dart';

import '../runtime/audio_focus_gateway.dart';

/// [AudioFocusGateway] backed by `audio_session`.
///
/// Acquires audio focus for speech recording on [requestFocus] and releases
/// it on [abandonFocus]. Works on Android (AudioFocus API) and iOS
/// (AVAudioSession activation).
final class PlatformAudioFocusGateway implements AudioFocusGateway {
  @override
  Future<bool> requestFocus() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.record,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.measurement,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
      return await session.setActive(true);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> abandonFocus() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {
      // Best-effort; never throw from abandonFocus.
    }
  }
}

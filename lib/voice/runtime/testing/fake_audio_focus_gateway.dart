import 'package:combat_goblin_prime/voice/runtime/audio_focus_gateway.dart';

/// Configurable fake [AudioFocusGateway] for deterministic testing.
class FakeAudioFocusGateway implements AudioFocusGateway {
  /// Whether [requestFocus] returns `true`.
  bool allow;

  FakeAudioFocusGateway({this.allow = true});

  @override
  Future<bool> requestFocus() async => allow;

  @override
  Future<void> abandonFocus() async {}
}

/// Injectable boundary for audio focus acquisition.
///
/// Real platform adapter (Android AudioFocus / iOS AVAudioSession) is
/// deferred to Phase 12C. In Phase 12B only [FakeAudioFocusGateway]
/// is provided.
abstract interface class AudioFocusGateway {
  /// Requests audio focus. Returns `true` if granted.
  Future<bool> requestFocus();

  /// Releases audio focus.
  Future<void> abandonFocus();
}

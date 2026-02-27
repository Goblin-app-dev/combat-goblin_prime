/// Injectable boundary for audio route change notifications.
///
/// Route changes include Bluetooth device connect/disconnect, headphone plug,
/// and similar hardware events. When a route change occurs while the controller
/// is in [ListeningState], the controller stops with [VoiceStopReason.routeChanged].
///
/// Real platform adapter is deferred to Phase 12C. In Phase 12B only
/// [FakeAudioRouteObserver] is provided.
abstract interface class AudioRouteObserver {
  /// Fires when the audio route changes. Payload is ignored (void).
  Stream<void> get routeChanges;

  /// Release resources. Called by [VoiceRuntimeController.dispose].
  void dispose();
}

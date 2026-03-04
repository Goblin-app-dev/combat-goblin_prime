/// Injectable boundary for text-to-speech output.
///
/// Platform adapter ([PlatformTextToSpeechEngine]) is wired in 12E.
/// Lazy initialization is an adapter implementation detail — the interface
/// makes no assumption about when the underlying engine is ready.
abstract interface class TextToSpeechEngine {
  /// Speaks [text] and returns when playback completes (or is interrupted).
  Future<void> speak(String text);

  /// Stops any ongoing speech immediately.
  Future<void> stop();

  /// Releases all resources held by this engine.
  Future<void> dispose();
}

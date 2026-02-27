import 'dart:typed_data';

/// Type alias for a stream of raw audio frame bytes.
///
/// Used as the payload type for [VoiceRuntimeController.onAudioCaptured].
/// In Phase 12B this is a placeholder — the callback is invoked with an
/// empty stream. Real mic frame delivery is wired in Phase 12C+.
typedef AudioFrameStream = Stream<Uint8List>;

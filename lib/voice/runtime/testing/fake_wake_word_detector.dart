import 'dart:async';

import 'package:combat_goblin_prime/voice/runtime/wake_word_detector.dart';

/// Configurable fake [WakeWordDetector] for deterministic testing.
///
/// Call [simulateWake] to push a [WakeEvent] into the stream.
class FakeWakeWordDetector implements WakeWordDetector {
  final StreamController<WakeEvent> _controller =
      StreamController<WakeEvent>.broadcast();

  @override
  Stream<WakeEvent> get wakeEvents => _controller.stream;

  /// Simulate a wake detection. Pushes [event] into [wakeEvents].
  void simulateWake(WakeEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}

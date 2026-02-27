import 'dart:async';

import 'package:combat_goblin_prime/voice/runtime/audio_route_observer.dart';

/// Configurable fake [AudioRouteObserver] for deterministic testing.
///
/// Call [simulateRouteChange] to push a route-change event into the stream.
class FakeAudioRouteObserver implements AudioRouteObserver {
  final StreamController<void> _controller =
      StreamController<void>.broadcast();

  @override
  Stream<void> get routeChanges => _controller.stream;

  /// Simulate a route change event.
  void simulateRouteChange() {
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  @override
  void dispose() {
    _controller.close();
  }
}

import 'dart:async';

import 'package:audio_session/audio_session.dart';

import '../runtime/audio_route_observer.dart';

/// [AudioRouteObserver] backed by `audio_session` device-change events.
///
/// Merges [AudioSession.becomingNoisyEventStream] (wired headphone unplug)
/// with [AudioSession.interruptionEventStream] (system-level audio
/// interruption ends) to cover the most common route-change scenarios.
///
/// Graceful degradation: if `AudioSession` initialization fails, [routeChanges]
/// never emits — the controller simply never stops on route change.
final class PlatformAudioRouteObserver implements AudioRouteObserver {
  final StreamController<void> _controller =
      StreamController<void>.broadcast();

  final List<StreamSubscription<dynamic>> _subs = [];

  PlatformAudioRouteObserver() {
    _init();
  }

  Future<void> _init() async {
    try {
      final session = await AudioSession.instance;
      _subs.add(session.becomingNoisyEventStream.listen((_) => _emit()));
      _subs.add(
        session.interruptionEventStream.listen((event) {
          // Route changed when an interruption ends (e.g. phone call finished).
          if (event.type == AudioInterruptionType.unknown) _emit();
        }),
      );
    } catch (_) {
      // Graceful degradation: no route events.
    }
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(null);
  }

  @override
  Stream<void> get routeChanges => _controller.stream;

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _controller.close();
  }
}

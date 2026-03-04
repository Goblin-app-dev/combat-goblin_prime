import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

import '../runtime/text_to_speech_engine.dart';

/// [TextToSpeechEngine] backed by [FlutterTts].
///
/// Lazy-initialised on the first [speak] call so that boot is not blocked.
/// On iOS, [FlutterTts.setSharedInstance] is called to allow audio routing
/// through AVAudioSession without conflicting with the system session.
///
/// If platform TTS fails to initialise the engine degrades silently: all
/// subsequent [speak] calls return immediately without throwing. One
/// deterministic error line is logged via [print].
final class PlatformTextToSpeechEngine implements TextToSpeechEngine {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _degraded = false;

  Future<void> _ensureInitialized() async {
    if (_initialized || _degraded) return;
    try {
      await _tts.setLanguage('en-US');
      if (Platform.isIOS) {
        // Required on iOS so AVSpeechSynthesizer works alongside other audio.
        await _tts.setSharedInstance(true);
      }
      _initialized = true;
    } catch (e) {
      _degraded = true;
      print('[VOICE] TTS init failed — speech output disabled: $e');
    }
  }

  @override
  Future<void> speak(String text) async {
    await _ensureInitialized();
    if (_degraded) return;
    try {
      await _tts.speak(text);
    } catch (e) {
      print('[VOICE] TTS speak failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Best-effort; never throw from stop().
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Best-effort; never throw from dispose().
    }
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/text_candidate.dart';
import '../runtime/speech_to_text_engine.dart';
import '../runtime/voice_listen_mode.dart';
import '../runtime/voice_listen_trigger.dart';

/// Sherpa ONNX offline ASR implementation of [SpeechToTextEngine].
///
/// Accepts buffered PCM16 / 16 kHz / mono bytes, converts to float32, and
/// runs a full-utterance decode via [sherpa.OfflineRecognizer].
///
/// The recognizer is lazy-initialized on the first [transcribe] call.
/// If bundled model assets are missing, the first call throws, and
/// [VoiceRuntimeController] catches it and emits [ErrorState(sttFailed)].
///
/// [TextCandidate.sessionId], [mode], and [trigger] carry placeholder values;
/// the controller overwrites them with the actual session context.
final class OfflineSpeechToTextEngine implements SpeechToTextEngine {
  sherpa.OfflineRecognizer? _recognizer;
  bool _initAttempted = false;

  @override
  Future<TextCandidate> transcribe(
    Uint8List pcm, {
    required List<String> contextHints,
  }) async {
    final recognizer = await _getRecognizer();

    final sttStartMs = DateTime.now().millisecondsSinceEpoch;
    final samples = _pcm16ToFloat32(pcm);
    final stream = recognizer.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: 16000);
    recognizer.decode(stream);
    final result = recognizer.getResult(stream);
    stream.free();
    final sttEndMs = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[VOICE PERF] stt latency: ${sttEndMs - sttStartMs}ms');

    return TextCandidate(
      text: result.text.trim(),
      confidence: -1.0, // sherpa offline transducer does not expose per-utt confidence
      isFinal: true,
      sessionId: 0, // controller overwrites
      mode: VoiceListenMode.pushToTalkSearch, // controller overwrites
      trigger: VoiceListenTrigger.pushToTalk, // controller overwrites
    );
  }

  Future<sherpa.OfflineRecognizer> _getRecognizer() async {
    if (_recognizer != null) return _recognizer!;
    if (_initAttempted) {
      throw StateError('ASR engine failed to initialize; model assets missing?');
    }
    _initAttempted = true;

    final dir = await getApplicationDocumentsDirectory();
    final asrDir = Directory('${dir.path}/voice/asr');
    await asrDir.create(recursive: true);

    Future<String> extractAsset(String assetPath) async {
      final data = await rootBundle.load(assetPath);
      final name = assetPath.split('/').last;
      final file = File('${asrDir.path}/$name');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file.path;
    }

    final encoder = await extractAsset('assets/voice/asr/encoder.onnx');
    final decoder = await extractAsset('assets/voice/asr/decoder.onnx');
    final joiner = await extractAsset('assets/voice/asr/joiner.onnx');
    final tokens = await extractAsset('assets/voice/asr/tokens.txt');

    final config = sherpa.OfflineRecognizerConfig(
      feat: sherpa.FeatureExtractorConfig(
        sampleRate: 16000,
        featureDim: 80,
      ),
      model: sherpa.OfflineModelConfig(
        transducer: sherpa.OfflineTransducerModelConfig(
          encoder: encoder,
          decoder: decoder,
          joiner: joiner,
        ),
        tokens: tokens,
        numThreads: 2,
        debug: false,
      ),
    );

    _recognizer = sherpa.OfflineRecognizer(config);
    return _recognizer!;
  }

  static Float32List _pcm16ToFloat32(Uint8List pcm) {
    final samples = Float32List(pcm.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      final lo = pcm[2 * i];
      final hi = pcm[2 * i + 1];
      final raw = (hi << 8) | lo;
      final signed = raw > 32767 ? raw - 65536 : raw;
      samples[i] = signed / 32768.0;
    }
    return samples;
  }
}

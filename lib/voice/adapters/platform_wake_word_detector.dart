import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../runtime/audio_capture_gateway.dart';
import '../runtime/wake_word_detector.dart';

/// Sherpa ONNX keyword-spotting [WakeWordDetector].
///
/// Uses the bundled `sherpa-onnx-kws-zipformer-gigaspeech-3.3M` model.
/// Keywords are expressed as BPE tokens derived from the model's
/// `bpe.model` via sentencepiece (see `assets/voice/kws/keywords.txt`).
///
/// Do not construct directly — use [PlatformWakeWordDetector.create].
///
/// Graceful degradation: if model assets are missing or init fails,
/// [create] returns `null` and logs `[VOICE] wake engine unavailable`.
final class PlatformWakeWordDetector implements WakeWordDetector {
  final StreamController<WakeEvent> _wakeController =
      StreamController<WakeEvent>.broadcast();

  final AudioCaptureGateway _captureGateway;
  sherpa.KeywordSpotter? _kws;
  StreamSubscription<Uint8List>? _frameSub;

  PlatformWakeWordDetector._({
    required AudioCaptureGateway captureGateway,
    required sherpa.KeywordSpotter kws,
  })  : _captureGateway = captureGateway,
        _kws = kws {
    _startListening();
  }

  /// Async factory: initializes Sherpa ONNX KWS from bundled assets.
  ///
  /// Returns `null` on any init failure; caller should degrade to PTT-only.
  static Future<PlatformWakeWordDetector?> create({
    required AudioCaptureGateway captureGateway,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final kwsDir = Directory('${dir.path}/voice/kws');
      await kwsDir.create(recursive: true);

      Future<String> extractAsset(String assetPath) async {
        final data = await rootBundle.load(assetPath);
        final name = assetPath.split('/').last;
        final file = File('${kwsDir.path}/$name');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        return file.path;
      }

      final encoder = await extractAsset('assets/voice/kws/encoder.onnx');
      final decoder = await extractAsset('assets/voice/kws/decoder.onnx');
      final joiner = await extractAsset('assets/voice/kws/joiner.onnx');
      final tokens = await extractAsset('assets/voice/kws/tokens.txt');
      final keywords = await extractAsset('assets/voice/kws/keywords.txt');

      final config = sherpa.KeywordSpotterConfig(
        feat: sherpa.FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: encoder,
            decoder: decoder,
            joiner: joiner,
          ),
          tokens: tokens,
          numThreads: 1,
          provider: 'cpu',
          debug: false,
        ),
        keywordsFile: keywords,
        maxActivePaths: 4,
        numTrailingBlanks: 1,
        keywordsScore: 1.0,
        keywordsThreshold: 0.25,
      );

      final kws = sherpa.KeywordSpotter(config);
      return PlatformWakeWordDetector._(
        captureGateway: captureGateway,
        kws: kws,
      );
    } catch (e) {
      debugPrint('[VOICE] wake engine unavailable: $e');
      return null;
    }
  }

  void _startListening() {
    _captureGateway.start();
    _frameSub = _captureGateway.audioFrames.listen(_processFrame);
  }

  void _processFrame(Uint8List pcm) {
    final kws = _kws;
    if (kws == null || _wakeController.isClosed) return;
    try {
      final stream = kws.createStream();
      stream.acceptWaveform(
        samples: _pcm16ToFloat32(pcm),
        sampleRate: 16000,
      );
      kws.decode(stream);
      final result = kws.getResult(stream);
      if (result.keyword.isNotEmpty) {
        _wakeController.add(WakeEvent(phrase: result.keyword.trim()));
      }
      stream.free();
    } catch (_) {
      // Silently drop bad frames; never crash the controller.
    }
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

  @override
  Stream<WakeEvent> get wakeEvents => _wakeController.stream;

  @override
  void dispose() {
    _frameSub?.cancel();
    _frameSub = null;
    _wakeController.close();
    _kws?.free();
    _kws = null;
  }
}

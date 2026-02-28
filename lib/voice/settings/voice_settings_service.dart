import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'voice_settings.dart';

/// Persists [VoiceSettings] to `voice_settings.json` in the app storage root.
///
/// Uses the same atomic-write pattern as `SessionPersistenceService`:
/// write to `.tmp`, then rename to the real file.
final class VoiceSettingsService {
  static const _fileName = 'voice_settings.json';

  final String _storageRoot;

  VoiceSettingsService({required String storageRoot})
      : _storageRoot = storageRoot;

  String get _filePath => p.join(_storageRoot, _fileName);

  /// Loads saved settings, or returns [VoiceSettings.defaults] if missing or corrupt.
  Future<VoiceSettings> load() async {
    try {
      final file = File(_filePath);
      if (!await file.exists()) return VoiceSettings.defaults;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return VoiceSettings.fromJson(json);
    } catch (_) {
      return VoiceSettings.defaults;
    }
  }

  /// Saves [settings] atomically (write temp, rename).
  Future<void> save(VoiceSettings settings) async {
    final file = File(_filePath);
    await file.parent.create(recursive: true);
    final tmp = File('$_filePath.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
    await tmp.rename(_filePath);
  }
}

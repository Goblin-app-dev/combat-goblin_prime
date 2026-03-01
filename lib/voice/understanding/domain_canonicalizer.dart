import '../models/disambiguation_command.dart';
import 'voice_intent_classifier.dart';

/// Normalizes raw STT transcripts and fuzzy-matches them against domain vocabulary.
///
/// **Normalization:** lowercase, strip non-word/non-space characters, collapse
/// whitespace, trim.
///
/// **Fuzzy matching:** compares the normalized transcript against each hint
/// using normalized Levenshtein similarity = `1.0 - distance / max(len_a, len_b)`.
/// Threshold: ≥ 0.75. If a hint matches, its original (pre-normalization) form
/// is returned so display names preserve casing.
///
/// **Tie-break:** first matching hint in iteration order. Callers control the
/// hint ordering for determinism (e.g. lexicographic slot order).
///
/// **Performance cap:** strings longer than [_maxLenForFuzzy] return 0.0
/// similarity and are never matched.
///
/// This class is stateless — a single `const` instance can be shared.
final class DomainCanonicalizer {
  const DomainCanonicalizer();

  static const double _fuzzyThreshold = 0.75;
  static const int _maxLenForFuzzy = 128;

  /// Return the canonical query string for [raw].
  ///
  /// If any [contextHints] entry has similarity ≥ [_fuzzyThreshold] with the
  /// normalized form of [raw], the original hint (preserving casing) is returned.
  /// Otherwise the normalized form of [raw] is returned.
  String canonicalizeQuery(String raw, {required List<String> contextHints}) {
    final normalized = _normalize(raw);
    if (normalized.isEmpty) return '';
    if (contextHints.isEmpty) return normalized;

    double bestScore = 0.0;
    String bestHint = normalized;

    for (final hint in contextHints) {
      final hintNorm = _normalize(hint);
      if (hintNorm.isEmpty) continue;
      final score = _similarity(normalized, hintNorm);
      if (score > bestScore && score >= _fuzzyThreshold) {
        bestScore = score;
        bestHint = hint; // Return original hint casing for display.
      }
    }
    return bestHint;
  }

  /// Parse [raw] as a [DisambiguationCommand] if it matches exactly.
  ///
  /// Delegates to [VoiceIntentClassifier.commandMap]. Returns null if not a command.
  DisambiguationCommand? parseCommand(String raw) {
    return VoiceIntentClassifier.commandMap[raw.trim().toLowerCase()];
  }

  /// Normalize: lowercase, strip non-word/non-space, collapse spaces, trim.
  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Normalized Levenshtein similarity in [0.0, 1.0].
  ///
  /// Returns 0.0 for strings exceeding [_maxLenForFuzzy] to bound O(m×n) cost.
  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a.length > _maxLenForFuzzy || b.length > _maxLenForFuzzy) return 0.0;
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - _levenshtein(a, b) / maxLen;
  }

  /// Standard O(m×n) Levenshtein edit distance.
  static int _levenshtein(String a, String b) {
    final m = a.length;
    final n = b.length;
    // Single-row rolling update to reduce allocations.
    var prev = List<int>.generate(n + 1, (j) => j);
    var curr = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          curr[j] = prev[j - 1];
        } else {
          final sub = prev[j - 1];
          final del = prev[j];
          final ins = curr[j - 1];
          curr[j] = 1 + (sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins));
        }
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }
}

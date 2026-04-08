/// Bounded deterministic canonical name resolver.
///
/// Converts user-friendly search terms to BSData-compatible query strings
/// before they reach the search engine.
///
/// **Deterministic only**: uses a fixed alias table and rule-based
/// normalization. No fuzzy search, no probabilistic matching.
///
/// ## Resolution steps (first match wins)
///
/// 1. Normalize input (lowercase, strip non-alphanumeric, collapse
///    whitespace) — identical to [IndexService.normalize] so results are
///    compatible with canonicalKey values stored in the index.
/// 2. Exact alias lookup in [_aliases].
/// 3. Singular → plural alias: append 's' and look up in [_aliases].
/// 4. Plural → singular alias: strip trailing 's' and look up in [_aliases].
/// 5. General plural stripping: if the input ends in 's' and
///    [_shouldSingularize] returns true, return the stripped form.
///    This ensures that M10's substring matching (which checks
///    `canonicalKey.contains(query)`) finds units whose canonical keys
///    use the singular form (e.g. "intercessor squad" for input
///    "intercessors"). Stripping never loses results because the singular
///    form is always a substring of the plural canonical key.
/// 6. No match — return the normalized form unchanged.
///
/// This class is stateless — a single `const` instance can be shared.
final class CanonicalNameResolver {
  const CanonicalNameResolver();

  /// Known alias mappings.
  ///
  /// **Keys**: normalized user-friendly names (lowercase, non-alphanumeric
  ///   stripped, whitespace collapsed). Must be in normal form — no uppercase,
  ///   no punctuation.
  /// **Values**: BSData-compatible query string passed to the search engine.
  static const Map<String, String> _aliases = <String, String>{
    // ── Faction name aliases ─────────────────────────────────────────────
    // BSData catalog uses "Legiones Daemonica" as the army book name.
    // Common spoken / colloquial variants are mapped here.
    'chaos daemons': 'legiones daemonica',
    'chaos daemon': 'legiones daemonica',
    'daemons of chaos': 'legiones daemonica',
    'daemons': 'legiones daemonica',
    'daemon': 'legiones daemonica',
  };

  /// Resolve [raw] to a BSData-compatible query string.
  ///
  /// Returns the empty string if [raw] normalizes to empty.
  String resolve(String raw) {
    final normalized = _normalize(raw);
    if (normalized.isEmpty) return '';

    // Step 1: exact alias lookup.
    final exact = _aliases[normalized];
    if (exact != null) return exact;

    // Step 2: singular → plural alias (e.g. "daemon" → look up "daemons").
    if (!normalized.endsWith('s')) {
      final pluralAlias = _aliases['${normalized}s'];
      if (pluralAlias != null) return pluralAlias;
    }

    // Step 3: plural → singular alias (e.g. "daemons" → look up "daemon").
    if (normalized.endsWith('s') && normalized.length > 3) {
      final singularAlias =
          _aliases[normalized.substring(0, normalized.length - 1)];
      if (singularAlias != null) return singularAlias;
    }

    // Step 4: general plural stripping to improve M10 substring coverage.
    // E.g. "intercessors" → "intercessor" so that M10 can find
    // "intercessor squad" via substring matching.
    if (_shouldSingularize(normalized)) {
      return normalized.substring(0, normalized.length - 1);
    }

    return normalized;
  }

  /// Whether trailing 's' should be stripped from [s] as a plural→singular
  /// normalization step.
  ///
  /// Guards against stripping words that merely end in 's' without being
  /// regular English plurals (e.g. boss, nexus, abilities).
  static bool _shouldSingularize(String s) {
    if (!s.endsWith('s')) return false;
    if (s.endsWith('ss')) return false; // e.g. "boss"
    if (s.endsWith('us')) return false; // e.g. "nexus", "status"
    if (s.endsWith('ies')) return false; // irregular plural (abilities → ability)
    final stripped = s.substring(0, s.length - 1);
    return stripped.length >= 4; // guard against very short stems
  }

  /// Normalize: lowercase, strip non-alphanumeric non-space chars,
  /// collapse whitespace, trim.
  ///
  /// Matches [IndexService.normalize] so resolved queries are compatible
  /// with canonicalKey values in the index.
  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

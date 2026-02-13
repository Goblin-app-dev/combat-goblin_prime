import '../models/search_result.dart';

/// Formats a [SearchResult] for voice or display output.
///
/// This is an optional extension — not required for core M10 search.
/// Must not access [IndexBundle] directly. Operates on [SearchResult] only.
/// Must not access M6–M8 modules.
abstract class SearchPresentationFormatter {
  /// Format a search result into a presentation string.
  String format(SearchResult result);
}

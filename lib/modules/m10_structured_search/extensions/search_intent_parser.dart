import '../models/search_request.dart';

/// Converts natural language input into a [SearchRequest].
///
/// This is an optional extension — not required for core M10 search.
/// Must not access M6–M8 modules. Must not access [IndexBundle] directly.
abstract class SearchIntentParser {
  /// Parse a raw input string into a structured [SearchRequest].
  SearchRequest parse(String input);
}

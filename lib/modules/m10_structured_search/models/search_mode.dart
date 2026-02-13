/// Query execution mode for M10 search.
enum SearchMode {
  /// Prefix-based matching for incremental input.
  autocomplete,

  /// Full-text matching across display names and descriptions.
  fullText,

  /// Structured field-level filtering (keywords, characteristics, docTypes).
  structured,
}

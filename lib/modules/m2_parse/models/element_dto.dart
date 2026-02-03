/// Generic DTO representing any XML element, preserving structure and order.
///
/// Part of M2 Parse (Phase 1B).
class ElementDto {
  /// XML element tag (e.g., "catalogue", "selectionEntry", "profile").
  final String tagName;

  /// All XML attributes as key-value pairs.
  final Map<String, String> attributes;

  /// Child elements in document order.
  final List<ElementDto> children;

  /// Text content if present (null if element has only children).
  final String? textContent;

  /// Document-order index for diagnostics (nullable; best-effort).
  ///
  /// Dart's xml package does not guarantee line/column numbers.
  /// sourceIndex is a document-order counter (0, 1, 2, ...) assigned
  /// during parse traversal. Absence does not affect semantic correctness.
  final int? sourceIndex;

  const ElementDto({
    required this.tagName,
    required this.attributes,
    required this.children,
    this.textContent,
    this.sourceIndex,
  });
}

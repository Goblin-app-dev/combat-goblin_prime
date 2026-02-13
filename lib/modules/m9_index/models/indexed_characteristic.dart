/// A flattened characteristic for search indexing.
///
/// Represents a single stat field (e.g., M, T, SV, W, LD, OC for units;
/// Range, A, BS, S, AP, D for weapons).
///
/// This is a field type inside UnitDoc/WeaponDoc, not a standalone document.
///
/// Part of M9 Index-Core (Search).
class IndexedCharacteristic {
  /// The characteristic name (e.g., "M", "T", "Range").
  final String name;

  /// The profile type ID from M5 (for provenance).
  final String typeId;

  /// The display value as text (e.g., "6\"", "4", "3+").
  final String valueText;

  const IndexedCharacteristic({
    required this.name,
    required this.typeId,
    required this.valueText,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexedCharacteristic &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          typeId == other.typeId &&
          valueText == other.valueText;

  @override
  int get hashCode => name.hashCode ^ typeId.hashCode ^ valueText.hashCode;

  @override
  String toString() => 'IndexedCharacteristic($name: $valueText)';
}

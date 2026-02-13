/// A flattened cost entry for search indexing.
///
/// Represents a cost value (e.g., points, power level) for a unit.
/// Mirrors structure from M5 BoundCost for consistency.
///
/// Part of M9 Index-Core (Search).
class IndexedCost {
  /// Cost type ID (e.g., "pts", "PL").
  final String typeId;

  /// Cost type display name.
  final String typeName;

  /// Numeric value.
  final double value;

  const IndexedCost({
    required this.typeId,
    required this.typeName,
    required this.value,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexedCost &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId &&
          typeName == other.typeName &&
          value == other.value;

  @override
  int get hashCode => typeId.hashCode ^ typeName.hashCode ^ value.hashCode;

  @override
  String toString() => 'IndexedCost($typeName: $value)';
}

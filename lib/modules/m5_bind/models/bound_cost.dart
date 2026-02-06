import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Cost value.
///
/// Eligible tagNames: `cost`
///
/// Part of M5 Bind (Phase 3).
class BoundCost {
  /// References costType (stored as string, no registry lookup).
  final String typeId;

  /// costType name (may be null if type not found).
  final String? typeName;

  /// Numeric cost value.
  final double value;

  /// Provenance: file containing this cost.
  final String sourceFileId;

  /// Provenance: node reference.
  final NodeRef sourceNode;

  const BoundCost({
    required this.typeId,
    this.typeName,
    required this.value,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  String toString() =>
      'BoundCost(typeId: $typeId, value: $value)';
}

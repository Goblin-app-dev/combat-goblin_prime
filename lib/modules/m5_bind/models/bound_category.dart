import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Category definition.
///
/// Eligible tagNames: `categoryEntry`
///
/// Part of M5 Bind (Phase 3).
class BoundCategory {
  final String id;
  final String name;

  /// True if primary="true" on categoryEntry.
  final bool isPrimary;

  /// Provenance: file containing this category.
  final String sourceFileId;

  /// Provenance: node reference.
  final NodeRef sourceNode;

  const BoundCategory({
    required this.id,
    required this.name,
    required this.isPrimary,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  String toString() =>
      'BoundCategory(id: $id, name: $name, primary: $isPrimary)';
}

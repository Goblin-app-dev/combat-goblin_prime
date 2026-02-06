import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Profile definition with characteristics.
///
/// Eligible tagNames: `profile`
///
/// Part of M5 Bind (Phase 3).
class BoundProfile {
  final String id;
  final String name;

  /// References profileType (may be null if type not found).
  final String? typeId;

  /// profileType name (may be null if type not found).
  final String? typeName;

  /// Ordered name-value pairs for characteristics.
  final List<({String name, String value})> characteristics;

  /// Provenance: file containing this profile.
  final String sourceFileId;

  /// Provenance: node reference.
  final NodeRef sourceNode;

  const BoundProfile({
    required this.id,
    required this.name,
    this.typeId,
    this.typeName,
    required this.characteristics,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  String toString() =>
      'BoundProfile(id: $id, name: $name, characteristics: ${characteristics.length})';
}

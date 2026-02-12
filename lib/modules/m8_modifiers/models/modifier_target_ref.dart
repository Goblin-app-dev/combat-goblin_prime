import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Disambiguates field namespace for modifier targets.
///
/// Field strings can be ambiguous (e.g., "value" could be cost or constraint).
/// FieldKind resolves ambiguity at resolution time.
///
/// Part of M8 Modifiers (Phase 6).
enum FieldKind {
  /// Profile characteristic field.
  characteristic,

  /// Cost type field.
  cost,

  /// Constraint value field.
  constraint,

  /// Entry metadata (name, hidden, etc.).
  metadata,
}

/// Reference to a modifier target with field namespace disambiguation.
///
/// Combines targetId + field + fieldKind for unambiguous reference.
///
/// Part of M8 Modifiers (Phase 6).
class ModifierTargetRef {
  /// ID of target entry/profile/cost.
  final String targetId;

  /// Field name being modified.
  final String field;

  /// Namespace disambiguation.
  final FieldKind fieldKind;

  /// Optional scope restriction.
  final String? scope;

  /// Provenance: source file ID.
  final String sourceFileId;

  /// Provenance: source node reference.
  final NodeRef sourceNode;

  const ModifierTargetRef({
    required this.targetId,
    required this.field,
    required this.fieldKind,
    this.scope,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  String toString() =>
      'ModifierTargetRef(targetId: $targetId, field: $field, kind: $fieldKind'
      '${scope != null ? ', scope: $scope' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModifierTargetRef &&
          runtimeType == other.runtimeType &&
          targetId == other.targetId &&
          field == other.field &&
          fieldKind == other.fieldKind &&
          scope == other.scope &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode;

  @override
  int get hashCode =>
      targetId.hashCode ^
      field.hashCode ^
      fieldKind.hashCode ^
      scope.hashCode ^
      sourceFileId.hashCode ^
      sourceNode.hashCode;
}

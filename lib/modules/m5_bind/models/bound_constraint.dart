import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Constraint definition (not evaluated).
///
/// BoundConstraint captures raw fields and linked targets only; no truth evaluation.
/// Constraint data is stored, NOT evaluated.
/// Evaluation requires roster state (deferred to M6+).
///
/// Eligible tagNames: `constraint`
///
/// Part of M5 Bind (Phase 3).
class BoundConstraint {
  /// Constraint type (min, max, etc.).
  final String type;

  /// Field being constrained.
  final String field;

  /// Scope of constraint.
  final String scope;

  /// Constraint value.
  final int value;

  /// Optional constraint ID.
  final String? id;

  /// Provenance: file containing this constraint.
  final String sourceFileId;

  /// Provenance: node reference.
  final NodeRef sourceNode;

  const BoundConstraint({
    required this.type,
    required this.field,
    required this.scope,
    required this.value,
    this.id,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  String toString() =>
      'BoundConstraint(type: $type, field: $field, scope: $scope, value: $value)';
}

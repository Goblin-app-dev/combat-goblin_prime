/// Defines the boundary of evaluation.
///
/// Part of M6 Evaluate (Phase 4).
class EvaluationScope {
  /// Scope type: self, parent, force, roster.
  final String scopeType;

  /// The selection defining the boundary (null for roster scope).
  final String? boundarySelectionId;

  const EvaluationScope({
    required this.scopeType,
    this.boundarySelectionId,
  });

  @override
  String toString() =>
      'EvaluationScope(scopeType: $scopeType, boundarySelectionId: $boundarySelectionId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationScope &&
          runtimeType == other.runtimeType &&
          scopeType == other.scopeType &&
          boundarySelectionId == other.boundarySelectionId;

  @override
  int get hashCode => scopeType.hashCode ^ boundarySelectionId.hashCode;
}

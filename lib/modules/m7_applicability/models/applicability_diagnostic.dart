import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Diagnostic codes for M7 Applicability.
///
/// Closed set. New codes require doc + glossary update.
///
/// Part of M7 Applicability (Phase 5).
enum ApplicabilityDiagnosticCode {
  /// Condition type not recognized.
  unknownConditionType,

  /// Scope keyword not recognized.
  unknownConditionScopeKeyword,

  /// Field keyword not recognized.
  unknownConditionFieldKeyword,

  /// Scope is ID-like but not found in bundle.
  unresolvedConditionScopeId,

  /// Field is ID-like but not found in bundle.
  unresolvedConditionFieldId,

  /// childId not found in bundle.
  unresolvedChildId,

  /// Cost field requested but snapshot lacks cost data.
  snapshotDataGapCosts,

  /// Cannot compute includeChildSelections distinction.
  snapshotDataGapChildSemantics,

  /// Cannot resolve category-id scope.
  snapshotDataGapCategories,

  /// Cannot determine force boundary.
  snapshotDataGapForceBoundary,
}

/// Non-fatal issue during M7 Applicability evaluation.
///
/// Diagnostics do not collapse into "skipped". Unknown types/scopes/fields
/// produce [ApplicabilityState.unknown] and emit a diagnostic.
///
/// Diagnostics are accumulated, never thrown.
///
/// Part of M7 Applicability (Phase 5).
class ApplicabilityDiagnostic {
  /// Diagnostic code.
  final ApplicabilityDiagnosticCode code;

  /// Human-readable description.
  final String message;

  /// File where issue occurred.
  final String sourceFileId;

  /// Node where issue occurred (may be null if not node-specific).
  final NodeRef? sourceNode;

  /// The ID involved (if applicable).
  final String? targetId;

  const ApplicabilityDiagnostic({
    required this.code,
    required this.message,
    required this.sourceFileId,
    this.sourceNode,
    this.targetId,
  });

  /// Returns the code as a string constant.
  String get codeString {
    switch (code) {
      case ApplicabilityDiagnosticCode.unknownConditionType:
        return 'UNKNOWN_CONDITION_TYPE';
      case ApplicabilityDiagnosticCode.unknownConditionScopeKeyword:
        return 'UNKNOWN_CONDITION_SCOPE_KEYWORD';
      case ApplicabilityDiagnosticCode.unknownConditionFieldKeyword:
        return 'UNKNOWN_CONDITION_FIELD_KEYWORD';
      case ApplicabilityDiagnosticCode.unresolvedConditionScopeId:
        return 'UNRESOLVED_CONDITION_SCOPE_ID';
      case ApplicabilityDiagnosticCode.unresolvedConditionFieldId:
        return 'UNRESOLVED_CONDITION_FIELD_ID';
      case ApplicabilityDiagnosticCode.unresolvedChildId:
        return 'UNRESOLVED_CHILD_ID';
      case ApplicabilityDiagnosticCode.snapshotDataGapCosts:
        return 'SNAPSHOT_DATA_GAP_COSTS';
      case ApplicabilityDiagnosticCode.snapshotDataGapChildSemantics:
        return 'SNAPSHOT_DATA_GAP_CHILD_SEMANTICS';
      case ApplicabilityDiagnosticCode.snapshotDataGapCategories:
        return 'SNAPSHOT_DATA_GAP_CATEGORIES';
      case ApplicabilityDiagnosticCode.snapshotDataGapForceBoundary:
        return 'SNAPSHOT_DATA_GAP_FORCE_BOUNDARY';
    }
  }

  @override
  String toString() =>
      'ApplicabilityDiagnostic(code: $codeString, message: $message${targetId != null ? ', targetId: $targetId' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApplicabilityDiagnostic &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode &&
          targetId == other.targetId;

  @override
  int get hashCode =>
      code.hashCode ^
      message.hashCode ^
      sourceFileId.hashCode ^
      sourceNode.hashCode ^
      targetId.hashCode;
}

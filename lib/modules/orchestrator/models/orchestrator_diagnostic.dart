import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Source module for a diagnostic.
enum DiagnosticSource {
  /// M6 Evaluate constraint diagnostic.
  m6,

  /// M7 Applicability condition diagnostic.
  m7,

  /// M8 Modifiers diagnostic.
  m8,

  /// Orchestrator-specific diagnostic.
  orchestrator,
}

/// Orchestrator-specific diagnostic codes.
enum OrchestratorDiagnosticCode {
  /// Selection references entry not in BoundPackBundle.
  selectionNotInBundle,

  /// Internal ordering invariant violated (fatal).
  evaluationOrderViolation,
}

/// Unified diagnostic from orchestration.
///
/// Wraps diagnostics from M6/M7/M8 with source attribution,
/// or represents Orchestrator-specific issues.
///
/// Module diagnostics are preserved with original codes unchanged.
///
/// Part of Orchestrator v1 (PROPOSED).
class OrchestratorDiagnostic {
  /// Origin module: M6, M7, M8, or ORCHESTRATOR.
  final DiagnosticSource source;

  /// Original diagnostic code (unchanged from source module).
  final String code;

  /// Human-readable description.
  final String message;

  /// File where issue occurred.
  final String sourceFileId;

  /// Node where issue occurred (may be null).
  final NodeRef? sourceNode;

  /// ID involved (if applicable).
  final String? targetId;

  const OrchestratorDiagnostic({
    required this.source,
    required this.code,
    required this.message,
    required this.sourceFileId,
    this.sourceNode,
    this.targetId,
  });

  /// Creates diagnostic from Orchestrator-specific code.
  factory OrchestratorDiagnostic.fromOrchestratorCode({
    required OrchestratorDiagnosticCode code,
    required String message,
    required String sourceFileId,
    NodeRef? sourceNode,
    String? targetId,
  }) {
    return OrchestratorDiagnostic(
      source: DiagnosticSource.orchestrator,
      code: _codeToString(code),
      message: message,
      sourceFileId: sourceFileId,
      sourceNode: sourceNode,
      targetId: targetId,
    );
  }

  static String _codeToString(OrchestratorDiagnosticCode code) {
    switch (code) {
      case OrchestratorDiagnosticCode.selectionNotInBundle:
        return 'SELECTION_NOT_IN_BUNDLE';
      case OrchestratorDiagnosticCode.evaluationOrderViolation:
        return 'EVALUATION_ORDER_VIOLATION';
    }
  }

  @override
  String toString() =>
      'OrchestratorDiagnostic(source: $source, code: $code, message: $message'
      '${targetId != null ? ', targetId: $targetId' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrchestratorDiagnostic &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          code == other.code &&
          message == other.message &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode &&
          targetId == other.targetId;

  @override
  int get hashCode =>
      source.hashCode ^
      code.hashCode ^
      message.hashCode ^
      sourceFileId.hashCode ^
      sourceNode.hashCode ^
      targetId.hashCode;
}

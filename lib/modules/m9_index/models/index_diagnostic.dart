import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Closed set of diagnostic codes for M9 Index-Core.
///
/// These codes represent non-fatal issues detected during indexing.
/// No new codes may be added post-freeze without a new phase.
enum IndexDiagnosticCode {
  /// Entity missing required name field.
  missingName,

  /// Canonical key collision between two documents.
  duplicateDocKey,

  /// Rule canonical key collision with differing descriptions.
  duplicateRuleCanonicalKey,

  /// Profile has unrecognized typeId/typeName.
  unknownProfileType,

  /// Profile has no characteristics.
  emptyCharacteristics,

  /// Rule description was truncated.
  truncatedDescription,

  /// Unit→Weapon or Weapon→Rule link target not found.
  linkTargetMissing,
}

/// Non-fatal issue detected during M9 indexing.
///
/// Diagnostics are collected, never thrown. Processing continues.
/// All diagnostics are preserved in IndexBundle for reporting.
///
/// Part of M9 Index-Core (Search).
class IndexDiagnostic {
  /// The diagnostic code (from closed set).
  final IndexDiagnosticCode code;

  /// Human-readable message describing the issue.
  final String message;

  /// Source file where issue originated (for provenance).
  final String? sourceFileId;

  /// Source node reference (for provenance).
  final NodeRef? sourceNode;

  /// Target ID that caused the issue (if applicable).
  final String? targetId;

  const IndexDiagnostic({
    required this.code,
    required this.message,
    this.sourceFileId,
    this.sourceNode,
    this.targetId,
  });

  /// Returns the canonical string code for this diagnostic.
  ///
  /// Used for serialization and diagnostic counting.
  String get codeString {
    switch (code) {
      case IndexDiagnosticCode.missingName:
        return 'MISSING_NAME';
      case IndexDiagnosticCode.duplicateDocKey:
        return 'DUPLICATE_DOC_KEY';
      case IndexDiagnosticCode.duplicateRuleCanonicalKey:
        return 'DUPLICATE_RULE_CANONICAL_KEY';
      case IndexDiagnosticCode.unknownProfileType:
        return 'UNKNOWN_PROFILE_TYPE';
      case IndexDiagnosticCode.emptyCharacteristics:
        return 'EMPTY_CHARACTERISTICS';
      case IndexDiagnosticCode.truncatedDescription:
        return 'TRUNCATED_DESCRIPTION';
      case IndexDiagnosticCode.linkTargetMissing:
        return 'LINK_TARGET_MISSING';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndexDiagnostic &&
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
      (sourceFileId?.hashCode ?? 0) ^
      (sourceNode?.hashCode ?? 0) ^
      (targetId?.hashCode ?? 0);

  @override
  String toString() =>
      'IndexDiagnostic(${codeString}: $message${targetId != null ? ' [target=$targetId]' : ''})';
}

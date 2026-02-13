import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Closed set of diagnostic codes for M9 Index-Core.
///
/// **STATUS: FROZEN** (2026-02-13)
///
/// These codes represent non-fatal issues detected during indexing.
/// No new codes may be added post-freeze without a new module version.
///
/// ## Frozen Codes
/// - `missingName`: Entity missing required name field
/// - `duplicateDocId`: Duplicate docId detected (data issue)
/// - `unknownProfileType`: Profile has unrecognized typeId/typeName
/// - `emptyCharacteristics`: Profile has no characteristics
/// - `truncatedDescription`: Rule description was truncated
/// - `linkTargetMissing`: Unit→Weapon or Weapon→Rule link target not found
/// - `duplicateSourceProfileSkipped`: Summary of deduplicated profiles
///
/// Note: Multiple docs sharing the same canonicalKey is EXPECTED
/// (e.g., "Bolt Rifle" on many units). This is not a diagnostic.
/// Only docId collisions (which indicate data issues) are reported.
enum IndexDiagnosticCode {
  /// Entity missing required name field.
  missingName,

  /// Duplicate docId detected (indicates data issue, should be rare).
  /// docId format is "type:{stableId}" so collisions mean duplicate IDs.
  duplicateDocId,

  /// Profile has unrecognized typeId/typeName.
  unknownProfileType,

  /// Profile has no characteristics.
  emptyCharacteristics,

  /// Rule description was truncated.
  truncatedDescription,

  /// Unit→Weapon or Weapon→Rule link target not found.
  linkTargetMissing,

  /// Source profiles were deduplicated (same profileId on multiple entries).
  /// Emitted once as a summary with count, not per-instance.
  duplicateSourceProfileSkipped,
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
      case IndexDiagnosticCode.duplicateDocId:
        return 'DUPLICATE_DOC_ID';
      case IndexDiagnosticCode.unknownProfileType:
        return 'UNKNOWN_PROFILE_TYPE';
      case IndexDiagnosticCode.emptyCharacteristics:
        return 'EMPTY_CHARACTERISTICS';
      case IndexDiagnosticCode.truncatedDescription:
        return 'TRUNCATED_DESCRIPTION';
      case IndexDiagnosticCode.linkTargetMissing:
        return 'LINK_TARGET_MISSING';
      case IndexDiagnosticCode.duplicateSourceProfileSkipped:
        return 'DUPLICATE_SOURCE_PROFILE_SKIPPED';
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

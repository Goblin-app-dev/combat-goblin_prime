import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Diagnostic codes for M8 Modifiers.
///
/// Closed set. New codes require doc + glossary update.
///
/// Part of M8 Modifiers (Phase 6).
enum ModifierDiagnosticCode {
  /// Modifier type not recognized.
  unknownModifierType,

  /// Field not recognized.
  unknownModifierField,

  /// Scope keyword not recognized.
  unknownModifierScope,

  /// Target ID not found in bundle.
  unresolvedModifierTarget,

  /// Value type incompatible with field.
  incompatibleValueType,

  /// Target kind not supported for this operation.
  unsupportedTargetKind,

  /// Scope not supported for this target kind.
  unsupportedTargetScope,
}

/// Non-fatal issue during M8 Modifiers processing.
///
/// Diagnostics are accumulated, never thrown.
/// Unknown types/fields/scopes produce diagnostics and skip operations.
///
/// Part of M8 Modifiers (Phase 6).
class ModifierDiagnostic {
  /// Diagnostic code.
  final ModifierDiagnosticCode code;

  /// Human-readable description.
  final String message;

  /// File where issue occurred.
  final String sourceFileId;

  /// Node where issue occurred (may be null if not node-specific).
  final NodeRef? sourceNode;

  /// The ID involved (if applicable).
  final String? targetId;

  const ModifierDiagnostic({
    required this.code,
    required this.message,
    required this.sourceFileId,
    this.sourceNode,
    this.targetId,
  });

  /// Returns the code as a string constant.
  String get codeString {
    switch (code) {
      case ModifierDiagnosticCode.unknownModifierType:
        return 'UNKNOWN_MODIFIER_TYPE';
      case ModifierDiagnosticCode.unknownModifierField:
        return 'UNKNOWN_MODIFIER_FIELD';
      case ModifierDiagnosticCode.unknownModifierScope:
        return 'UNKNOWN_MODIFIER_SCOPE';
      case ModifierDiagnosticCode.unresolvedModifierTarget:
        return 'UNRESOLVED_MODIFIER_TARGET';
      case ModifierDiagnosticCode.incompatibleValueType:
        return 'INCOMPATIBLE_VALUE_TYPE';
      case ModifierDiagnosticCode.unsupportedTargetKind:
        return 'UNSUPPORTED_TARGET_KIND';
      case ModifierDiagnosticCode.unsupportedTargetScope:
        return 'UNSUPPORTED_TARGET_SCOPE';
    }
  }

  @override
  String toString() =>
      'ModifierDiagnostic(code: $codeString, message: $message'
      '${targetId != null ? ', targetId: $targetId' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModifierDiagnostic &&
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

import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Non-fatal semantic issue detected during M5 binding.
///
/// Part of M5 Bind (Phase 3).
class BindDiagnostic {
  /// Diagnostic code (closed set).
  final String code;

  /// Human-readable description.
  final String message;

  /// File where issue occurred.
  final String sourceFileId;

  /// Node where issue occurred (if applicable).
  final NodeRef? sourceNode;

  /// The ID involved (if applicable).
  final String? targetId;

  const BindDiagnostic({
    required this.code,
    required this.message,
    required this.sourceFileId,
    this.sourceNode,
    this.targetId,
  });

  @override
  String toString() =>
      'BindDiagnostic($code: $message, file: $sourceFileId)';
}

/// Closed set of diagnostic codes for M5 Bind.
abstract class BindDiagnosticCode {
  /// entryLink targetId not found.
  static const unresolvedEntryLink = 'UNRESOLVED_ENTRY_LINK';

  /// infoLink targetId not found.
  static const unresolvedInfoLink = 'UNRESOLVED_INFO_LINK';

  /// categoryLink targetId not found.
  static const unresolvedCategoryLink = 'UNRESOLVED_CATEGORY_LINK';

  /// ID matched multiple targets, using first.
  static const shadowedDefinition = 'SHADOWED_DEFINITION';

  /// profile references unknown profileType.
  static const invalidProfileType = 'INVALID_PROFILE_TYPE';

  /// cost references unknown costType.
  static const invalidCostType = 'INVALID_COST_TYPE';
}

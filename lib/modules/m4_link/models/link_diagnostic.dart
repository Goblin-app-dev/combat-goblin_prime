import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Non-fatal resolution issue detected during M4 linking.
///
/// Diagnostics are accumulated (not thrown), do not stop processing,
/// and are attached to the LinkedPackBundle.
///
/// Part of M4 Link (Phase 2).
class LinkDiagnostic {
  /// Diagnostic code from the closed set.
  final String code;

  /// Human-readable description.
  final String message;

  /// File where the issue occurred.
  final String sourceFileId;

  /// Node where the issue occurred (if applicable).
  final NodeRef? sourceNode;

  /// The ID involved (if applicable).
  final String? targetId;

  const LinkDiagnostic({
    required this.code,
    required this.message,
    required this.sourceFileId,
    this.sourceNode,
    this.targetId,
  });

  @override
  String toString() =>
      'LinkDiagnostic($code: $message, file: $sourceFileId, targetId: $targetId)';
}

/// Diagnostic codes (closed set).
///
/// New codes require doc + glossary update.
abstract class LinkDiagnosticCode {
  /// targetId not found in SymbolTable (zero targets).
  /// Behavior: emit diagnostic, ResolvedRef.targets is empty, continue.
  static const unresolvedTarget = 'UNRESOLVED_TARGET';

  /// targetId found >1 time in SymbolTable.
  /// Behavior: emit diagnostic, keep ALL targets, continue.
  static const duplicateIdReference = 'DUPLICATE_ID_REFERENCE';

  /// Link element has no targetId attribute, or targetId is empty/whitespace.
  /// Behavior: emit diagnostic, no ResolvedRef created, continue.
  static const invalidLinkFormat = 'INVALID_LINK_FORMAT';
}

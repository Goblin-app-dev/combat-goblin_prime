import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'link_diagnostic.dart';
import 'resolved_ref.dart';
import 'symbol_table.dart';

/// Complete M4 output for a pack.
///
/// One-to-one correspondence with input WrappedPackBundle.
/// Contains resolution results but does not modify wrapped nodes.
/// Preserves provenance chain (M4 → M3 → M2 → M1).
///
/// Part of M4 Link (Phase 2).
class LinkedPackBundle {
  /// From WrappedPackBundle.packId.
  final String packId;

  /// When linking completed.
  final DateTime linkedAt;

  /// Cross-file ID registry.
  final SymbolTable symbolTable;

  /// Resolved references for all link elements.
  final List<ResolvedRef> resolvedRefs;

  /// Non-fatal diagnostics accumulated during linking.
  final List<LinkDiagnostic> diagnostics;

  /// Reference to M3 input (immutable).
  final WrappedPackBundle wrappedBundle;

  const LinkedPackBundle({
    required this.packId,
    required this.linkedAt,
    required this.symbolTable,
    required this.resolvedRefs,
    required this.diagnostics,
    required this.wrappedBundle,
  });

  /// True if there are any diagnostics.
  bool get hasDiagnostics => diagnostics.isNotEmpty;

  /// Count of unresolved references.
  int get unresolvedCount => diagnostics
      .where((d) => d.code == LinkDiagnosticCode.unresolvedTarget)
      .length;

  /// Count of duplicate ID references.
  int get duplicateRefCount => diagnostics
      .where((d) => d.code == LinkDiagnosticCode.duplicateIdReference)
      .length;

  /// Count of invalid link format errors.
  int get invalidFormatCount => diagnostics
      .where((d) => d.code == LinkDiagnosticCode.invalidLinkFormat)
      .length;
}

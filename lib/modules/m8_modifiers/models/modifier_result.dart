import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'modifier_diagnostic.dart';
import 'modifier_operation.dart';
import 'modifier_target_ref.dart';
import 'modifier_value.dart';

/// Complete result of modifier application for a target.
///
/// Contains base value, effective value, applied/skipped operations,
/// diagnostics, and provenance.
///
/// Determinism guarantee: Same inputs → identical ModifierResult.
/// Operations applied in XML traversal order.
///
/// Part of M8 Modifiers (Phase 6).
class ModifierResult {
  /// What was modified.
  final ModifierTargetRef target;

  /// Value before modifiers (null if no base value).
  final ModifierValue? baseValue;

  /// Value after modifiers (null if no effective value computed).
  final ModifierValue? effectiveValue;

  /// Operations that were applied.
  final List<ModifierOperation> appliedOperations;

  /// Operations that were skipped (not applicable or errors).
  final List<ModifierOperation> skippedOperations;

  /// Diagnostics from this evaluation.
  final List<ModifierDiagnostic> diagnostics;

  /// Provenance: source file ID.
  final String sourceFileId;

  /// Provenance: source node reference.
  final NodeRef sourceNode;

  const ModifierResult({
    required this.target,
    this.baseValue,
    this.effectiveValue,
    required this.appliedOperations,
    required this.skippedOperations,
    required this.diagnostics,
    required this.sourceFileId,
    required this.sourceNode,
  });

  /// Creates a result with no modifiers applied (base value preserved).
  factory ModifierResult.unchanged({
    required ModifierTargetRef target,
    ModifierValue? baseValue,
    required String sourceFileId,
    required NodeRef sourceNode,
    List<ModifierDiagnostic> diagnostics = const [],
  }) {
    return ModifierResult(
      target: target,
      baseValue: baseValue,
      effectiveValue: baseValue,
      appliedOperations: const [],
      skippedOperations: const [],
      diagnostics: diagnostics,
      sourceFileId: sourceFileId,
      sourceNode: sourceNode,
    );
  }

  @override
  String toString() =>
      'ModifierResult(target: ${target.targetId}.${target.field}, '
      'base: $baseValue, effective: $effectiveValue, '
      'applied: ${appliedOperations.length}, skipped: ${skippedOperations.length}, '
      'diagnostics: ${diagnostics.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModifierResult &&
          runtimeType == other.runtimeType &&
          target == other.target &&
          baseValue == other.baseValue &&
          effectiveValue == other.effectiveValue &&
          _listEquals(appliedOperations, other.appliedOperations) &&
          _listEquals(skippedOperations, other.skippedOperations) &&
          _listEquals(diagnostics, other.diagnostics) &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode;

  @override
  int get hashCode =>
      target.hashCode ^
      baseValue.hashCode ^
      effectiveValue.hashCode ^
      _deepListHash(appliedOperations) ^
      _deepListHash(skippedOperations) ^
      _deepListHash(diagnostics) ^
      sourceFileId.hashCode ^
      sourceNode.hashCode;

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Computes a deterministic hash for a list based on element hashes.
  static int _deepListHash<T>(List<T> list) {
    var hash = 0;
    for (var i = 0; i < list.length; i++) {
      hash = hash ^ (list[i].hashCode * (i + 1));
    }
    return hash;
  }
}

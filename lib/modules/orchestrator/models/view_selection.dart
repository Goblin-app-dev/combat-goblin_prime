import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m7_applicability/m7_applicability.dart';
import 'package:combat_goblin_prime/modules/m8_modifiers/m8_modifiers.dart';

/// Computed view of a single selection with all evaluations applied.
///
/// Contains effective values after modifier application and
/// references to all evaluation results for this selection.
///
/// Part of Orchestrator v1 (PROPOSED).
class ViewSelection {
  /// Selection identity.
  final String selectionId;

  /// Entry ID from snapshot.
  final String entryId;

  /// Reference to bound entry (for downstream lookups).
  final BoundEntry? boundEntry;

  /// Modifiers applied to this selection.
  final List<ModifierResult> appliedModifiers;

  /// Conditions evaluated for this selection.
  final List<ApplicabilityResult> applicabilityResults;

  /// Computed values after modifiers, keyed by field name.
  ///
  /// null value means "unknown" or "not computed".
  /// Fields sorted alphabetically for determinism.
  final Map<String, ModifierValue?> effectiveValues;

  /// Provenance: source file ID.
  final String sourceFileId;

  /// Provenance: source node reference.
  final NodeRef sourceNode;

  const ViewSelection({
    required this.selectionId,
    required this.entryId,
    this.boundEntry,
    required this.appliedModifiers,
    required this.applicabilityResults,
    required this.effectiveValues,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  String toString() =>
      'ViewSelection(selectionId: $selectionId, entryId: $entryId, '
      'modifiers: ${appliedModifiers.length}, '
      'effectiveValues: ${effectiveValues.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewSelection &&
          runtimeType == other.runtimeType &&
          selectionId == other.selectionId &&
          entryId == other.entryId &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode &&
          _listEquals(appliedModifiers, other.appliedModifiers) &&
          _listEquals(applicabilityResults, other.applicabilityResults) &&
          _mapEquals(effectiveValues, other.effectiveValues);

  @override
  int get hashCode =>
      selectionId.hashCode ^
      entryId.hashCode ^
      sourceFileId.hashCode ^
      sourceNode.hashCode ^
      _deepListHash(appliedModifiers) ^
      _deepListHash(applicabilityResults) ^
      _deepMapHash(effectiveValues);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  static int _deepListHash<T>(List<T> list) {
    var hash = 0;
    for (final item in list) {
      hash = hash ^ item.hashCode;
    }
    return hash;
  }

  static int _deepMapHash<K, V>(Map<K, V> map) {
    var hash = 0;
    for (final entry in map.entries) {
      hash = hash ^ entry.key.hashCode ^ entry.value.hashCode;
    }
    return hash;
  }
}

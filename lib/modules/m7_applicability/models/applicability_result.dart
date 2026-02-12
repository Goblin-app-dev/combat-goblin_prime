import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'condition_evaluation.dart';
import 'condition_group_evaluation.dart';

/// Tri-state enum for applicability outcomes.
///
/// Applicability is **not boolean**. M7 distinguishes:
/// - [applies]: conditions true (or no conditions present)
/// - [skipped]: conditions evaluated false; constraint/modifier should not apply
/// - [unknown]: cannot determine; missing data, unsupported operator, unresolved reference
///
/// Part of M7 Applicability (Phase 5).
enum ApplicabilityState {
  /// Conditions are met (or no conditions present).
  applies,

  /// Conditions evaluated to false; the conditional element should not apply.
  skipped,

  /// Cannot determine applicability due to missing data, unsupported
  /// operator, or unresolved reference.
  unknown,
}

/// Complete applicability evaluation result.
///
/// Contains:
/// - Final tri-state applicability
/// - Deterministic reason text
/// - Leaf and group evaluation details
/// - Provenance identity (index-ready)
///
/// Determinism guarantee: Same inputs → identical ApplicabilityResult.
///
/// Part of M7 Applicability (Phase 5).
class ApplicabilityResult {
  /// Final tri-state result.
  final ApplicabilityState state;

  /// Human-readable explanation (deterministic).
  ///
  /// Set when state is [ApplicabilityState.skipped] or [ApplicabilityState.unknown].
  /// Null when state is [ApplicabilityState.applies].
  final String? reason;

  /// Leaf condition evaluations in XML traversal order.
  final List<ConditionEvaluation> conditionResults;

  /// Top-level group result (if conditions are grouped).
  final ConditionGroupEvaluation? groupResult;

  /// Provenance: source file ID (index-ready).
  final String sourceFileId;

  /// Provenance: source node reference (index-ready).
  final NodeRef sourceNode;

  /// Optional referenced target ID (when applicable).
  final String? targetId;

  const ApplicabilityResult({
    required this.state,
    this.reason,
    required this.conditionResults,
    this.groupResult,
    required this.sourceFileId,
    required this.sourceNode,
    this.targetId,
  });

  /// Creates an [ApplicabilityResult] with state [ApplicabilityState.applies].
  ///
  /// Used when no conditions are present or all conditions are met.
  factory ApplicabilityResult.applies({
    required String sourceFileId,
    required NodeRef sourceNode,
    List<ConditionEvaluation> conditionResults = const [],
    ConditionGroupEvaluation? groupResult,
    String? targetId,
  }) {
    return ApplicabilityResult(
      state: ApplicabilityState.applies,
      reason: null,
      conditionResults: conditionResults,
      groupResult: groupResult,
      sourceFileId: sourceFileId,
      sourceNode: sourceNode,
      targetId: targetId,
    );
  }

  /// Creates an [ApplicabilityResult] with state [ApplicabilityState.skipped].
  ///
  /// Used when conditions evaluate to false.
  factory ApplicabilityResult.skipped({
    required String reason,
    required String sourceFileId,
    required NodeRef sourceNode,
    required List<ConditionEvaluation> conditionResults,
    ConditionGroupEvaluation? groupResult,
    String? targetId,
  }) {
    return ApplicabilityResult(
      state: ApplicabilityState.skipped,
      reason: reason,
      conditionResults: conditionResults,
      groupResult: groupResult,
      sourceFileId: sourceFileId,
      sourceNode: sourceNode,
      targetId: targetId,
    );
  }

  /// Creates an [ApplicabilityResult] with state [ApplicabilityState.unknown].
  ///
  /// Used when conditions cannot be evaluated.
  factory ApplicabilityResult.unknown({
    required String reason,
    required String sourceFileId,
    required NodeRef sourceNode,
    required List<ConditionEvaluation> conditionResults,
    ConditionGroupEvaluation? groupResult,
    String? targetId,
  }) {
    return ApplicabilityResult(
      state: ApplicabilityState.unknown,
      reason: reason,
      conditionResults: conditionResults,
      groupResult: groupResult,
      sourceFileId: sourceFileId,
      sourceNode: sourceNode,
      targetId: targetId,
    );
  }

  @override
  String toString() =>
      'ApplicabilityResult(state: $state${reason != null ? ', reason: $reason' : ''}, conditions: ${conditionResults.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ApplicabilityResult &&
          runtimeType == other.runtimeType &&
          state == other.state &&
          reason == other.reason &&
          _listEquals(conditionResults, other.conditionResults) &&
          groupResult == other.groupResult &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode &&
          targetId == other.targetId;

  @override
  int get hashCode =>
      state.hashCode ^
      reason.hashCode ^
      conditionResults.hashCode ^
      groupResult.hashCode ^
      sourceFileId.hashCode ^
      sourceNode.hashCode ^
      targetId.hashCode;

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

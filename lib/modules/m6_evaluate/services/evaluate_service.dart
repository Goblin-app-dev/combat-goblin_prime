import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';

import '../contracts/selection_snapshot.dart';
import '../models/constraint_evaluation.dart';
import '../models/constraint_evaluation_outcome.dart';
import '../models/constraint_violation.dart';
import '../models/evaluate_failure.dart';
import '../models/evaluation_notice.dart';
import '../models/evaluation_report.dart';
import '../models/evaluation_scope.dart';
import '../models/evaluation_source_ref.dart';
import '../models/evaluation_summary.dart';
import '../models/evaluation_telemetry.dart';
import '../models/evaluation_warning.dart';

/// Service that evaluates constraints against a selection snapshot.
///
/// Part of M6 Evaluate (Phase 4).
class EvaluateService {
  /// Known constraint types.
  static const _knownTypes = {'min', 'max'};

  /// Known constraint fields.
  static const _knownFields = {'selections', 'forces'};

  /// Known constraint scopes.
  static const _knownScopes = {'self', 'parent', 'force', 'roster'};

  /// Evaluates constraints against a selection snapshot.
  ///
  /// Returns (EvaluationReport, EvaluationTelemetry?) where:
  /// - EvaluationReport is strictly deterministic
  /// - EvaluationTelemetry is optional, non-deterministic instrumentation
  (EvaluationReport, EvaluationTelemetry?) evaluateConstraints({
    required BoundPackBundle boundBundle,
    required SelectionSnapshot snapshot,
  }) {
    final stopwatch = Stopwatch()..start();

    // Validate invariants
    _validateInvariants(boundBundle, snapshot);

    final warnings = <EvaluationWarning>[];
    final notices = <EvaluationNotice>[];
    final evaluations = <ConstraintEvaluation>[];

    final selections = snapshot.orderedSelections();

    // Handle empty snapshot
    if (selections.isEmpty) {
      notices.add(const EvaluationNotice(
        code: EvaluationNotice.codeEmptySnapshot,
        message: 'Snapshot has no selections to evaluate',
      ));

      stopwatch.stop();
      return (
        EvaluationReport(
          packId: boundBundle.packId,
          evaluatedAt: boundBundle.boundAt,
          constraintEvaluations: const [],
          summary: const EvaluationSummary(
            totalEvaluations: 0,
            satisfiedCount: 0,
            violatedCount: 0,
            notApplicableCount: 0,
            errorCount: 0,
          ),
          warnings: warnings,
          notices: notices,
          boundBundle: boundBundle,
        ),
        EvaluationTelemetry(evaluationDuration: stopwatch.elapsed),
      );
    }

    // Build count tables for O(1) lookup
    final countTables = _buildCountTables(snapshot, selections);

    // Build entry lookup map
    final entryById = <String, BoundEntry>{};
    for (final entry in boundBundle.entries) {
      entryById[entry.id] = entry;
    }

    // Evaluate constraints for each selection
    for (final selectionId in selections) {
      final entryId = snapshot.entryIdFor(selectionId);
      final entry = entryById[entryId];

      // Handle missing entry reference
      if (entry == null) {
        warnings.add(EvaluationWarning(
          code: EvaluationWarning.codeMissingEntryReference,
          message: 'Selection $selectionId references entry $entryId not found in bundle',
        ));
        // Still traverse children - they may reference valid entries
        continue;
      }

      // Evaluate each constraint on the entry (in stored order)
      for (final constraint in entry.constraints) {
        final evaluation = _evaluateConstraint(
          constraint: constraint,
          entry: entry,
          selectionId: selectionId,
          snapshot: snapshot,
          countTables: countTables,
          warnings: warnings,
        );
        evaluations.add(evaluation);
      }
    }

    // Build summary
    final summary = _buildSummary(evaluations);

    stopwatch.stop();

    return (
      EvaluationReport(
        packId: boundBundle.packId,
        evaluatedAt: boundBundle.boundAt,
        constraintEvaluations: evaluations,
        summary: summary,
        warnings: warnings,
        notices: notices,
        boundBundle: boundBundle,
      ),
      EvaluationTelemetry(evaluationDuration: stopwatch.elapsed),
    );
  }

  /// Validates invariants before evaluation.
  void _validateInvariants(
    BoundPackBundle boundBundle,
    SelectionSnapshot snapshot,
  ) {
    // NULL_PROVENANCE: Required provenance pointers missing
    if (boundBundle.linkedBundle == null) {
      throw EvaluateFailure(
        invariant: EvaluateFailure.invariantNullProvenance,
        message: 'BoundPackBundle.linkedBundle is null',
      );
    }

    final selections = snapshot.orderedSelections();
    final selectionSet = selections.toSet();

    // Check for invalid children type and other invariants
    final visited = <String>{};
    final visiting = <String>{};

    void checkSelection(String selectionId) {
      if (visiting.contains(selectionId)) {
        throw EvaluateFailure(
          invariant: EvaluateFailure.invariantCycleDetected,
          message: 'Cycle detected in selection hierarchy at $selectionId',
        );
      }
      if (visited.contains(selectionId)) return;

      visiting.add(selectionId);

      final children = snapshot.childrenOf(selectionId);

      // INVALID_CHILDREN_TYPE: Already enforced by abstract class returning List
      // DUPLICATE_CHILD_ID: Check for duplicates
      final childSet = <String>{};
      for (final childId in children) {
        if (childSet.contains(childId)) {
          throw EvaluateFailure(
            invariant: EvaluateFailure.invariantDuplicateChildId,
            message: 'Duplicate child ID $childId in children of $selectionId',
          );
        }
        childSet.add(childId);

        // UNKNOWN_CHILD_ID: Check child exists in selections
        if (!selectionSet.contains(childId)) {
          throw EvaluateFailure(
            invariant: EvaluateFailure.invariantUnknownChildId,
            message: 'Unknown child ID $childId referenced by $selectionId',
          );
        }

        checkSelection(childId);
      }

      visiting.remove(selectionId);
      visited.add(selectionId);
    }

    // Start from root selections (those without parents or with null parent)
    for (final selectionId in selections) {
      if (snapshot.parentOf(selectionId) == null) {
        checkSelection(selectionId);
      }
    }

    // Check for orphaned cycles (selections with parents but not reachable from roots)
    for (final selectionId in selections) {
      if (!visited.contains(selectionId)) {
        // This selection is part of an orphaned cycle
        throw EvaluateFailure(
          invariant: EvaluateFailure.invariantCycleDetected,
          message: 'Orphaned cycle detected: $selectionId is not reachable from any root',
        );
      }
    }
  }

  /// Builds count tables for O(1) lookup during constraint evaluation.
  _CountTables _buildCountTables(
    SelectionSnapshot snapshot,
    List<String> selections,
  ) {
    // Count tables: Map<boundarySelectionId, Map<entryId, count>>
    final selfCounts = <String, Map<String, int>>{};
    final parentCounts = <String, Map<String, int>>{};
    final forceCounts = <String, Map<String, int>>{};
    final rosterCounts = <String, int>{};

    for (final selectionId in selections) {
      final entryId = snapshot.entryIdFor(selectionId);
      final count = snapshot.countFor(selectionId);
      final parentId = snapshot.parentOf(selectionId);

      // Self boundary
      selfCounts[selectionId] = {entryId: count};

      // Parent boundary
      if (parentId != null) {
        parentCounts.putIfAbsent(parentId, () => {});
        parentCounts[parentId]![entryId] =
            (parentCounts[parentId]![entryId] ?? 0) + count;
      }

      // Force boundary
      final forceRootId = _findForceRoot(snapshot, selectionId);
      if (forceRootId != null) {
        forceCounts.putIfAbsent(forceRootId, () => {});
        forceCounts[forceRootId]![entryId] =
            (forceCounts[forceRootId]![entryId] ?? 0) + count;
      }

      // Roster boundary
      rosterCounts[entryId] = (rosterCounts[entryId] ?? 0) + count;
    }

    return _CountTables(
      selfCounts: selfCounts,
      parentCounts: parentCounts,
      forceCounts: forceCounts,
      rosterCounts: rosterCounts,
    );
  }

  /// Finds the force root for a selection, or null if none exists.
  ///
  /// Note: Cycle protection is included even though _validateInvariants
  /// should have already checked for cycles. This is a defensive measure.
  String? _findForceRoot(SelectionSnapshot snapshot, String selectionId) {
    var current = selectionId;
    final visited = <String>{};
    while (true) {
      if (visited.contains(current)) {
        // Cycle detected - should not happen if validation passed
        return null;
      }
      visited.add(current);

      if (snapshot.isForceRoot(current)) {
        return current;
      }
      final parent = snapshot.parentOf(current);
      if (parent == null) break;
      current = parent;
    }
    return null;
  }

  /// Evaluates a single constraint.
  ConstraintEvaluation _evaluateConstraint({
    required BoundConstraint constraint,
    required BoundEntry entry,
    required String selectionId,
    required SelectionSnapshot snapshot,
    required _CountTables countTables,
    required List<EvaluationWarning> warnings,
  }) {
    final sourceRef = EvaluationSourceRef(
      sourceFileId: constraint.sourceFileId,
      entryId: entry.id,
      constraintId: constraint.id,
      sourceNode: constraint.sourceNode,
    );

    // Check for unknown constraint type
    if (!_knownTypes.contains(constraint.type)) {
      warnings.add(EvaluationWarning(
        code: EvaluationWarning.codeUnknownConstraintType,
        message: 'Unknown constraint type: ${constraint.type}',
        sourceRef: sourceRef,
      ));
      return ConstraintEvaluation(
        constraintId: constraint.id,
        outcome: ConstraintEvaluationOutcome.error,
        scope: EvaluationScope(scopeType: constraint.scope),
        boundarySelectionId: selectionId,
        sourceRef: sourceRef,
        actualValue: 0,
        requiredValue: constraint.value,
        constraintType: constraint.type,
      );
    }

    // Check for unknown constraint field
    if (!_knownFields.contains(constraint.field)) {
      warnings.add(EvaluationWarning(
        code: EvaluationWarning.codeUnknownConstraintField,
        message: 'Unknown constraint field: ${constraint.field}',
        sourceRef: sourceRef,
      ));
      return ConstraintEvaluation(
        constraintId: constraint.id,
        outcome: ConstraintEvaluationOutcome.error,
        scope: EvaluationScope(scopeType: constraint.scope),
        boundarySelectionId: selectionId,
        sourceRef: sourceRef,
        actualValue: 0,
        requiredValue: constraint.value,
        constraintType: constraint.type,
      );
    }

    // Check for unknown constraint scope
    if (!_knownScopes.contains(constraint.scope)) {
      warnings.add(EvaluationWarning(
        code: EvaluationWarning.codeUnknownConstraintScope,
        message: 'Unknown constraint scope: ${constraint.scope}',
        sourceRef: sourceRef,
      ));
      return ConstraintEvaluation(
        constraintId: constraint.id,
        outcome: ConstraintEvaluationOutcome.error,
        scope: EvaluationScope(scopeType: constraint.scope),
        boundarySelectionId: selectionId,
        sourceRef: sourceRef,
        actualValue: 0,
        requiredValue: constraint.value,
        constraintType: constraint.type,
      );
    }

    // Determine boundary and get actual value
    final (boundaryId, actualValue, scope, forceWarning) = _getActualValue(
      constraint: constraint,
      entry: entry,
      selectionId: selectionId,
      snapshot: snapshot,
      countTables: countTables,
    );

    if (forceWarning != null) {
      warnings.add(forceWarning);
      return ConstraintEvaluation(
        constraintId: constraint.id,
        outcome: ConstraintEvaluationOutcome.notApplicable,
        scope: scope,
        boundarySelectionId: boundaryId,
        sourceRef: sourceRef,
        actualValue: 0,
        requiredValue: constraint.value,
        constraintType: constraint.type,
      );
    }

    // Evaluate constraint
    final satisfied = _evaluateCondition(
      type: constraint.type,
      actualValue: actualValue,
      requiredValue: constraint.value,
    );

    final outcome = satisfied
        ? ConstraintEvaluationOutcome.satisfied
        : ConstraintEvaluationOutcome.violated;

    ConstraintViolation? violation;
    if (!satisfied) {
      violation = ConstraintViolation(
        constraintType: constraint.type,
        actualValue: actualValue,
        requiredValue: constraint.value,
        affectedEntryId: entry.id,
        boundarySelectionId: boundaryId,
        scope: scope,
        message: _buildViolationMessage(
          type: constraint.type,
          actualValue: actualValue,
          requiredValue: constraint.value,
          entryName: entry.name,
        ),
      );
    }

    return ConstraintEvaluation(
      constraintId: constraint.id,
      outcome: outcome,
      violation: violation,
      scope: scope,
      boundarySelectionId: boundaryId,
      sourceRef: sourceRef,
      actualValue: actualValue,
      requiredValue: constraint.value,
      constraintType: constraint.type,
    );
  }

  /// Gets the actual value for a constraint based on scope.
  (String, int, EvaluationScope, EvaluationWarning?) _getActualValue({
    required BoundConstraint constraint,
    required BoundEntry entry,
    required String selectionId,
    required SelectionSnapshot snapshot,
    required _CountTables countTables,
  }) {
    final entryId = entry.id;

    switch (constraint.scope) {
      case 'self':
        final counts = countTables.selfCounts[selectionId] ?? {};
        final actualValue = counts[entryId] ?? 0;
        return (
          selectionId,
          actualValue,
          EvaluationScope(scopeType: 'self', boundarySelectionId: selectionId),
          null,
        );

      case 'parent':
        final parentId = snapshot.parentOf(selectionId);
        if (parentId == null) {
          // No parent, count is 0
          return (
            selectionId,
            0,
            EvaluationScope(scopeType: 'parent', boundarySelectionId: null),
            null,
          );
        }
        final counts = countTables.parentCounts[parentId] ?? {};
        final actualValue = counts[entryId] ?? 0;
        return (
          parentId,
          actualValue,
          EvaluationScope(scopeType: 'parent', boundarySelectionId: parentId),
          null,
        );

      case 'force':
        final forceRootId = _findForceRoot(snapshot, selectionId);
        if (forceRootId == null) {
          // Undefined force boundary
          return (
            selectionId,
            0,
            EvaluationScope(scopeType: 'force', boundarySelectionId: null),
            EvaluationWarning(
              code: EvaluationWarning.codeUndefinedForceBoundary,
              message: 'Force scope requested but no force root found for selection $selectionId',
              sourceRef: EvaluationSourceRef(
                sourceFileId: constraint.sourceFileId,
                entryId: entry.id,
                constraintId: constraint.id,
              ),
            ),
          );
        }
        final counts = countTables.forceCounts[forceRootId] ?? {};
        final actualValue = counts[entryId] ?? 0;
        return (
          forceRootId,
          actualValue,
          EvaluationScope(scopeType: 'force', boundarySelectionId: forceRootId),
          null,
        );

      case 'roster':
        final actualValue = countTables.rosterCounts[entryId] ?? 0;
        return (
          selectionId,
          actualValue,
          const EvaluationScope(scopeType: 'roster', boundarySelectionId: null),
          null,
        );

      default:
        // Should not reach here due to earlier validation
        return (
          selectionId,
          0,
          EvaluationScope(scopeType: constraint.scope),
          null,
        );
    }
  }

  /// Evaluates the constraint condition.
  bool _evaluateCondition({
    required String type,
    required int actualValue,
    required int requiredValue,
  }) {
    switch (type) {
      case 'min':
        return actualValue >= requiredValue;
      case 'max':
        return actualValue <= requiredValue;
      default:
        return false;
    }
  }

  /// Builds a human-readable violation message.
  String _buildViolationMessage({
    required String type,
    required int actualValue,
    required int requiredValue,
    required String entryName,
  }) {
    switch (type) {
      case 'min':
        return '$entryName: requires at least $requiredValue, but has $actualValue';
      case 'max':
        return '$entryName: allows at most $requiredValue, but has $actualValue';
      default:
        return '$entryName: constraint $type violated (actual: $actualValue, required: $requiredValue)';
    }
  }

  /// Builds the evaluation summary from all evaluations.
  EvaluationSummary _buildSummary(List<ConstraintEvaluation> evaluations) {
    var satisfiedCount = 0;
    var violatedCount = 0;
    var notApplicableCount = 0;
    var errorCount = 0;

    for (final evaluation in evaluations) {
      switch (evaluation.outcome) {
        case ConstraintEvaluationOutcome.satisfied:
          satisfiedCount++;
          break;
        case ConstraintEvaluationOutcome.violated:
          violatedCount++;
          break;
        case ConstraintEvaluationOutcome.notApplicable:
          notApplicableCount++;
          break;
        case ConstraintEvaluationOutcome.error:
          errorCount++;
          break;
      }
    }

    return EvaluationSummary(
      totalEvaluations: evaluations.length,
      satisfiedCount: satisfiedCount,
      violatedCount: violatedCount,
      notApplicableCount: notApplicableCount,
      errorCount: errorCount,
    );
  }
}

/// Internal class for count tables.
class _CountTables {
  /// Self boundary counts: Map<selectionId, Map<entryId, count>>
  final Map<String, Map<String, int>> selfCounts;

  /// Parent boundary counts: Map<parentSelectionId, Map<entryId, count>>
  final Map<String, Map<String, int>> parentCounts;

  /// Force boundary counts: Map<forceRootSelectionId, Map<entryId, count>>
  final Map<String, Map<String, int>> forceCounts;

  /// Roster boundary counts: Map<entryId, count>
  final Map<String, int> rosterCounts;

  _CountTables({
    required this.selfCounts,
    required this.parentCounts,
    required this.forceCounts,
    required this.rosterCounts,
  });
}

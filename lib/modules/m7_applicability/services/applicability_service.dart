import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m6_evaluate/m6_evaluate.dart';

import '../models/applicability_diagnostic.dart';
import '../models/applicability_result.dart';
import '../models/condition_evaluation.dart';
import '../models/condition_group_evaluation.dart';

/// Service that evaluates conditions against roster state.
///
/// Provides:
/// - [evaluate]: single-source evaluation
/// - [evaluateMany]: bulk evaluation preserving input order
///
/// Determinism guarantee: Same inputs → identical [ApplicabilityResult].
/// Condition evaluation order matches XML traversal.
///
/// Part of M7 Applicability (Phase 5).
class ApplicabilityService {
  /// Supported condition types.
  static const _supportedConditionTypes = {
    'atleast',
    'atmost',
    'greaterthan',
    'lessthan',
    'equalto',
    'notequalto',
    'instanceof',
    'notinstanceof',
  };

  /// Supported scope keywords.
  static const _supportedScopeKeywords = {
    'self',
    'parent',
    'ancestor',
    'roster',
    'force',
  };

  /// Supported field keywords.
  static const _supportedFieldKeywords = {
    'selections',
    'forces',
  };

  /// Accumulated diagnostics during evaluation.
  final List<ApplicabilityDiagnostic> _diagnostics = [];

  /// Cached cost type IDs from game system (lazy-built).
  Set<String>? _knownCostTypeIds;

  /// Returns diagnostics from the last evaluation.
  List<ApplicabilityDiagnostic> get diagnostics =>
      List.unmodifiable(_diagnostics);

  /// Builds set of known cost type IDs from game system.
  Set<String> _getKnownCostTypeIds(BoundPackBundle boundBundle) {
    if (_knownCostTypeIds != null) return _knownCostTypeIds!;

    final costTypeIds = <String>{};
    final gameSystem = boundBundle.linkedBundle.wrappedBundle.gameSystem;

    // Find costTypes container in game system root children
    for (final childRef in gameSystem.root.children) {
      final childNode = gameSystem.nodeAt(childRef);
      if (childNode.tagName == 'costTypes') {
        // Iterate costType children
        for (final costTypeRef in childNode.children) {
          final costTypeNode = gameSystem.nodeAt(costTypeRef);
          if (costTypeNode.tagName == 'costType') {
            final id = costTypeNode.attributes['id'];
            if (id != null && id.isNotEmpty) {
              costTypeIds.add(id);
            }
          }
        }
        break;
      }
    }

    _knownCostTypeIds = costTypeIds;
    return costTypeIds;
  }

  /// Evaluates conditions for a single source node.
  ///
  /// Parameters:
  /// - [conditionSource]: Node containing conditions (modifier, constraint, etc.)
  /// - [sourceFileId]: Provenance for index-ready output
  /// - [sourceNode]: Provenance for index-ready output
  /// - [snapshot]: Current roster state
  /// - [boundBundle]: For entry/category/costType lookups
  /// - [contextSelectionId]: "self" scope resolves relative to this selection
  ApplicabilityResult evaluate({
    required WrappedNode conditionSource,
    required String sourceFileId,
    required NodeRef sourceNode,
    required SelectionSnapshot snapshot,
    required BoundPackBundle boundBundle,
    required String contextSelectionId,
  }) {
    _diagnostics.clear();

    // Get the WrappedFile for traversing children
    final wrappedFile = _findWrappedFile(boundBundle, sourceFileId);
    if (wrappedFile == null) {
      return ApplicabilityResult.applies(
        sourceFileId: sourceFileId,
        sourceNode: sourceNode,
        diagnostics: List.unmodifiable(_diagnostics),
      );
    }

    // Find conditions or conditionGroups children
    final conditionResults = <ConditionEvaluation>[];
    final topLevelGroups = <ConditionGroupEvaluation>[];

    for (final childRef in conditionSource.children) {
      final childNode = wrappedFile.nodeAt(childRef);

      if (childNode.tagName == 'conditions') {
        // Process flat conditions container
        for (final condRef in childNode.children) {
          final condNode = wrappedFile.nodeAt(condRef);
          if (condNode.tagName == 'condition') {
            final eval = _evaluateCondition(
              condNode: condNode,
              wrappedFile: wrappedFile,
              snapshot: snapshot,
              boundBundle: boundBundle,
              contextSelectionId: contextSelectionId,
            );
            conditionResults.add(eval);
          }
        }
      } else if (childNode.tagName == 'conditionGroups') {
        // Fix 4: Collect ALL condition groups (not just last)
        for (final groupRef in childNode.children) {
          final groupNode = wrappedFile.nodeAt(groupRef);
          if (groupNode.tagName == 'conditionGroup') {
            final groupEval = _evaluateConditionGroup(
              groupNode: groupNode,
              wrappedFile: wrappedFile,
              snapshot: snapshot,
              boundBundle: boundBundle,
              contextSelectionId: contextSelectionId,
              conditionResults: conditionResults,
            );
            topLevelGroups.add(groupEval);
          }
        }
      }
    }

    // Fix 4: Combine multiple top-level groups as implicit AND
    ConditionGroupEvaluation? groupResult;
    if (topLevelGroups.length == 1) {
      groupResult = topLevelGroups.first;
    } else if (topLevelGroups.length > 1) {
      // Multiple groups → combine as implicit AND
      final combinedState = ConditionGroupEvaluation.computeGroupState(
        groupType: 'and',
        conditions: const [],
        nestedGroups: topLevelGroups,
      );
      groupResult = ConditionGroupEvaluation(
        groupType: 'and',
        conditions: const [],
        nestedGroups: topLevelGroups,
        state: combinedState,
      );
    }

    // No conditions found → applies
    if (conditionResults.isEmpty && groupResult == null) {
      return ApplicabilityResult.applies(
        sourceFileId: sourceFileId,
        sourceNode: sourceNode,
        diagnostics: List.unmodifiable(_diagnostics),
      );
    }

    // Compute final state
    final ApplicabilityState finalState;
    String? reason;

    if (groupResult != null) {
      finalState = groupResult.state;
    } else {
      // If no group, treat all conditions as implicit AND
      finalState = ConditionGroupEvaluation.computeGroupState(
        groupType: 'and',
        conditions: conditionResults,
        nestedGroups: const [],
      );
    }

    // Build reason text
    if (finalState == ApplicabilityState.skipped) {
      reason = _buildSkippedReason(conditionResults);
    } else if (finalState == ApplicabilityState.unknown) {
      reason = _buildUnknownReason(conditionResults);
    }

    return ApplicabilityResult(
      state: finalState,
      reason: reason,
      conditionResults: conditionResults,
      groupResult: groupResult,
      sourceFileId: sourceFileId,
      sourceNode: sourceNode,
      diagnostics: List.unmodifiable(_diagnostics),
    );
  }

  /// Evaluates conditions for multiple source nodes.
  ///
  /// Results preserve the order of [sources] input.
  List<ApplicabilityResult> evaluateMany({
    required List<({WrappedNode conditionSource, String sourceFileId, NodeRef sourceNode})>
        sources,
    required SelectionSnapshot snapshot,
    required BoundPackBundle boundBundle,
    required String contextSelectionId,
  }) {
    final results = <ApplicabilityResult>[];
    for (final source in sources) {
      results.add(evaluate(
        conditionSource: source.conditionSource,
        sourceFileId: source.sourceFileId,
        sourceNode: source.sourceNode,
        snapshot: snapshot,
        boundBundle: boundBundle,
        contextSelectionId: contextSelectionId,
      ));
    }
    return results;
  }

  /// Evaluates a single condition element.
  ConditionEvaluation _evaluateCondition({
    required WrappedNode condNode,
    required WrappedFile wrappedFile,
    required SelectionSnapshot snapshot,
    required BoundPackBundle boundBundle,
    required String contextSelectionId,
  }) {
    final attrs = condNode.attributes;
    final conditionType = attrs['type'] ?? '';
    final field = attrs['field'] ?? '';
    final scope = attrs['scope'] ?? '';
    final childId = attrs['childId'];
    final valueStr = attrs['value'] ?? '0';
    final requiredValue = int.tryParse(valueStr) ?? 0;
    final includeChildSelections =
        attrs['includeChildSelections']?.toLowerCase() == 'true';
    final includeChildForces =
        attrs['includeChildForces']?.toLowerCase() == 'true';

    // Validate condition type
    final normalizedType = conditionType.toLowerCase();
    if (!_supportedConditionTypes.contains(normalizedType)) {
      _diagnostics.add(ApplicabilityDiagnostic(
        code: ApplicabilityDiagnosticCode.unknownConditionType,
        message: 'Unknown condition type: $conditionType',
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
        targetId: conditionType,
      ));
      return ConditionEvaluation(
        conditionType: conditionType,
        field: field,
        scope: scope,
        childId: childId,
        requiredValue: requiredValue,
        actualValue: null,
        state: ApplicabilityState.unknown,
        includeChildSelections: includeChildSelections,
        includeChildForces: includeChildForces,
        reasonCode: 'UNKNOWN_CONDITION_TYPE',
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
      );
    }

    // Resolve field
    final fieldResolution = _resolveField(field, boundBundle, wrappedFile, condNode);
    if (fieldResolution.isUnknown) {
      return ConditionEvaluation(
        conditionType: conditionType,
        field: field,
        scope: scope,
        childId: childId,
        requiredValue: requiredValue,
        actualValue: null,
        state: ApplicabilityState.unknown,
        includeChildSelections: includeChildSelections,
        includeChildForces: includeChildForces,
        reasonCode: fieldResolution.reasonCode,
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
      );
    }

    // Resolve scope
    final scopeResolution = _resolveScope(scope, boundBundle, wrappedFile, condNode);
    if (scopeResolution.isUnknown) {
      return ConditionEvaluation(
        conditionType: conditionType,
        field: field,
        scope: scope,
        childId: childId,
        requiredValue: requiredValue,
        actualValue: null,
        state: ApplicabilityState.unknown,
        includeChildSelections: includeChildSelections,
        includeChildForces: includeChildForces,
        reasonCode: scopeResolution.reasonCode,
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
      );
    }

    // Validate childId if present
    if (childId != null && childId.isNotEmpty) {
      final entry = boundBundle.entryById(childId);
      final category = boundBundle.categoryById(childId);
      if (entry == null && category == null) {
        _diagnostics.add(ApplicabilityDiagnostic(
          code: ApplicabilityDiagnosticCode.unresolvedChildId,
          message: 'Unresolved childId: $childId',
          sourceFileId: wrappedFile.fileId,
          sourceNode: condNode.ref,
          targetId: childId,
        ));
        return ConditionEvaluation(
          conditionType: conditionType,
          field: field,
          scope: scope,
          childId: childId,
          requiredValue: requiredValue,
          actualValue: null,
          state: ApplicabilityState.unknown,
          includeChildSelections: includeChildSelections,
          includeChildForces: includeChildForces,
          reasonCode: 'UNRESOLVED_CHILD_ID',
          sourceFileId: wrappedFile.fileId,
          sourceNode: condNode.ref,
        );
      }
    }

    // Fix 2: includeChildForces requires force-subtree semantics not yet supported
    if (field.toLowerCase() == 'forces' && includeChildForces) {
      _diagnostics.add(ApplicabilityDiagnostic(
        code: ApplicabilityDiagnosticCode.snapshotDataGapChildSemantics,
        message: 'includeChildForces=true requires force-subtree semantics not yet supported',
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
      ));
      return ConditionEvaluation(
        conditionType: conditionType,
        field: field,
        scope: scope,
        childId: childId,
        requiredValue: requiredValue,
        actualValue: null,
        state: ApplicabilityState.unknown,
        includeChildSelections: includeChildSelections,
        includeChildForces: includeChildForces,
        reasonCode: 'SNAPSHOT_DATA_GAP_CHILD_SEMANTICS',
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
      );
    }

    // Compute actual value
    final actualValue = _computeActualValue(
      field: field,
      scope: scope,
      childId: childId,
      snapshot: snapshot,
      contextSelectionId: contextSelectionId,
      includeChildSelections: includeChildSelections,
    );

    // Evaluate condition
    final satisfied = _evaluateComparison(
      conditionType: normalizedType,
      actualValue: actualValue,
      requiredValue: requiredValue,
    );

    return ConditionEvaluation(
      conditionType: conditionType,
      field: field,
      scope: scope,
      childId: childId,
      requiredValue: requiredValue,
      actualValue: actualValue,
      state: satisfied ? ApplicabilityState.applies : ApplicabilityState.skipped,
      includeChildSelections: includeChildSelections,
      includeChildForces: includeChildForces,
      reasonCode: satisfied ? null : 'CONDITION_NOT_MET',
      sourceFileId: wrappedFile.fileId,
      sourceNode: condNode.ref,
    );
  }

  /// Evaluates a condition group.
  ConditionGroupEvaluation _evaluateConditionGroup({
    required WrappedNode groupNode,
    required WrappedFile wrappedFile,
    required SelectionSnapshot snapshot,
    required BoundPackBundle boundBundle,
    required String contextSelectionId,
    required List<ConditionEvaluation> conditionResults,
  }) {
    final groupType = groupNode.attributes['type'] ?? 'and';
    final conditions = <ConditionEvaluation>[];
    final nestedGroups = <ConditionGroupEvaluation>[];

    for (final childRef in groupNode.children) {
      final childNode = wrappedFile.nodeAt(childRef);
      if (childNode.tagName == 'condition') {
        final eval = _evaluateCondition(
          condNode: childNode,
          wrappedFile: wrappedFile,
          snapshot: snapshot,
          boundBundle: boundBundle,
          contextSelectionId: contextSelectionId,
        );
        conditions.add(eval);
        conditionResults.add(eval);
      } else if (childNode.tagName == 'conditionGroup') {
        final nested = _evaluateConditionGroup(
          groupNode: childNode,
          wrappedFile: wrappedFile,
          snapshot: snapshot,
          boundBundle: boundBundle,
          contextSelectionId: contextSelectionId,
          conditionResults: conditionResults,
        );
        nestedGroups.add(nested);
      }
    }

    final state = ConditionGroupEvaluation.computeGroupState(
      groupType: groupType,
      conditions: conditions,
      nestedGroups: nestedGroups,
    );

    return ConditionGroupEvaluation(
      groupType: groupType,
      conditions: conditions,
      nestedGroups: nestedGroups,
      state: state,
    );
  }

  /// Resolves field to keyword or ID.
  _FieldResolution _resolveField(
    String field,
    BoundPackBundle boundBundle,
    WrappedFile wrappedFile,
    WrappedNode condNode,
  ) {
    final normalizedField = field.toLowerCase();

    // Check keyword
    if (_supportedFieldKeywords.contains(normalizedField)) {
      return _FieldResolution(isUnknown: false);
    }

    // Rev-2 compliant: Check if field is a known cost type ID in the bundle
    final knownCostTypes = _getKnownCostTypeIds(boundBundle);
    if (knownCostTypes.contains(field)) {
      // Valid cost type ID, but snapshot doesn't support cost evaluation yet
      _diagnostics.add(ApplicabilityDiagnostic(
        code: ApplicabilityDiagnosticCode.snapshotDataGapCosts,
        message: 'Cost field "$field" requested but snapshot lacks cost data',
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
        targetId: field,
      ));
      return _FieldResolution(
        isUnknown: true,
        reasonCode: 'SNAPSHOT_DATA_GAP_COSTS',
      );
    }

    // Not a keyword and not a known cost type → unresolved field ID
    _diagnostics.add(ApplicabilityDiagnostic(
      code: ApplicabilityDiagnosticCode.unresolvedConditionFieldId,
      message: 'Unresolved field ID: $field (not a keyword or known cost type)',
      sourceFileId: wrappedFile.fileId,
      sourceNode: condNode.ref,
      targetId: field,
    ));
    return _FieldResolution(
      isUnknown: true,
      reasonCode: 'UNRESOLVED_CONDITION_FIELD_ID',
    );
  }

  /// Resolves scope to keyword or ID.
  _ScopeResolution _resolveScope(
    String scope,
    BoundPackBundle boundBundle,
    WrappedFile wrappedFile,
    WrappedNode condNode,
  ) {
    final normalizedScope = scope.toLowerCase();

    // Check keyword
    if (_supportedScopeKeywords.contains(normalizedScope)) {
      return _ScopeResolution(isUnknown: false);
    }

    // Check if it's a category ID
    final category = boundBundle.categoryById(scope);
    if (category != null) {
      // Category-id scope - currently not supported in snapshot
      _diagnostics.add(ApplicabilityDiagnostic(
        code: ApplicabilityDiagnosticCode.snapshotDataGapCategories,
        message: 'Category-id scope "$scope" requested but snapshot lacks category membership data',
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
        targetId: scope,
      ));
      return _ScopeResolution(
        isUnknown: true,
        reasonCode: 'SNAPSHOT_DATA_GAP_CATEGORIES',
      );
    }

    // Check if it's an entry ID
    final entry = boundBundle.entryById(scope);
    if (entry != null) {
      // Entry-id scope - deferred semantics
      _diagnostics.add(ApplicabilityDiagnostic(
        code: ApplicabilityDiagnosticCode.unresolvedConditionScopeId,
        message: 'Entry-id scope "$scope" has deferred semantics',
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
        targetId: scope,
      ));
      return _ScopeResolution(
        isUnknown: true,
        reasonCode: 'UNRESOLVED_CONDITION_SCOPE_ID',
      );
    }

    // Fix 6: Differentiate ID-like unknown scopes from unknown keywords
    if (_looksLikeId(scope)) {
      // Looks like an ID (GUID-ish) but not found in bundle
      _diagnostics.add(ApplicabilityDiagnostic(
        code: ApplicabilityDiagnosticCode.unresolvedConditionScopeId,
        message: 'Unresolved scope ID: $scope (not found in bundle)',
        sourceFileId: wrappedFile.fileId,
        sourceNode: condNode.ref,
        targetId: scope,
      ));
      return _ScopeResolution(
        isUnknown: true,
        reasonCode: 'UNRESOLVED_CONDITION_SCOPE_ID',
      );
    }

    // Truly unknown scope keyword
    _diagnostics.add(ApplicabilityDiagnostic(
      code: ApplicabilityDiagnosticCode.unknownConditionScopeKeyword,
      message: 'Unknown scope keyword: $scope',
      sourceFileId: wrappedFile.fileId,
      sourceNode: condNode.ref,
      targetId: scope,
    ));
    return _ScopeResolution(
      isUnknown: true,
      reasonCode: 'UNKNOWN_CONDITION_SCOPE_KEYWORD',
    );
  }

  /// Detects if a string looks like an ID (GUID-like pattern).
  ///
  /// BSD IDs typically contain hyphens and hex characters.
  bool _looksLikeId(String value) {
    // Check for GUID-like patterns: contains hyphens and primarily hex chars
    if (!value.contains('-')) return false;
    // BSD IDs are typically like: "xxxx-xxxx-xxxx-xxxx"
    final parts = value.split('-');
    if (parts.length < 2) return false;
    // Check if parts look like hex segments
    final hexPattern = RegExp(r'^[0-9a-fA-F]+$');
    return parts.every((part) => part.isNotEmpty && hexPattern.hasMatch(part));
  }

  /// Computes the actual value for a condition.
  int _computeActualValue({
    required String field,
    required String scope,
    required String? childId,
    required SelectionSnapshot snapshot,
    required String contextSelectionId,
    required bool includeChildSelections,
  }) {
    final normalizedField = field.toLowerCase();
    final normalizedScope = scope.toLowerCase();

    if (normalizedField == 'selections') {
      return _countSelections(
        scope: normalizedScope,
        childId: childId,
        snapshot: snapshot,
        contextSelectionId: contextSelectionId,
        includeChildSelections: includeChildSelections,
      );
    } else if (normalizedField == 'forces') {
      return _countForces(
        scope: normalizedScope,
        childId: childId,
        snapshot: snapshot,
        contextSelectionId: contextSelectionId,
      );
    }

    // Unknown field - should have been caught earlier
    return 0;
  }

  /// Counts selections matching criteria.
  int _countSelections({
    required String scope,
    required String? childId,
    required SelectionSnapshot snapshot,
    required String contextSelectionId,
    required bool includeChildSelections,
  }) {
    var count = 0;
    final selectionsToCheck = _getSelectionsForScope(
      scope: scope,
      snapshot: snapshot,
      contextSelectionId: contextSelectionId,
      includeChildSelections: includeChildSelections,
    );

    for (final selectionId in selectionsToCheck) {
      if (childId == null || childId.isEmpty) {
        // Count all selections in scope
        count += snapshot.countFor(selectionId);
      } else {
        // Count only selections matching childId
        final entryId = snapshot.entryIdFor(selectionId);
        if (entryId == childId) {
          count += snapshot.countFor(selectionId);
        }
      }
    }

    return count;
  }

  /// Counts forces matching criteria.
  int _countForces({
    required String scope,
    required String? childId,
    required SelectionSnapshot snapshot,
    required String contextSelectionId,
  }) {
    var count = 0;

    if (scope == 'roster') {
      // Count all force roots
      for (final selectionId in snapshot.orderedSelections()) {
        if (snapshot.isForceRoot(selectionId)) {
          if (childId == null || childId.isEmpty) {
            count++;
          } else {
            final entryId = snapshot.entryIdFor(selectionId);
            if (entryId == childId) {
              count++;
            }
          }
        }
      }
    } else if (scope == 'force') {
      // Count within current force
      final forceRoot = _findForceRoot(snapshot, contextSelectionId);
      if (forceRoot != null && snapshot.isForceRoot(forceRoot)) {
        if (childId == null || childId.isEmpty) {
          count = 1;
        } else {
          final entryId = snapshot.entryIdFor(forceRoot);
          if (entryId == childId) {
            count = 1;
          }
        }
      }
    }

    return count;
  }

  /// Gets selections to check for a given scope.
  List<String> _getSelectionsForScope({
    required String scope,
    required SelectionSnapshot snapshot,
    required String contextSelectionId,
    required bool includeChildSelections,
  }) {
    switch (scope) {
      case 'self':
        if (includeChildSelections) {
          return _getSubtreeSelections(snapshot, contextSelectionId);
        }
        return [contextSelectionId];

      case 'parent':
        final parent = snapshot.parentOf(contextSelectionId);
        if (parent == null) return [];
        if (includeChildSelections) {
          return _getSubtreeSelections(snapshot, parent);
        }
        return [parent];

      case 'ancestor':
        final ancestors = <String>[];
        var current = snapshot.parentOf(contextSelectionId);
        while (current != null) {
          ancestors.add(current);
          if (includeChildSelections) {
            ancestors.addAll(snapshot.childrenOf(current));
          }
          current = snapshot.parentOf(current);
        }
        return ancestors;

      case 'roster':
        return snapshot.orderedSelections();

      case 'force':
        final forceRoot = _findForceRoot(snapshot, contextSelectionId);
        if (forceRoot == null) return [];
        return _getSubtreeSelections(snapshot, forceRoot);

      default:
        return [];
    }
  }

  /// Gets all selections in a subtree.
  List<String> _getSubtreeSelections(
      SelectionSnapshot snapshot, String rootId) {
    final result = <String>[rootId];
    final children = snapshot.childrenOf(rootId);
    for (final child in children) {
      result.addAll(_getSubtreeSelections(snapshot, child));
    }
    return result;
  }

  /// Finds the force root for a selection.
  String? _findForceRoot(SelectionSnapshot snapshot, String selectionId) {
    var current = selectionId;
    while (true) {
      if (snapshot.isForceRoot(current)) {
        return current;
      }
      final parent = snapshot.parentOf(current);
      if (parent == null) {
        return null;
      }
      current = parent;
    }
  }

  /// Evaluates a comparison.
  bool _evaluateComparison({
    required String conditionType,
    required int actualValue,
    required int requiredValue,
  }) {
    switch (conditionType) {
      case 'atleast':
        return actualValue >= requiredValue;
      case 'atmost':
        return actualValue <= requiredValue;
      case 'greaterthan':
        return actualValue > requiredValue;
      case 'lessthan':
        return actualValue < requiredValue;
      case 'equalto':
        return actualValue == requiredValue;
      case 'notequalto':
        return actualValue != requiredValue;
      case 'instanceof':
        // instanceOf: true if actualValue >= 1 (at least one instance)
        return actualValue >= 1;
      case 'notinstanceof':
        // notInstanceOf: true if actualValue == 0 (no instances)
        return actualValue == 0;
      default:
        return false;
    }
  }

  /// Finds the WrappedFile for a given fileId.
  WrappedFile? _findWrappedFile(BoundPackBundle boundBundle, String fileId) {
    final wrappedBundle = boundBundle.linkedBundle.wrappedBundle;
    if (wrappedBundle.gameSystem.fileId == fileId) {
      return wrappedBundle.gameSystem;
    }
    if (wrappedBundle.primaryCatalog.fileId == fileId) {
      return wrappedBundle.primaryCatalog;
    }
    for (final dep in wrappedBundle.dependencyCatalogs) {
      if (dep.fileId == fileId) {
        return dep;
      }
    }
    return null;
  }

  /// Builds reason text for skipped state.
  String _buildSkippedReason(List<ConditionEvaluation> conditions) {
    final skippedConditions =
        conditions.where((c) => c.state == ApplicabilityState.skipped).toList();
    if (skippedConditions.isEmpty) {
      return 'Conditions not met';
    }

    final first = skippedConditions.first;
    if (first.childId != null && first.childId!.isNotEmpty) {
      return 'Condition not met: ${first.conditionType} ${first.requiredValue} '
          '${first.field} of ${first.childId} in ${first.scope} (actual: ${first.actualValue})';
    }
    return 'Condition not met: ${first.conditionType} ${first.requiredValue} '
        '${first.field} in ${first.scope} (actual: ${first.actualValue})';
  }

  /// Builds reason text for unknown state.
  String _buildUnknownReason(List<ConditionEvaluation> conditions) {
    final unknownConditions =
        conditions.where((c) => c.state == ApplicabilityState.unknown).toList();
    if (unknownConditions.isEmpty) {
      return 'Cannot determine applicability';
    }

    final first = unknownConditions.first;
    return 'Cannot evaluate condition: ${first.reasonCode}';
  }
}

/// Internal field resolution result.
class _FieldResolution {
  final bool isUnknown;
  final String? reasonCode;

  const _FieldResolution({required this.isUnknown, this.reasonCode});
}

/// Internal scope resolution result.
class _ScopeResolution {
  final bool isUnknown;
  final String? reasonCode;

  const _ScopeResolution({required this.isUnknown, this.reasonCode});
}

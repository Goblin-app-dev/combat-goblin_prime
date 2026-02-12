import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';
import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m6_evaluate/m6_evaluate.dart';
import 'package:combat_goblin_prime/modules/m7_applicability/m7_applicability.dart';

import '../models/modifier_diagnostic.dart';
import '../models/modifier_failure.dart';
import '../models/modifier_operation.dart';
import '../models/modifier_result.dart';
import '../models/modifier_target_ref.dart';
import '../models/modifier_value.dart';

/// Service that applies modifiers to produce effective values.
///
/// Provides:
/// - [applyModifiers]: single-target application
/// - [applyModifiersMany]: bulk application preserving input order
///
/// Determinism guarantee: Same inputs → identical [ModifierResult].
/// Modifier application order matches XML traversal.
///
/// Part of M8 Modifiers (Phase 6).
class ModifierService {
  /// Supported modifier types.
  static const _supportedModifierTypes = {
    'set',
    'increment',
    'decrement',
    'append',
  };

  /// Supported scope keywords.
  static const _supportedScopeKeywords = {
    'self',
    'parent',
    'ancestor',
    'roster',
    'force',
  };

  /// Supported field kinds for metadata.
  static const _metadataFields = {
    'name',
    'hidden',
    'collective',
  };

  /// Accumulated diagnostics during evaluation.
  final List<ModifierDiagnostic> _diagnostics = [];

  /// Returns diagnostics from the last evaluation.
  List<ModifierDiagnostic> get diagnostics =>
      List.unmodifiable(_diagnostics);

  /// Applies modifiers for a single source node.
  ///
  /// Parameters:
  /// - [modifierSource]: Node containing modifiers
  /// - [sourceFileId]: Provenance for index-ready output
  /// - [sourceNode]: Provenance for index-ready output
  /// - [boundBundle]: For entry/profile/cost lookups
  /// - [snapshot]: Current roster state (for condition evaluation via M7)
  /// - [contextSelectionId]: Context for condition evaluation
  /// - [applicabilityService]: M7 service for condition evaluation
  ModifierResult applyModifiers({
    required WrappedNode modifierSource,
    required String sourceFileId,
    required NodeRef sourceNode,
    required BoundPackBundle boundBundle,
    required SelectionSnapshot snapshot,
    required String contextSelectionId,
    required ApplicabilityService applicabilityService,
  }) {
    _diagnostics.clear();

    // Get the WrappedFile for traversing children
    final wrappedFile = _findWrappedFile(boundBundle, sourceFileId);
    if (wrappedFile == null) {
      // Cannot find file - return empty result
      final emptyTarget = ModifierTargetRef(
        targetId: '',
        field: '',
        fieldKind: FieldKind.metadata,
        sourceFileId: sourceFileId,
        sourceNode: sourceNode,
      );
      return ModifierResult.unchanged(
        target: emptyTarget,
        sourceFileId: sourceFileId,
        sourceNode: sourceNode,
        diagnostics: List.unmodifiable(_diagnostics),
      );
    }

    // Find modifiers children
    final modifierNodes = <WrappedNode>[];
    for (final childRef in modifierSource.children) {
      final childNode = wrappedFile.nodeAt(childRef);
      if (childNode.tagName == 'modifiers') {
        // Process modifiers container
        for (final modRef in childNode.children) {
          final modNode = wrappedFile.nodeAt(modRef);
          if (modNode.tagName == 'modifier') {
            modifierNodes.add(modNode);
          }
        }
      } else if (childNode.tagName == 'modifier') {
        // Direct modifier child
        modifierNodes.add(childNode);
      }
    }

    // No modifiers found - return unchanged
    if (modifierNodes.isEmpty) {
      final emptyTarget = ModifierTargetRef(
        targetId: '',
        field: '',
        fieldKind: FieldKind.metadata,
        sourceFileId: sourceFileId,
        sourceNode: sourceNode,
      );
      return ModifierResult.unchanged(
        target: emptyTarget,
        sourceFileId: sourceFileId,
        sourceNode: sourceNode,
        diagnostics: List.unmodifiable(_diagnostics),
      );
    }

    // Parse and evaluate each modifier
    final appliedOperations = <ModifierOperation>[];
    final skippedOperations = <ModifierOperation>[];
    ModifierValue? effectiveValue;
    ModifierTargetRef? resultTarget;

    for (final modNode in modifierNodes) {
      final operation = _parseModifier(
        modNode: modNode,
        wrappedFile: wrappedFile,
        boundBundle: boundBundle,
        snapshot: snapshot,
        contextSelectionId: contextSelectionId,
        applicabilityService: applicabilityService,
      );

      if (operation == null) {
        // Parsing failed - diagnostic already added
        continue;
      }

      // Use first target as result target
      resultTarget ??= operation.target;

      if (operation.isApplicable) {
        // Apply the operation
        effectiveValue = _applyOperation(
          operation: operation,
          currentValue: effectiveValue,
        );
        appliedOperations.add(operation);
      } else {
        skippedOperations.add(operation);
      }
    }

    // If no target found, create empty target
    resultTarget ??= ModifierTargetRef(
      targetId: '',
      field: '',
      fieldKind: FieldKind.metadata,
      sourceFileId: sourceFileId,
      sourceNode: sourceNode,
    );

    return ModifierResult(
      target: resultTarget,
      baseValue: null, // Base value would come from bound data
      effectiveValue: effectiveValue,
      appliedOperations: appliedOperations,
      skippedOperations: skippedOperations,
      diagnostics: List.unmodifiable(_diagnostics),
      sourceFileId: sourceFileId,
      sourceNode: sourceNode,
    );
  }

  /// Applies modifiers for multiple source nodes.
  ///
  /// Results preserve the order of [sources] input.
  List<ModifierResult> applyModifiersMany({
    required List<({WrappedNode modifierSource, String sourceFileId, NodeRef sourceNode})>
        sources,
    required BoundPackBundle boundBundle,
    required SelectionSnapshot snapshot,
    required String contextSelectionId,
    required ApplicabilityService applicabilityService,
  }) {
    final results = <ModifierResult>[];
    for (final source in sources) {
      results.add(applyModifiers(
        modifierSource: source.modifierSource,
        sourceFileId: source.sourceFileId,
        sourceNode: source.sourceNode,
        boundBundle: boundBundle,
        snapshot: snapshot,
        contextSelectionId: contextSelectionId,
        applicabilityService: applicabilityService,
      ));
    }
    return results;
  }

  /// Parses a single modifier element into an operation.
  ModifierOperation? _parseModifier({
    required WrappedNode modNode,
    required WrappedFile wrappedFile,
    required BoundPackBundle boundBundle,
    required SelectionSnapshot snapshot,
    required String contextSelectionId,
    required ApplicabilityService applicabilityService,
  }) {
    final attrs = modNode.attributes;
    final modifierType = attrs['type'] ?? '';
    final field = attrs['field'] ?? '';
    final valueStr = attrs['value'] ?? '';
    final scope = attrs['scope'];

    // Validate modifier type
    final normalizedType = modifierType.toLowerCase();
    if (!_supportedModifierTypes.contains(normalizedType)) {
      _diagnostics.add(ModifierDiagnostic(
        code: ModifierDiagnosticCode.unknownModifierType,
        message: 'Unknown modifier type: $modifierType',
        sourceFileId: wrappedFile.fileId,
        sourceNode: modNode.ref,
        targetId: modifierType,
      ));
      return null;
    }

    // Resolve field kind
    final fieldKind = _resolveFieldKind(field, wrappedFile, modNode);
    if (fieldKind == null) {
      // Diagnostic already added
      return null;
    }

    // Validate scope if present
    if (scope != null && scope.isNotEmpty) {
      final scopeValid = _validateScope(scope, wrappedFile, modNode, fieldKind);
      if (!scopeValid) {
        // Diagnostic already added
        return null;
      }
    }

    // Parse value
    final value = _parseValue(valueStr, normalizedType);

    // Resolve target
    // For modifiers, the target is typically the parent or a referenced entry
    final targetId = _resolveTargetId(modNode, wrappedFile, boundBundle);
    if (targetId == null) {
      _diagnostics.add(ModifierDiagnostic(
        code: ModifierDiagnosticCode.unresolvedModifierTarget,
        message: 'Cannot resolve modifier target',
        sourceFileId: wrappedFile.fileId,
        sourceNode: modNode.ref,
      ));
      return null;
    }

    final target = ModifierTargetRef(
      targetId: targetId,
      field: field,
      fieldKind: fieldKind,
      scope: scope,
      sourceFileId: wrappedFile.fileId,
      sourceNode: modNode.ref,
    );

    // Check applicability via M7
    final applicability = applicabilityService.evaluate(
      conditionSource: modNode,
      sourceFileId: wrappedFile.fileId,
      sourceNode: modNode.ref,
      snapshot: snapshot,
      boundBundle: boundBundle,
      contextSelectionId: contextSelectionId,
    );

    final isApplicable = applicability.state == ApplicabilityState.applies;
    final reasonSkipped = isApplicable ? null : applicability.reason;

    return ModifierOperation(
      operationType: normalizedType,
      target: target,
      value: value,
      isApplicable: isApplicable,
      reasonSkipped: reasonSkipped,
      sourceFileId: wrappedFile.fileId,
      sourceNode: modNode.ref,
    );
  }

  /// Resolves the field kind for a field name.
  FieldKind? _resolveFieldKind(
    String field,
    WrappedFile wrappedFile,
    WrappedNode modNode,
  ) {
    final normalizedField = field.toLowerCase();

    // Check metadata fields
    if (_metadataFields.contains(normalizedField)) {
      return FieldKind.metadata;
    }

    // Check for characteristic indicators
    if (field.contains('characteristic') ||
        field.startsWith('W') ||
        field.startsWith('BS') ||
        field.startsWith('WS') ||
        field.startsWith('S') ||
        field.startsWith('T') ||
        field.startsWith('A') ||
        field.startsWith('Ld') ||
        field.startsWith('Sv')) {
      return FieldKind.characteristic;
    }

    // Check for cost indicators (typically ends with "pts" or contains "cost")
    if (field.contains('cost') || field.endsWith('pts') || field.endsWith('pl')) {
      return FieldKind.cost;
    }

    // Check for constraint indicators
    if (field.contains('min') || field.contains('max')) {
      return FieldKind.constraint;
    }

    // Default to metadata for unknown fields
    _diagnostics.add(ModifierDiagnostic(
      code: ModifierDiagnosticCode.unknownModifierField,
      message: 'Unknown modifier field: $field (defaulting to metadata)',
      sourceFileId: wrappedFile.fileId,
      sourceNode: modNode.ref,
      targetId: field,
    ));
    return FieldKind.metadata;
  }

  /// Validates scope for a given field kind.
  bool _validateScope(
    String scope,
    WrappedFile wrappedFile,
    WrappedNode modNode,
    FieldKind fieldKind,
  ) {
    final normalizedScope = scope.toLowerCase();

    // Check if it's a supported keyword
    if (_supportedScopeKeywords.contains(normalizedScope)) {
      // Some scopes may not be supported for certain field kinds
      if (fieldKind == FieldKind.characteristic &&
          (normalizedScope == 'roster' || normalizedScope == 'ancestor')) {
        _diagnostics.add(ModifierDiagnostic(
          code: ModifierDiagnosticCode.unsupportedTargetScope,
          message: 'Scope "$scope" not supported for characteristic modifiers',
          sourceFileId: wrappedFile.fileId,
          sourceNode: modNode.ref,
          targetId: scope,
        ));
        return false;
      }
      return true;
    }

    // Unknown scope keyword
    _diagnostics.add(ModifierDiagnostic(
      code: ModifierDiagnosticCode.unknownModifierScope,
      message: 'Unknown modifier scope: $scope',
      sourceFileId: wrappedFile.fileId,
      sourceNode: modNode.ref,
      targetId: scope,
    ));
    return false;
  }

  /// Parses a value string into a ModifierValue.
  ModifierValue _parseValue(String valueStr, String operationType) {
    // Try integer first
    final intValue = int.tryParse(valueStr);
    if (intValue != null) {
      return IntModifierValue(intValue);
    }

    // Try double
    final doubleValue = double.tryParse(valueStr);
    if (doubleValue != null) {
      return DoubleModifierValue(doubleValue);
    }

    // Try boolean
    if (valueStr.toLowerCase() == 'true') {
      return const BoolModifierValue(true);
    }
    if (valueStr.toLowerCase() == 'false') {
      return const BoolModifierValue(false);
    }

    // Default to string
    return StringModifierValue(valueStr);
  }

  /// Resolves the target ID for a modifier.
  String? _resolveTargetId(
    WrappedNode modNode,
    WrappedFile wrappedFile,
    BoundPackBundle boundBundle,
  ) {
    // Look for explicit target reference
    final targetId = modNode.attributes['targetId'];
    if (targetId != null && targetId.isNotEmpty) {
      // Verify target exists
      final entry = boundBundle.entryById(targetId);
      final profile = boundBundle.profileById(targetId);
      if (entry != null || profile != null) {
        return targetId;
      }
      return null;
    }

    // Find parent entry by walking up the tree
    var currentRef = modNode.parent;
    while (currentRef != null) {
      final parentNode = wrappedFile.nodeAt(currentRef);
      final parentId = parentNode.attributes['id'];
      if (parentId != null && parentId.isNotEmpty) {
        final entry = boundBundle.entryById(parentId);
        if (entry != null) {
          return parentId;
        }
      }
      currentRef = parentNode.parent;
    }

    return null;
  }

  /// Applies an operation to a current value.
  ModifierValue? _applyOperation({
    required ModifierOperation operation,
    required ModifierValue? currentValue,
  }) {
    final opType = operation.operationType;
    final newValue = operation.value;

    switch (opType) {
      case 'set':
        // Set replaces the value
        return newValue;

      case 'increment':
        // Increment adds to current value
        if (newValue is IntModifierValue) {
          if (currentValue is IntModifierValue) {
            return IntModifierValue(currentValue.value + newValue.value);
          }
          // No current value - start from new value
          return newValue;
        }
        if (newValue is DoubleModifierValue) {
          if (currentValue is DoubleModifierValue) {
            return DoubleModifierValue(currentValue.value + newValue.value);
          }
          return newValue;
        }
        return newValue;

      case 'decrement':
        // Decrement subtracts from current value
        if (newValue is IntModifierValue) {
          if (currentValue is IntModifierValue) {
            return IntModifierValue(currentValue.value - newValue.value);
          }
          return IntModifierValue(-newValue.value);
        }
        if (newValue is DoubleModifierValue) {
          if (currentValue is DoubleModifierValue) {
            return DoubleModifierValue(currentValue.value - newValue.value);
          }
          return DoubleModifierValue(-newValue.value);
        }
        return newValue;

      case 'append':
        // Append concatenates strings
        if (newValue is StringModifierValue) {
          if (currentValue is StringModifierValue) {
            return StringModifierValue(currentValue.value + newValue.value);
          }
          return newValue;
        }
        return newValue;

      default:
        return newValue;
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
}

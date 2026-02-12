import 'package:combat_goblin_prime/modules/m6_evaluate/m6_evaluate.dart';
import 'package:combat_goblin_prime/modules/m7_applicability/m7_applicability.dart';
import 'package:combat_goblin_prime/modules/m8_modifiers/m8_modifiers.dart';

import '../models/orchestrator_diagnostic.dart';
import '../models/orchestrator_request.dart';
import '../models/view_bundle.dart';
import '../models/view_selection.dart';

/// Fatal exception for Orchestrator failures.
///
/// Thrown ONLY for:
/// 1. Corrupted M5 input — BoundPackBundle violates frozen contracts
/// 2. Internal invariant violation — Orchestrator implementation bug
/// 3. Evaluation order violation — M6/M7/M8 returned inconsistent state
///
/// **In normal operation, no OrchestratorFailure is thrown.**
class OrchestratorFailure implements Exception {
  final String message;
  final String? fileId;
  final String? details;
  final String invariant;

  const OrchestratorFailure({
    required this.message,
    required this.invariant,
    this.fileId,
    this.details,
  });

  static const invariantCorruptedInput = 'CORRUPTED_M5_INPUT';
  static const invariantInternalAssertion = 'INTERNAL_ASSERTION';
  static const invariantEvaluationOrder = 'EVALUATION_ORDER_VIOLATION';

  @override
  String toString() =>
      'OrchestratorFailure(invariant: $invariant, message: $message'
      '${fileId != null ? ', fileId: $fileId' : ''}'
      '${details != null ? ', details: $details' : ''})';
}

/// Coordinator service that calls M6/M7/M8 and produces ViewBundle.
///
/// Single deterministic entrypoint for all evaluations.
///
/// Evaluation order (fixed): M6 → M7 → M8
///
/// Determinism guarantee: Same [OrchestratorRequest] → identical [ViewBundle].
///
/// Part of Orchestrator v1 (PROPOSED).
class OrchestratorService {
  /// M6 Evaluate service (injected or created internally).
  final EvaluateService _evaluateService;

  /// M7 Applicability service (injected or created internally).
  final ApplicabilityService _applicabilityService;

  /// M8 Modifier service (injected or created internally).
  final ModifierService _modifierService;

  OrchestratorService({
    EvaluateService? evaluateService,
    ApplicabilityService? applicabilityService,
    ModifierService? modifierService,
  })  : _evaluateService = evaluateService ?? EvaluateService(),
        _applicabilityService = applicabilityService ?? ApplicabilityService(),
        _modifierService = modifierService ?? ModifierService();

  /// Builds a complete ViewBundle from the given request.
  ///
  /// Coordinates M6/M7/M8 evaluation in fixed order:
  /// 1. M6: evaluateConstraints()
  /// 2. For each selection:
  ///    a. M7: evaluate() for applicable conditions
  ///    b. M8: applyModifiers() for applicable modifiers
  /// 3. Aggregate results into ViewBundle
  ///
  /// Determinism: Same request → identical ViewBundle (except evaluatedAt).
  ViewBundle buildViewBundle(OrchestratorRequest request) {
    final evaluatedAt = DateTime.now().toUtc();
    final boundBundle = request.boundBundle;
    final snapshot = request.snapshot;
    final options = request.options;

    final diagnostics = <OrchestratorDiagnostic>[];

    // Step 1: Run M6 constraint evaluation
    final evaluationReport = _evaluateService.evaluateConstraints(
      boundBundle: boundBundle,
      snapshot: snapshot,
    );

    // Collect M6 diagnostics
    for (final warning in evaluationReport.warnings) {
      diagnostics.add(OrchestratorDiagnostic(
        source: DiagnosticSource.m6,
        code: warning.code,
        message: warning.message,
        sourceFileId: warning.sourceFileId,
        sourceNode: warning.sourceNode,
        targetId: warning.targetId,
      ));
    }

    // Step 2: Process each selection
    final selections = <ViewSelection>[];
    final allApplicabilityResults = <ApplicabilityResult>[];
    final allModifierResults = <ModifierResult>[];

    for (final selectionId in snapshot.orderedSelections()) {
      final entryId = snapshot.entryIdFor(selectionId);
      final boundEntry = boundBundle.entryById(entryId);

      if (boundEntry == null) {
        // Selection references non-existent entry
        diagnostics.add(OrchestratorDiagnostic.fromOrchestratorCode(
          code: OrchestratorDiagnosticCode.selectionNotInBundle,
          message: 'Selection "$selectionId" references unknown entry "$entryId"',
          sourceFileId: '',
          targetId: entryId,
        ));
        continue;
      }

      // Step 2a: M7 applicability for this selection's entry
      final wrappedFile = _findWrappedFileForEntry(boundBundle, boundEntry);
      final applicabilityResults = <ApplicabilityResult>[];

      if (wrappedFile != null) {
        final entryNode = wrappedFile.nodeAt(boundEntry.sourceNode);
        final result = _applicabilityService.evaluate(
          conditionSource: entryNode,
          sourceFileId: boundEntry.sourceFileId,
          sourceNode: boundEntry.sourceNode,
          snapshot: snapshot,
          boundBundle: boundBundle,
          contextSelectionId: selectionId,
        );
        applicabilityResults.add(result);
        allApplicabilityResults.add(result);

        // Collect M7 diagnostics
        for (final diag in result.diagnostics) {
          diagnostics.add(OrchestratorDiagnostic(
            source: DiagnosticSource.m7,
            code: diag.codeString,
            message: diag.message,
            sourceFileId: diag.sourceFileId,
            sourceNode: diag.sourceNode,
            targetId: diag.targetId,
          ));
        }
      }

      // Step 2b: M8 modifiers for this selection's entry
      final modifierResults = <ModifierResult>[];

      if (wrappedFile != null) {
        final entryNode = wrappedFile.nodeAt(boundEntry.sourceNode);
        final result = _modifierService.applyModifiers(
          modifierSource: entryNode,
          sourceFileId: boundEntry.sourceFileId,
          sourceNode: boundEntry.sourceNode,
          boundBundle: boundBundle,
          snapshot: snapshot,
          contextSelectionId: selectionId,
          applicabilityService: _applicabilityService,
        );
        modifierResults.add(result);
        allModifierResults.add(result);

        // Collect M8 diagnostics
        for (final diag in result.diagnostics) {
          diagnostics.add(OrchestratorDiagnostic(
            source: DiagnosticSource.m8,
            code: diag.codeString,
            message: diag.message,
            sourceFileId: diag.sourceFileId,
            sourceNode: diag.sourceNode,
            targetId: diag.targetId,
          ));
        }
      }

      // Build effective values map (sorted alphabetically)
      final effectiveValues = <String, ModifierValue?>{};
      for (final modResult in modifierResults) {
        if (modResult.target.field.isNotEmpty) {
          effectiveValues[modResult.target.field] = modResult.effectiveValue;
        }
      }
      final sortedEffectiveValues = Map.fromEntries(
        effectiveValues.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );

      selections.add(ViewSelection(
        selectionId: selectionId,
        entryId: entryId,
        boundEntry: boundEntry,
        appliedModifiers: modifierResults,
        applicabilityResults: applicabilityResults,
        effectiveValues: sortedEffectiveValues,
        sourceFileId: boundEntry.sourceFileId,
        sourceNode: boundEntry.sourceNode,
      ));
    }

    return ViewBundle(
      packId: boundBundle.packId,
      evaluatedAt: evaluatedAt,
      selections: selections,
      evaluationReport: evaluationReport,
      applicabilityResults: allApplicabilityResults,
      modifierResults: allModifierResults,
      diagnostics: diagnostics,
      boundBundle: boundBundle,
    );
  }

  /// Finds the WrappedFile containing a BoundEntry.
  dynamic _findWrappedFileForEntry(
    dynamic boundBundle,
    dynamic boundEntry,
  ) {
    final wrappedBundle = boundBundle.linkedBundle.wrappedBundle;
    final sourceFileId = boundEntry.sourceFileId;

    if (wrappedBundle.gameSystem.fileId == sourceFileId) {
      return wrappedBundle.gameSystem;
    }
    if (wrappedBundle.primaryCatalog.fileId == sourceFileId) {
      return wrappedBundle.primaryCatalog;
    }
    for (final dep in wrappedBundle.dependencyCatalogs) {
      if (dep.fileId == sourceFileId) {
        return dep;
      }
    }
    return null;
  }
}

import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m6_evaluate/m6_evaluate.dart';
import 'package:combat_goblin_prime/modules/m7_applicability/m7_applicability.dart';
import 'package:combat_goblin_prime/modules/m8_modifiers/m8_modifiers.dart';

import 'orchestrator_diagnostic.dart';
import 'view_selection.dart';

/// Complete orchestrated output containing all evaluation results.
///
/// Contains:
/// - ViewSelections for each selection in the snapshot
/// - Raw M6/M7/M8 results (preserved without transformation)
/// - Merged diagnostics from all modules
///
/// Deterministic: same inputs → identical ViewBundle.
///
/// Part of Orchestrator v1 (PROPOSED).
class ViewBundle {
  /// Pack identity (from BoundPackBundle).
  final String packId;

  /// Timestamp of orchestration.
  final DateTime evaluatedAt;

  /// Computed views for each selection.
  ///
  /// Ordered by snapshot.orderedSelections().
  final List<ViewSelection> selections;

  /// M6 constraint evaluations (preserved).
  final EvaluationReport evaluationReport;

  /// M7 applicability results (preserved).
  final List<ApplicabilityResult> applicabilityResults;

  /// M8 modifier results (preserved).
  final List<ModifierResult> modifierResults;

  /// Merged diagnostics from all modules.
  ///
  /// Order: M6 diagnostics, then M7, then M8, then Orchestrator.
  final List<OrchestratorDiagnostic> diagnostics;

  /// Reference to input BoundPackBundle (for downstream lookups).
  final BoundPackBundle boundBundle;

  const ViewBundle({
    required this.packId,
    required this.evaluatedAt,
    required this.selections,
    required this.evaluationReport,
    required this.applicabilityResults,
    required this.modifierResults,
    required this.diagnostics,
    required this.boundBundle,
  });

  @override
  String toString() =>
      'ViewBundle(packId: $packId, '
      'selections: ${selections.length}, '
      'diagnostics: ${diagnostics.length})';

  /// Creates a copy with updated evaluatedAt (for testing determinism).
  ViewBundle copyWithEvaluatedAt(DateTime newEvaluatedAt) {
    return ViewBundle(
      packId: packId,
      evaluatedAt: newEvaluatedAt,
      selections: selections,
      evaluationReport: evaluationReport,
      applicabilityResults: applicabilityResults,
      modifierResults: modifierResults,
      diagnostics: diagnostics,
      boundBundle: boundBundle,
    );
  }

  /// Compares two ViewBundles for equality, ignoring evaluatedAt.
  ///
  /// Used for determinism testing.
  bool equalsIgnoringTimestamp(ViewBundle other) {
    if (packId != other.packId) return false;
    if (selections.length != other.selections.length) return false;
    for (var i = 0; i < selections.length; i++) {
      if (selections[i] != other.selections[i]) return false;
    }
    if (diagnostics.length != other.diagnostics.length) return false;
    for (var i = 0; i < diagnostics.length; i++) {
      if (diagnostics[i] != other.diagnostics[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewBundle &&
          runtimeType == other.runtimeType &&
          packId == other.packId &&
          evaluatedAt == other.evaluatedAt &&
          _listEquals(selections, other.selections) &&
          _listEquals(diagnostics, other.diagnostics);

  @override
  int get hashCode =>
      packId.hashCode ^
      evaluatedAt.hashCode ^
      _deepListHash(selections) ^
      _deepListHash(diagnostics);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
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
}

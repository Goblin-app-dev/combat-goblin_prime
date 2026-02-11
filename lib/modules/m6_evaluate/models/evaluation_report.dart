import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';

import 'constraint_evaluation.dart';
import 'evaluation_notice.dart';
import 'evaluation_summary.dart';
import 'evaluation_warning.dart';

/// Strictly deterministic M6 output.
///
/// Two evaluations of the same inputs MUST produce identical reports.
/// Telemetry data is excluded from this type.
///
/// Part of M6 Evaluate (Phase 4).
class EvaluationReport {
  /// Pack identifier.
  final String packId;

  /// Derived from boundBundle.boundAt (deterministic).
  final DateTime evaluatedAt;

  /// All boundary evaluations.
  final List<ConstraintEvaluation> constraintEvaluations;

  /// Aggregate counts.
  final EvaluationSummary summary;

  /// Non-fatal issues (strict emission order).
  final List<EvaluationWarning> warnings;

  /// Informational messages (strict emission order).
  final List<EvaluationNotice> notices;

  /// Reference to M5 input (immutable).
  final BoundPackBundle boundBundle;

  const EvaluationReport({
    required this.packId,
    required this.evaluatedAt,
    required this.constraintEvaluations,
    required this.summary,
    required this.warnings,
    required this.notices,
    required this.boundBundle,
  });

  @override
  String toString() =>
      'EvaluationReport(packId: $packId, evaluations: ${constraintEvaluations.length}, hasViolations: ${summary.hasViolations})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationReport &&
          runtimeType == other.runtimeType &&
          packId == other.packId &&
          evaluatedAt == other.evaluatedAt &&
          _listEquals(constraintEvaluations, other.constraintEvaluations) &&
          summary == other.summary &&
          _listEquals(warnings, other.warnings) &&
          _listEquals(notices, other.notices);

  @override
  int get hashCode =>
      packId.hashCode ^
      evaluatedAt.hashCode ^
      constraintEvaluations.hashCode ^
      summary.hashCode ^
      warnings.hashCode ^
      notices.hashCode;

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

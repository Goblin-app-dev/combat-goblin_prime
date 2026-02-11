/// M6 Evaluate module.
///
/// Evaluates constraints against a selection snapshot.
/// Produces strictly deterministic EvaluationReport.
///
/// Part of Phase 4.
library m6_evaluate;

// Contracts
export 'contracts/selection_snapshot.dart';

// Models
export 'models/constraint_evaluation.dart';
export 'models/constraint_evaluation_outcome.dart';
export 'models/constraint_violation.dart';
export 'models/evaluate_failure.dart';
export 'models/evaluation_notice.dart';
export 'models/evaluation_report.dart';
export 'models/evaluation_scope.dart';
export 'models/evaluation_source_ref.dart';
export 'models/evaluation_summary.dart';
export 'models/evaluation_telemetry.dart';
export 'models/evaluation_warning.dart';

// Services
export 'services/evaluate_service.dart';

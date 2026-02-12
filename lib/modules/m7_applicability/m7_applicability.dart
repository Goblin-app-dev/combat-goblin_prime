/// M7 Applicability module.
///
/// Evaluates conditions to determine whether constraints, modifiers, and
/// other conditional elements apply to the current roster state.
///
/// Returns tri-state applicability (applies/skipped/unknown).
///
/// Part of Phase 5.
library m7_applicability;

// Models
export 'models/applicability_diagnostic.dart';
export 'models/applicability_failure.dart';
export 'models/applicability_result.dart';
export 'models/condition_evaluation.dart';
export 'models/condition_group_evaluation.dart';

// Services
export 'services/applicability_service.dart';

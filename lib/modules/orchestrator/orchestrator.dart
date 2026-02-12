/// Orchestrator module.
///
/// Single deterministic entrypoint that coordinates M6/M7/M8 evaluation
/// to produce a unified ViewBundle.
///
/// Orchestrator is a **coordinator**, not a pure composer:
/// - Takes BoundPackBundle + SelectionSnapshot
/// - Internally calls M6 → M7 → M8 in fixed order
/// - Returns complete ViewBundle with all results
///
/// Orchestrator does NOT add semantics, interpret rules, or persist data.
///
/// Part of Orchestrator v1 (PROPOSED).
library orchestrator;

// Models
export 'models/orchestrator_diagnostic.dart';
export 'models/orchestrator_options.dart';
export 'models/orchestrator_request.dart';
export 'models/view_bundle.dart';
export 'models/view_selection.dart';

// Services
export 'services/orchestrator_service.dart';

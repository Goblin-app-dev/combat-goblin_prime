import 'package:combat_goblin_prime/modules/m5_bind/m5_bind.dart';
import 'package:combat_goblin_prime/modules/m6_evaluate/m6_evaluate.dart';

import 'orchestrator_options.dart';

/// Input bundle for orchestration.
///
/// Contains all inputs needed to produce a ViewBundle:
/// - BoundPackBundle from M5 (read-only)
/// - SelectionSnapshot representing current roster state
/// - OrchestratorOptions for output configuration
///
/// Part of Orchestrator v1 (PROPOSED).
class OrchestratorRequest {
  /// M5 output (frozen, read-only).
  final BoundPackBundle boundBundle;

  /// Current roster state.
  final SelectionSnapshot snapshot;

  /// Configuration options.
  final OrchestratorOptions options;

  const OrchestratorRequest({
    required this.boundBundle,
    required this.snapshot,
    this.options = const OrchestratorOptions(),
  });

  @override
  String toString() =>
      'OrchestratorRequest(packId: ${boundBundle.packId}, '
      'selections: ${snapshot.orderedSelections().length})';
}

/// M3 Wrap module - converts parsed DTO trees into wrapped, indexed node graphs.
///
/// Phase 1C: Structural wrapping with deterministic indexing.
/// No cross-file linking. No semantic interpretation.
library m3_wrap;

export 'models/node_ref.dart';
export 'models/wrap_failure.dart';
export 'models/wrapped_file.dart';
export 'models/wrapped_node.dart';
export 'models/wrapped_pack_bundle.dart';
export 'services/wrap_service.dart';

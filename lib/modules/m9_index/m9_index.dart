/// M9 Index-Core (Search) module.
///
/// Builds a deterministic, canonical search index from M5 BoundPackBundle.
/// Transforms bound entities into a flattened, player-facing document model
/// optimized for:
/// - Unit lookup by name
/// - Weapon lookup by name
/// - Rule lookup by name
/// - Keyword/category filtering
/// - Voice-ready stat and rule retrieval
///
/// M9 does NOT:
/// - Execute rules
/// - Evaluate constraints
/// - Apply modifiers
/// - Depend on rosters
/// - Depend on M6/M7/M8
///
/// Input: BoundPackBundle (M5)
/// Output: IndexBundle (immutable, deterministic)
///
/// Part of M9 Index-Core (Search).
library m9_index;

// Models
export 'models/index_bundle.dart';
export 'models/index_diagnostic.dart';
export 'models/indexed_characteristic.dart';
export 'models/indexed_cost.dart';
export 'models/rule_doc.dart';
export 'models/unit_doc.dart';
export 'models/weapon_doc.dart';

// Services
export 'services/index_service.dart';

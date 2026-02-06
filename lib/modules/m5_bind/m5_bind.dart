/// M5 Bind module - converts linked bundle into typed, queryable entities.
///
/// Phase 3: Interpretation and binding with query surface.
/// Represents constraints but does NOT evaluate them.
library m5_bind;

export 'models/bind_diagnostic.dart';
export 'models/bind_failure.dart';
export 'models/bound_category.dart';
export 'models/bound_constraint.dart';
export 'models/bound_cost.dart';
export 'models/bound_entry.dart';
export 'models/bound_pack_bundle.dart';
export 'models/bound_profile.dart';
export 'services/bind_service.dart';

/// M8 Modifiers module.
///
/// Applies modifier operations to produce effective values for entry
/// characteristics, costs, constraints, and other modifiable fields.
///
/// M8 applies modifiers. M8 does NOT evaluate constraints (M6's job)
/// or evaluate conditions (M7's job).
///
/// Part of Phase 6.
library m8_modifiers;

// Models
export 'models/modifier_diagnostic.dart';
export 'models/modifier_failure.dart';
export 'models/modifier_operation.dart';
export 'models/modifier_result.dart';
export 'models/modifier_target_ref.dart';
export 'models/modifier_value.dart';

// Services
export 'services/modifier_service.dart';

/// M9 Index-Core (Search) module.
///
/// **STATUS: FROZEN** (2026-02-13)
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
/// ## Frozen Invariants
///
/// These guarantees are locked and must not change without a new module version:
///
/// ### Identity Model
/// - **docId**: Globally unique, type-prefixed (`unit:`, `weapon:`, `rule:`)
/// - **canonicalKey**: Normalized name for search grouping (lowercase, no punctuation)
/// - Multiple docs may share the same canonicalKey; docId is always unique
///
/// ### Determinism
/// - Same M5 input → identical IndexBundle output (byte-for-byte)
/// - All index maps are SplayTreeMap (sorted keys)
/// - All docId lists are sorted
/// - All doc collections are sorted by docId
/// - Tokenization output is sorted and deduplicated
///
/// ### Query Surface
/// - `findUnitsByName`, `findWeaponsByName`, `findRulesByName` (exact match)
/// - `findUnitsContaining`, `findWeaponsContaining`, `findRulesContaining` (substring)
/// - `unitsByKeyword`, `unitsByCanonicalKey`, etc. (index lookups)
/// - `autocompleteUnitKeys`, `autocompleteWeaponKeys`, `autocompleteRuleKeys`
/// - All queries normalize input, return stable-sorted results
///
/// ### Diagnostics
/// - Closed enum: no new codes without new module version
/// - Summary diagnostics for deduplication (not per-instance spam)
/// - DUPLICATE_SOURCE_PROFILE_SKIPPED: count of deduplicated profiles
///
/// ## M9 does NOT:
/// - Execute rules
/// - Evaluate constraints
/// - Apply modifiers
/// - Depend on rosters
/// - Depend on M6/M7/M8
///
/// ## Invocation
///
/// M9 is invoked at **pack-load time**, not per-roster:
/// ```dart
/// // After M5 bind completes:
/// final indexBundle = IndexService().buildIndex(boundPackBundle);
/// // IndexBundle is then cached/reused for all roster operations
/// ```
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

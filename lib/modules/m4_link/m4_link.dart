/// M4 Link module — Cross-file reference resolution.
///
/// Resolves targetId references across files in a WrappedPackBundle.
/// Produces LinkedPackBundle with symbol table and resolved refs.
///
/// Part of Phase 2.
library m4_link;

export 'models/link_diagnostic.dart';
export 'models/link_failure.dart';
export 'models/linked_pack_bundle.dart';
export 'models/resolved_ref.dart';
export 'models/symbol_table.dart';
export 'services/link_service.dart';

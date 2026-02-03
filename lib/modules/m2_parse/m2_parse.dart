/// M2 Parse module - converts raw XML bytes into generic DTO trees.
///
/// Phase 1B: Lossless parsing preserving structure and document order.
library m2_parse;

export 'models/element_dto.dart';
export 'models/parse_failure.dart';
export 'models/parsed_file.dart';
export 'models/parsed_pack_bundle.dart';
export 'services/parse_service.dart';

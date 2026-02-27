import 'spoken_entity.dart';
import 'spoken_variant.dart';

/// In-memory cursor over a list of [SpokenEntity] results.
///
/// Cycling is **clamped**: [nextVariant] and [previousVariant] stop at
/// bounds (index 0 and N-1). No wrap-around.
///
/// Create from [VoiceSearchResponse.entities]:
/// ```dart
/// final session = VoiceSelectionSession(response.entities);
/// ```
class VoiceSelectionSession {
  final List<SpokenEntity> entities;

  int _entityIndex = 0;
  int _variantIndex = 0;

  VoiceSelectionSession(this.entities);

  bool get isEmpty => entities.isEmpty;

  /// Current entity, or null if [entities] is empty.
  SpokenEntity? get currentEntity =>
      entities.isEmpty ? null : entities[_entityIndex];

  /// Current variant within the current entity, or null if empty.
  SpokenVariant? get currentVariant {
    final entity = currentEntity;
    if (entity == null) return null;
    return entity.variants[_variantIndex];
  }

  int get entityIndex => _entityIndex;
  int get variantIndex => _variantIndex;

  /// Move to next variant within current entity. Clamps at last variant.
  void nextVariant() {
    final entity = currentEntity;
    if (entity == null) return;
    _variantIndex =
        (_variantIndex + 1).clamp(0, entity.variants.length - 1);
  }

  /// Move to previous variant within current entity. Clamps at 0.
  void previousVariant() {
    _variantIndex = (_variantIndex - 1).clamp(0, _maxVariantIndex);
  }

  /// Move to next entity. Resets variant index to 0. Clamps at last entity.
  void nextEntity() {
    if (entities.isEmpty) return;
    _entityIndex = (_entityIndex + 1).clamp(0, entities.length - 1);
    _variantIndex = 0;
  }

  /// Move to previous entity. Resets variant index to 0. Clamps at 0.
  void previousEntity() {
    if (entities.isEmpty) return;
    _entityIndex = (_entityIndex - 1).clamp(0, entities.length - 1);
    _variantIndex = 0;
  }

  /// Jump to entity at [index]. Clamped to valid range.
  void chooseEntity(int index) {
    if (entities.isEmpty) return;
    _entityIndex = index.clamp(0, entities.length - 1);
    _variantIndex = 0;
  }

  /// Reset cursor to entity 0, variant 0.
  void reset() {
    _entityIndex = 0;
    _variantIndex = 0;
  }

  int get _maxVariantIndex {
    final entity = currentEntity;
    if (entity == null) return 0;
    return entity.variants.length - 1;
  }
}

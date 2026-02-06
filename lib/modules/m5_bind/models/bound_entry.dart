import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

import 'bound_category.dart';
import 'bound_constraint.dart';
import 'bound_cost.dart';
import 'bound_profile.dart';

/// Interpreted entry (selectionEntry or selectionEntryGroup).
///
/// Eligible tagNames: `selectionEntry`, `selectionEntryGroup`
///
/// Part of M5 Bind (Phase 3).
class BoundEntry {
  final String id;
  final String name;

  /// True if source was selectionEntryGroup.
  final bool isGroup;

  /// True if source had hidden="true".
  final bool isHidden;

  /// Nested entries and resolved entryLinks.
  final List<BoundEntry> children;

  /// Nested profiles and resolved infoLinks.
  final List<BoundProfile> profiles;

  /// Categories via categoryEntry and resolved categoryLinks.
  final List<BoundCategory> categories;

  /// Nested cost elements.
  final List<BoundCost> costs;

  /// Nested constraint elements (NOT evaluated).
  final List<BoundConstraint> constraints;

  /// Provenance: file containing this entry.
  final String sourceFileId;

  /// Provenance: node reference.
  final NodeRef sourceNode;

  const BoundEntry({
    required this.id,
    required this.name,
    required this.isGroup,
    required this.isHidden,
    required this.children,
    required this.profiles,
    required this.categories,
    required this.costs,
    required this.constraints,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  String toString() =>
      'BoundEntry(id: $id, name: $name, group: $isGroup, hidden: $isHidden)';
}

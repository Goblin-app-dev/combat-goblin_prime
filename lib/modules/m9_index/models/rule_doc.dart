import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Canonical rule entry for search indexing.
///
/// RuleDocs are deduplicated by canonical key. When multiple rules share
/// the same normalized name, only the first (in stable iteration order)
/// becomes a RuleDoc; others link to it.
///
/// Sources (v1):
/// - Ability-type profiles with description text
///
/// Part of M9 Index-Core (Search).
class RuleDoc {
  /// Canonical document ID (stable, deterministic).
  final String docId;

  /// Original rule/profile ID from M5 (for provenance).
  final String ruleId;

  /// Display name of the rule.
  final String name;

  /// Rule description/effect text.
  final String description;

  /// Page reference (if available).
  final String? page;

  /// Source file ID (for provenance).
  final String sourceFileId;

  /// Source node reference (for provenance).
  final NodeRef sourceNode;

  const RuleDoc({
    required this.docId,
    required this.ruleId,
    required this.name,
    required this.description,
    this.page,
    required this.sourceFileId,
    required this.sourceNode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleDoc &&
          runtimeType == other.runtimeType &&
          docId == other.docId &&
          ruleId == other.ruleId &&
          name == other.name &&
          description == other.description &&
          page == other.page &&
          sourceFileId == other.sourceFileId &&
          sourceNode == other.sourceNode;

  @override
  int get hashCode =>
      docId.hashCode ^
      ruleId.hashCode ^
      name.hashCode ^
      description.hashCode ^
      (page?.hashCode ?? 0) ^
      sourceFileId.hashCode ^
      sourceNode.hashCode;

  @override
  String toString() => 'RuleDoc($docId: "$name")';
}

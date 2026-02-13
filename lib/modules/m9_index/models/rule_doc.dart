import 'package:combat_goblin_prime/modules/m3_wrap/m3_wrap.dart';

/// Canonical rule entry for search indexing.
///
/// Identity vs Search:
/// - docId: Globally unique stable identifier (rule:{ruleId})
/// - canonicalKey: Normalized name for search grouping (normalize(name))
///
/// Multiple rules may share the same canonicalKey (e.g., "Leader" ability
/// on many characters). Use canonicalKey for search, docId for identity.
///
/// Sources (v1):
/// - Ability-type profiles with description text
///
/// Part of M9 Index-Core (Search).
class RuleDoc {
  /// Globally unique document ID (format: "rule:{ruleId}").
  final String docId;

  /// Canonical search key (normalized name for grouping).
  final String canonicalKey;

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
    required this.canonicalKey,
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
          docId == other.docId;

  @override
  int get hashCode => docId.hashCode;

  @override
  String toString() => 'RuleDoc($docId: "$name")';
}

import 'dart:convert';

import 'package:combat_goblin_prime/modules/m9_index/m9_index.dart';

// ---------------------------------------------------------------------------
// Data model: one unit's full exported dump
// ---------------------------------------------------------------------------

class WeaponStatDump {
  final String name;
  final Map<String, String> stats; // {Range, A, BS/WS, S, AP, D}
  final List<String> keywords; // weapon keyword tokens
  final String docId;

  const WeaponStatDump({
    required this.name,
    required this.stats,
    required this.keywords,
    required this.docId,
  });

  Map<String, Object> toJson() => {
        'name': name,
        'stats': stats,
        'keywords': keywords,
        'docId': docId,
      };
}

class RuleDump {
  final String name;
  final String description;
  final String docId;

  const RuleDump({
    required this.name,
    required this.description,
    required this.docId,
  });

  Map<String, Object> toJson() => {
        'name': name,
        'description': description,
        'docId': docId,
      };
}

class UnitAuditDump {
  // --- Identity ---
  final String name;
  final String docId;
  final String entryId;
  final String sourceFileId;

  // --- Core stats ---
  final Map<String, String> characteristics; // {M, T, SV, W, LD, OC, ...}

  // --- Costs ---
  final List<Map<String, Object>> costs; // [{typeId, typeName, value}]

  // --- Keywords ---
  /// Full category names, space-normalized, NOT fragmented.
  /// e.g. ["hive tyrant", "infantry", "monster", "psyker", "synapse", "tyranids"]
  final List<String> categoryTokens;

  /// Inverted-index keyword tokens built by M9.
  ///
  /// Since the E-class fragmentation fix, _collectCategoryKeywords uses
  /// normalize(name), so multi-word category names are stored as phrases
  /// (e.g. "adeptus astartes"), not split into individual word fragments.
  final List<String> keywordTokens;

  // --- Weapons ---
  final List<WeaponStatDump> weapons;

  // --- Rules / Abilities ---
  final List<RuleDump> rules;

  // --- Diagnostics / provenance ---
  final int weaponDocRefCount;
  final int ruleDocRefCount;
  final int keywordTokenCount;
  final int categoryTokenCount;

  const UnitAuditDump({
    required this.name,
    required this.docId,
    required this.entryId,
    required this.sourceFileId,
    required this.characteristics,
    required this.costs,
    required this.categoryTokens,
    required this.keywordTokens,
    required this.weapons,
    required this.rules,
    required this.weaponDocRefCount,
    required this.ruleDocRefCount,
    required this.keywordTokenCount,
    required this.categoryTokenCount,
  });

  Map<String, Object> toJson() => {
        'identity': {
          'name': name,
          'docId': docId,
          'entryId': entryId,
          'sourceFileId': sourceFileId,
        },
        'characteristics': characteristics,
        'costs': costs,
        'keywords': {
          'categoryTokens': categoryTokens,
          'keywordTokens': keywordTokens,
          'note':
              'categoryTokens = preserved full names; keywordTokens = inverted-index tokens (normalized phrases since E-class bug fix). '
                  'If multi-word category names appear fragmented in keywordTokens, this is a regression of the E-class bug.',
        },
        'weapons': weapons.map((w) => w.toJson()).toList(),
        'rules': rules.map((r) => r.toJson()).toList(),
        'diagnostics': {
          'weaponDocRefCount': weaponDocRefCount,
          'ruleDocRefCount': ruleDocRefCount,
          'keywordTokenCount': keywordTokenCount,
          'categoryTokenCount': categoryTokenCount,
        },
      };

  String toPrettyJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  /// Produces a human-readable text summary in the format the audit brief specifies.
  String toAuditText() {
    final buf = StringBuffer();
    buf.writeln('=== UNIT AUDIT DUMP: $name ===');
    buf.writeln();

    buf.writeln('--- Identity ---');
    buf.writeln('name        : $name');
    buf.writeln('docId       : $docId');
    buf.writeln('entryId     : $entryId');
    buf.writeln('sourceFile  : $sourceFileId');
    buf.writeln();

    buf.writeln('--- Core Characteristics ---');
    for (final e in characteristics.entries) {
      buf.writeln('  ${e.key.padRight(6)}: ${e.value}');
    }
    buf.writeln();

    buf.writeln('--- Points / Costs ---');
    for (final c in costs) {
      buf.writeln('  ${c['typeName']} (${c['typeId']}): ${c['value']}');
    }
    buf.writeln();

    buf.writeln('--- Keywords ---');
    buf.writeln('  categoryTokens (full names, preserved):');
    for (final k in categoryTokens) {
      buf.writeln('    "$k"');
    }
    buf.writeln('  keywordTokens (inverted-index fragments):');
    for (final k in keywordTokens) {
      buf.writeln('    "$k"');
    }
    buf.writeln();

    buf.writeln('--- Weapons (${weapons.length}) ---');
    for (final w in weapons) {
      buf.writeln('  ${w.name}');
      for (final e in w.stats.entries) {
        buf.writeln('    ${e.key}: ${e.value}');
      }
      if (w.keywords.isNotEmpty) {
        buf.writeln('    keywords: ${w.keywords.join(', ')}');
      }
      buf.writeln('    docId: ${w.docId}');
    }
    buf.writeln();

    buf.writeln('--- Rules / Abilities (${rules.length}) ---');
    for (final r in rules) {
      buf.writeln('  ${r.name}');
      final desc = r.description.length > 120
          ? '${r.description.substring(0, 120)}...'
          : r.description;
      buf.writeln('    $desc');
      buf.writeln('    docId: ${r.docId}');
    }
    buf.writeln();

    buf.writeln('--- Diagnostics ---');
    buf.writeln('  weaponDocRefs  : $weaponDocRefCount');
    buf.writeln('  ruleDocRefs    : $ruleDocRefCount');
    buf.writeln('  keywordTokens  : $keywordTokenCount');
    buf.writeln('  categoryTokens : $categoryTokenCount');

    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// Exporter: builds UnitAuditDump from an IndexBundle + unit name
// ---------------------------------------------------------------------------

class UnitDumpExporter {
  /// Exports a dump for the first unit whose name matches [unitName]
  /// (case-insensitive, after normalization).
  ///
  /// Returns null if the unit is not found in the index.
  UnitAuditDump? exportByName(IndexBundle index, String unitName) {
    final matches = index.findUnitsByName(unitName);
    if (matches.isEmpty) {
      // Try contains search as fallback
      final containsMatches = index.findUnitsContaining(unitName);
      if (containsMatches.isEmpty) return null;
      return _buildDump(index, containsMatches.first);
    }
    return _buildDump(index, matches.first);
  }

  /// Exports dumps for all units in the index (useful for bulk audit).
  List<UnitAuditDump> exportAll(IndexBundle index) {
    return index.units.map((u) => _buildDump(index, u)).toList();
  }

  UnitAuditDump _buildDump(IndexBundle index, UnitDoc unit) {
    // --- Characteristics ---
    final charMap = <String, String>{};
    for (final c in unit.characteristics) {
      charMap[c.name] = c.valueText;
    }

    // --- Costs ---
    final costList = unit.costs
        .map((c) => <String, Object>{
              'typeId': c.typeId,
              'typeName': c.typeName,
              'value': c.value,
            })
        .toList();

    // --- Weapons ---
    final weapons = <WeaponStatDump>[];
    for (final ref in unit.weaponDocRefs) {
      final w = index.weaponByDocId(ref);
      if (w == null) continue;
      final stats = <String, String>{};
      for (final c in w.characteristics) {
        stats[c.name] = c.valueText;
      }
      weapons.add(WeaponStatDump(
        name: w.name,
        stats: stats,
        keywords: w.keywordTokens,
        docId: w.docId,
      ));
    }

    // --- Rules ---
    final rules = <RuleDump>[];
    for (final ref in unit.ruleDocRefs) {
      final r = index.ruleByDocId(ref);
      if (r == null) continue;
      rules.add(RuleDump(
        name: r.name,
        description: r.description,
        docId: r.docId,
      ));
    }

    return UnitAuditDump(
      name: unit.name,
      docId: unit.docId,
      entryId: unit.entryId,
      sourceFileId: unit.sourceFileId,
      characteristics: charMap,
      costs: costList,
      categoryTokens: unit.categoryTokens,
      keywordTokens: unit.keywordTokens,
      weapons: weapons,
      rules: rules,
      weaponDocRefCount: unit.weaponDocRefs.length,
      ruleDocRefCount: unit.ruleDocRefs.length,
      keywordTokenCount: unit.keywordTokens.length,
      categoryTokenCount: unit.categoryTokens.length,
    );
  }
}

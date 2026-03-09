import 'dart:convert';
import 'dart:io';

import 'unit_dump_exporter.dart';

// ---------------------------------------------------------------------------
// Error classes (as specified in audit brief)
// ---------------------------------------------------------------------------

enum AuditErrorClass {
  /// A. Unit identity errors
  unitIdentity,

  /// B. Core stats errors
  coreStats,

  /// C. Weapon errors
  weapons,

  /// D. Rules / abilities errors
  rules,

  /// E. Keyword errors (includes fragmentation bug)
  keywords,

  /// F. Cost errors
  costs,

  /// G. Formatting / presentation
  formatting,

  /// H. Structural source-model mismatch.
  ///
  /// Not a bug, not a pass — a fundamental difference in how the source
  /// (BattleScribe) and the reference (Wahapedia) organise data.
  /// Examples:
  ///   - BattleScribe stores individual model entries; Wahapedia shows squads.
  ///   - BattleScribe splits weapons by profile; Wahapedia groups them.
  /// Requires a mapping policy decision, not a pipeline fix.
  structural,
}

enum AuditErrorSeverity { critical, major, minor, info }

enum AuditPipelineStage {
  m5Bind,
  m9Index,
  qaAssembly,
  uiPresentation,
  unknown,
}

enum AuditMismatchKind {
  // Identity
  wrongName,
  wrongVariantSelected,

  // Stats
  missingStat,
  wrongStatValue,

  // Weapons
  missingWeapon,
  extraWeapon,
  wrongWeaponStat,
  wrongWeaponKeyword,

  // Rules
  missingRule,
  extraRule,
  wrongRuleDescription,
  truncatedDescription,

  // Keywords
  missingKeyword,
  extraKeyword,
  keywordFragmented, // multi-word phrase split into tokens
  weaponWordsPollutingKeywords,

  // Costs
  missingPoints,
  wrongPoints,
  extraCostFields,

  // Formatting
  wrongDisplayOrder,
  debugJunkVisible,

  // Structural (H-class)
  /// Source uses model-entry granularity; reference uses datasheet granularity.
  /// Not a pipeline bug — requires a mapping policy.
  datasheetVsModelEntryGranularity,

  /// Source and reference disagree on how weapons are grouped/profiled.
  weaponProfileGranularity,
}

// ---------------------------------------------------------------------------
// Comparison target type
// ---------------------------------------------------------------------------

/// Declares the granularity level at which the comparison is being made.
///
/// This is a first-class audit field because BattleScribe and Wahapedia can
/// organise the same game data at different levels.  Marking the comparison
/// target explicitly prevents structural differences from masquerading as
/// extraction bugs.
///
/// Values:
///   - [datasheet]   — comparing against a full Wahapedia datasheet (squad)
///   - [modelEntry]  — comparing against a single model entry in BattleScribe
///   - [weapon]      — weapon-level comparison
///   - [rule]        — rule/ability-level comparison
enum AuditComparisonTargetType {
  /// Full squad/unit datasheet as shown on Wahapedia.
  datasheet,

  /// Individual model entry as stored in BattleScribe (sub-squad granularity).
  ///
  /// When this value is set, mismatches that arise purely because BattleScribe
  /// stores one model while Wahapedia shows the whole squad should be classified
  /// as [AuditMismatchKind.datasheetVsModelEntryGranularity] (H-class) rather
  /// than as data extraction errors.
  modelEntry,

  /// Single weapon profile comparison.
  weapon,

  /// Single rule or ability comparison.
  rule,
}

// ---------------------------------------------------------------------------
// Ground truth model (loaded from JSON)
// ---------------------------------------------------------------------------

class WeaponGroundTruth {
  final String name;
  final Map<String, String> stats;
  final List<String> keywords;

  const WeaponGroundTruth({
    required this.name,
    required this.stats,
    required this.keywords,
  });

  factory WeaponGroundTruth.fromJson(Map<String, dynamic> json) =>
      WeaponGroundTruth(
        name: json['name'] as String,
        stats: Map<String, String>.from(json['stats'] as Map),
        keywords: List<String>.from(json['keywords'] as List),
      );
}

class RuleGroundTruth {
  final String name;
  final String? descriptionSubstring; // partial match is OK

  const RuleGroundTruth({required this.name, this.descriptionSubstring});

  factory RuleGroundTruth.fromJson(Map<String, dynamic> json) =>
      RuleGroundTruth(
        name: json['name'] as String,
        descriptionSubstring: json['descriptionSubstring'] as String?,
      );
}

class UnitGroundTruth {
  final String unitName;
  final String source; // e.g. "Wahapedia 2026-03-08"

  /// Declares the granularity level of this comparison.
  ///
  /// When [comparisonTargetType] is [AuditComparisonTargetType.modelEntry],
  /// the comparator knows that mismatches arising purely from BattleScribe's
  /// model-entry vs Wahapedia's squad-datasheet structure should be classified
  /// as H-class [AuditMismatchKind.datasheetVsModelEntryGranularity] rather
  /// than as extraction bugs.
  final AuditComparisonTargetType comparisonTargetType;

  final Map<String, String> expectedStats;
  final int? expectedPoints; // null = not checked
  final List<String> expectedKeywords; // full keyword names, uppercase
  final List<WeaponGroundTruth> expectedWeapons;
  final List<RuleGroundTruth> expectedRules;
  final List<String> notes;

  const UnitGroundTruth({
    required this.unitName,
    required this.source,
    this.comparisonTargetType = AuditComparisonTargetType.datasheet,
    required this.expectedStats,
    this.expectedPoints,
    required this.expectedKeywords,
    required this.expectedWeapons,
    required this.expectedRules,
    this.notes = const [],
  });

  factory UnitGroundTruth.fromJson(Map<String, dynamic> json) {
    final targetTypeStr = json['comparisonTargetType'] as String? ?? 'datasheet';
    final targetType = AuditComparisonTargetType.values.firstWhere(
      (v) => v.name == targetTypeStr,
      orElse: () => AuditComparisonTargetType.datasheet,
    );
    return UnitGroundTruth(
      unitName: json['unitName'] as String,
      source: json['source'] as String,
      comparisonTargetType: targetType,
      expectedStats: Map<String, String>.from(json['expectedStats'] as Map),
      expectedPoints: json['expectedPoints'] as int?,
      expectedKeywords: List<String>.from(json['expectedKeywords'] as List),
      expectedWeapons: (json['expectedWeapons'] as List)
          .map((e) => WeaponGroundTruth.fromJson(e as Map<String, dynamic>))
          .toList(),
      expectedRules: (json['expectedRules'] as List)
          .map((e) => RuleGroundTruth.fromJson(e as Map<String, dynamic>))
          .toList(),
      notes: List<String>.from(json['notes'] as List? ?? []),
    );
  }

  static UnitGroundTruth? loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return UnitGroundTruth.fromJson(json);
  }
}

// ---------------------------------------------------------------------------
// Mismatch record
// ---------------------------------------------------------------------------

class AuditMismatch {
  final String unit;
  final String section;
  final String expected;
  final String observed;
  final AuditErrorClass errorClass;
  final AuditMismatchKind kind;
  final AuditErrorSeverity severity;
  final AuditPipelineStage likelyStage;
  final String notes;

  const AuditMismatch({
    required this.unit,
    required this.section,
    required this.expected,
    required this.observed,
    required this.errorClass,
    required this.kind,
    required this.severity,
    required this.likelyStage,
    this.notes = '',
  });

  Map<String, String> toRow() => {
        'Unit': unit,
        'Section': section,
        'Expected': expected,
        'Observed': observed,
        'ErrorClass': errorClass.name,
        'Kind': kind.name,
        'Severity': severity.name,
        'LikelyStage': likelyStage.name,
        'Notes': notes,
      };
}

// ---------------------------------------------------------------------------
// Comparator: diffs dump against ground truth, classifies mismatches
// ---------------------------------------------------------------------------

class AuditComparator {
  List<AuditMismatch> compare(
    UnitAuditDump dump,
    UnitGroundTruth truth,
  ) {
    final mismatches = <AuditMismatch>[];

    _compareStats(dump, truth, mismatches);
    _compareCosts(dump, truth, mismatches);
    _compareKeywords(dump, truth, mismatches);
    _compareWeapons(dump, truth, mismatches);
    _compareRules(dump, truth, mismatches);

    return mismatches;
  }

  void _compareStats(
    UnitAuditDump dump,
    UnitGroundTruth truth,
    List<AuditMismatch> out,
  ) {
    for (final entry in truth.expectedStats.entries) {
      final statName = entry.key;
      final expectedValue = entry.value;
      final observedValue = dump.characteristics[statName];

      if (observedValue == null) {
        out.add(AuditMismatch(
          unit: dump.name,
          section: 'Stats',
          expected: '$statName = $expectedValue',
          observed: 'MISSING',
          errorClass: AuditErrorClass.coreStats,
          kind: AuditMismatchKind.missingStat,
          severity: AuditErrorSeverity.critical,
          likelyStage: AuditPipelineStage.m9Index,
        ));
      } else if (observedValue.trim() != expectedValue.trim()) {
        out.add(AuditMismatch(
          unit: dump.name,
          section: 'Stats',
          expected: '$statName = $expectedValue',
          observed: '$statName = $observedValue',
          errorClass: AuditErrorClass.coreStats,
          kind: AuditMismatchKind.wrongStatValue,
          severity: AuditErrorSeverity.major,
          likelyStage: AuditPipelineStage.m9Index,
        ));
      }
    }
  }

  void _compareCosts(
    UnitAuditDump dump,
    UnitGroundTruth truth,
    List<AuditMismatch> out,
  ) {
    if (truth.expectedPoints == null) return;

    // Find a pts-like cost entry
    final ptsCost = dump.costs.where((c) {
      final name = (c['typeName'] as String).toLowerCase();
      return name.contains('pt') || name.contains('point');
    }).firstOrNull;

    if (ptsCost == null) {
      out.add(AuditMismatch(
        unit: dump.name,
        section: 'Costs',
        expected: '${truth.expectedPoints} pts',
        observed: 'NO PTS COST FOUND (costs: ${dump.costs.map((c) => c['typeName']).join(', ')})',
        errorClass: AuditErrorClass.costs,
        kind: AuditMismatchKind.missingPoints,
        severity: AuditErrorSeverity.critical,
        likelyStage: AuditPipelineStage.m9Index,
      ));
      return;
    }

    final observedPts = ptsCost['value'];
    if (observedPts.toString() != truth.expectedPoints.toString()) {
      out.add(AuditMismatch(
        unit: dump.name,
        section: 'Costs',
        expected: '${truth.expectedPoints}',
        observed: '$observedPts',
        errorClass: AuditErrorClass.costs,
        kind: AuditMismatchKind.wrongPoints,
        severity: AuditErrorSeverity.major,
        likelyStage: AuditPipelineStage.m9Index,
      ));
    }

    // Flag non-pts cost fields as potential pollution
    if (dump.costs.length > 1) {
      final extraFields =
          dump.costs.where((c) => c != ptsCost).map((c) => c['typeName']).join(', ');
      out.add(AuditMismatch(
        unit: dump.name,
        section: 'Costs',
        expected: 'only pts cost',
        observed: 'extra cost fields: $extraFields',
        errorClass: AuditErrorClass.costs,
        kind: AuditMismatchKind.extraCostFields,
        severity: AuditErrorSeverity.minor,
        likelyStage: AuditPipelineStage.uiPresentation,
        notes: 'Policy decision: should extra cost fields be shown?',
      ));
    }
  }

  void _compareKeywords(
    UnitAuditDump dump,
    UnitGroundTruth truth,
    List<AuditMismatch> out,
  ) {
    // Normalize expected keywords to lowercase for comparison
    final expectedNormalized =
        truth.expectedKeywords.map((k) => k.toLowerCase()).toSet();
    final observedCategoryTokens = dump.categoryTokens.toSet();
    final observedKeywordTokens = dump.keywordTokens.toSet();

    // Check each expected keyword
    for (final expected in expectedNormalized) {
      final normalizedExpected = expected.replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();

      if (observedCategoryTokens.contains(normalizedExpected)) {
        // Correct: full phrase preserved in categoryTokens
        continue;
      }

      // Check if it appears fragmented in keywordTokens
      final words = normalizedExpected.split(' ').where((w) => w.isNotEmpty).toList();
      final allFragmentsPresent = words.every((w) => observedKeywordTokens.contains(w));

      if (allFragmentsPresent && words.length > 1) {
        // Regression of the E-class fragmentation bug (should be fixed in
        // index_service.dart _collectCategoryKeywords via normalize(name)).
        out.add(AuditMismatch(
          unit: dump.name,
          section: 'Keywords',
          expected: '"${truth.expectedKeywords.firstWhere((k) => k.toLowerCase() == expected)}"',
          observed:
              'fragmented as: ${words.map((w) => '"$w"').join(', ')} in keywordTokens; MISSING as phrase in categoryTokens',
          errorClass: AuditErrorClass.keywords,
          kind: AuditMismatchKind.keywordFragmented,
          severity: AuditErrorSeverity.major,
          likelyStage: AuditPipelineStage.m9Index,
          notes:
              'Regression: _collectCategoryKeywords must use normalize(name), not tokenize(name). '
                  'Check index_service.dart _collectCategoryKeywords.',
        ));
      } else if (!allFragmentsPresent) {
        // Completely missing — classify based on comparison target type.
        if (truth.comparisonTargetType == AuditComparisonTargetType.modelEntry) {
          // Keyword may live on a parent squad/datasheet node rather than the
          // individual model entry being audited. This is a structural
          // source-model difference, not an extraction bug.
          out.add(AuditMismatch(
            unit: dump.name,
            section: 'Keywords',
            expected: '"${truth.expectedKeywords.firstWhere((k) => k.toLowerCase() == expected)}"',
            observed: 'MISSING from both categoryTokens and keywordTokens',
            errorClass: AuditErrorClass.structural,
            kind: AuditMismatchKind.datasheetVsModelEntryGranularity,
            severity: AuditErrorSeverity.info,
            likelyStage: AuditPipelineStage.unknown,
            notes:
                'modelEntry comparison: keyword may live on parent squad/datasheet node. '
                    'Verify whether the expected keyword is assigned at squad level in BattleScribe '
                    'before treating this as a pipeline bug. Keyword inheritance is a product policy decision.',
          ));
        } else {
          out.add(AuditMismatch(
            unit: dump.name,
            section: 'Keywords',
            expected: '"${truth.expectedKeywords.firstWhere((k) => k.toLowerCase() == expected)}"',
            observed: 'MISSING from both categoryTokens and keywordTokens',
            errorClass: AuditErrorClass.keywords,
            kind: AuditMismatchKind.missingKeyword,
            severity: AuditErrorSeverity.major,
            likelyStage: AuditPipelineStage.m5Bind,
          ));
        }
      }
    }

    // Check for unexpected single-word tokens that are weapon words polluting keywords
    // (e.g. "ranged", "melee", "weapon", "attacks", "extra")
    const weaponPollutionWords = {
      'ranged', 'melee', 'weapon', 'weapons', 'attacks', 'extra',
      'profile', 'profiles',
    };
    final polluters = observedKeywordTokens
        .intersection(weaponPollutionWords)
        .where((t) => !expectedNormalized.any((e) => e.contains(t)));

    for (final polluter in polluters.toList()..sort()) {
      out.add(AuditMismatch(
        unit: dump.name,
        section: 'Keywords',
        expected: 'NOT in keywords',
        observed: '"$polluter" present in keywordTokens',
        errorClass: AuditErrorClass.keywords,
        kind: AuditMismatchKind.weaponWordsPollutingKeywords,
        severity: AuditErrorSeverity.minor,
        likelyStage: AuditPipelineStage.m9Index,
        notes:
            'Weapon-related words leaking into unit keyword tokens via category tokenization.',
      ));
    }
  }

  void _compareWeapons(
    UnitAuditDump dump,
    UnitGroundTruth truth,
    List<AuditMismatch> out,
  ) {
    final observedByName = <String, WeaponStatDump>{};
    for (final w in dump.weapons) {
      observedByName[w.name.toLowerCase()] = w;
    }

    for (final expected in truth.expectedWeapons) {
      final key = expected.name.toLowerCase();
      final observed = observedByName[key];

      if (observed == null) {
        out.add(AuditMismatch(
          unit: dump.name,
          section: 'Weapons',
          expected: expected.name,
          observed: 'MISSING',
          errorClass: AuditErrorClass.weapons,
          kind: AuditMismatchKind.missingWeapon,
          severity: AuditErrorSeverity.critical,
          likelyStage: AuditPipelineStage.m9Index,
        ));
        continue;
      }

      // Compare stats
      for (final statEntry in expected.stats.entries) {
        final expectedVal = statEntry.value.trim();
        final observedVal = observed.stats[statEntry.key]?.trim();
        if (observedVal == null) {
          out.add(AuditMismatch(
            unit: dump.name,
            section: 'Weapons / ${expected.name}',
            expected: '${statEntry.key} = $expectedVal',
            observed: 'MISSING',
            errorClass: AuditErrorClass.weapons,
            kind: AuditMismatchKind.wrongWeaponStat,
            severity: AuditErrorSeverity.major,
            likelyStage: AuditPipelineStage.m9Index,
          ));
        } else if (observedVal != expectedVal) {
          out.add(AuditMismatch(
            unit: dump.name,
            section: 'Weapons / ${expected.name}',
            expected: '${statEntry.key} = $expectedVal',
            observed: '${statEntry.key} = $observedVal',
            errorClass: AuditErrorClass.weapons,
            kind: AuditMismatchKind.wrongWeaponStat,
            severity: AuditErrorSeverity.major,
            likelyStage: AuditPipelineStage.m9Index,
          ));
        }
      }
    }

    // Check for extra weapons not in ground truth
    final expectedNames =
        truth.expectedWeapons.map((w) => w.name.toLowerCase()).toSet();
    for (final observed in dump.weapons) {
      if (!expectedNames.contains(observed.name.toLowerCase())) {
        out.add(AuditMismatch(
          unit: dump.name,
          section: 'Weapons',
          expected: 'NOT present',
          observed: '"${observed.name}" (${observed.docId})',
          errorClass: AuditErrorClass.weapons,
          kind: AuditMismatchKind.extraWeapon,
          severity: AuditErrorSeverity.minor,
          likelyStage: AuditPipelineStage.m9Index,
          notes:
              'May be a valid option weapon or entryLink-expanded item. '
                  'Policy decision: show all possible vs equipped only.',
        ));
      }
    }
  }

  void _compareRules(
    UnitAuditDump dump,
    UnitGroundTruth truth,
    List<AuditMismatch> out,
  ) {
    final observedByName = <String, RuleDump>{};
    for (final r in dump.rules) {
      observedByName[r.name.toLowerCase()] = r;
    }

    for (final expected in truth.expectedRules) {
      final key = expected.name.toLowerCase();
      final observed = observedByName[key];

      if (observed == null) {
        out.add(AuditMismatch(
          unit: dump.name,
          section: 'Rules',
          expected: expected.name,
          observed: 'MISSING',
          errorClass: AuditErrorClass.rules,
          kind: AuditMismatchKind.missingRule,
          severity: AuditErrorSeverity.major,
          likelyStage: AuditPipelineStage.m9Index,
        ));
        continue;
      }

      // Check description substring if provided
      final subst = expected.descriptionSubstring;
      if (subst != null &&
          !observed.description.toLowerCase().contains(subst.toLowerCase())) {
        out.add(AuditMismatch(
          unit: dump.name,
          section: 'Rules / ${expected.name}',
          expected: 'description contains "$subst"',
          observed: observed.description.length > 100
              ? '${observed.description.substring(0, 100)}...'
              : observed.description,
          errorClass: AuditErrorClass.rules,
          kind: AuditMismatchKind.wrongRuleDescription,
          severity: AuditErrorSeverity.major,
          likelyStage: AuditPipelineStage.m9Index,
        ));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Report formatting
  // ---------------------------------------------------------------------------

  /// Renders the mismatch list as a human-readable comparison table.
  String renderTable(List<AuditMismatch> mismatches) {
    if (mismatches.isEmpty) {
      return '✓ No mismatches detected against ground truth.\n';
    }

    final buf = StringBuffer();
    buf.writeln('AUDIT COMPARISON TABLE');
    buf.writeln('=' * 120);

    // Group by error class
    final byClass = <AuditErrorClass, List<AuditMismatch>>{};
    for (final m in mismatches) {
      byClass.putIfAbsent(m.errorClass, () => []).add(m);
    }

    for (final cls in AuditErrorClass.values) {
      final group = byClass[cls];
      if (group == null || group.isEmpty) continue;

      buf.writeln();
      buf.writeln('--- ${cls.name.toUpperCase()} (${group.length} issues) ---');

      for (final m in group) {
        buf.writeln('  [${m.severity.name.toUpperCase()}] ${m.kind.name}');
        buf.writeln('    Unit    : ${m.unit}');
        buf.writeln('    Section : ${m.section}');
        buf.writeln('    Expected: ${m.expected}');
        buf.writeln('    Observed: ${m.observed}');
        buf.writeln('    Stage   : ${m.likelyStage.name}');
        if (m.notes.isNotEmpty) {
          buf.writeln('    Notes   : ${m.notes}');
        }
        buf.writeln();
      }
    }

    buf.writeln('=' * 120);

    // Separate structural (H-class) from actionable mismatches in summary
    final structural = mismatches
        .where((m) => m.errorClass == AuditErrorClass.structural)
        .toList();
    final actionable = mismatches
        .where((m) => m.errorClass != AuditErrorClass.structural)
        .toList();

    buf.writeln(
        'SUMMARY: ${mismatches.length} total mismatches '
        '(${actionable.length} actionable, ${structural.length} structural)');
    buf.writeln('  Structural (H-class): not bugs — require mapping policy decisions.');

    final bySeverity = <AuditErrorSeverity, int>{};
    for (final m in actionable) {
      bySeverity[m.severity] = (bySeverity[m.severity] ?? 0) + 1;
    }
    for (final sev in AuditErrorSeverity.values) {
      final count = bySeverity[sev] ?? 0;
      if (count > 0) buf.writeln('  ${sev.name}: $count');
    }

    return buf.toString();
  }

  /// Renders a pattern summary (group mismatches by kind across all units).
  String renderPatternSummary(List<AuditMismatch> mismatches) {
    final byKind = <AuditMismatchKind, List<AuditMismatch>>{};
    for (final m in mismatches) {
      byKind.putIfAbsent(m.kind, () => []).add(m);
    }

    final buf = StringBuffer();
    buf.writeln('SYSTEMIC PATTERN SUMMARY');
    buf.writeln('=' * 80);
    buf.writeln('(Sorted by frequency — fix highest-count patterns first)');
    buf.writeln();

    final sorted = byKind.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    for (final entry in sorted) {
      buf.writeln('  ${entry.key.name}: ${entry.value.length} instance(s)');
      final units = entry.value.map((m) => m.unit).toSet().join(', ');
      buf.writeln('    Units affected: $units');
    }

    return buf.toString();
  }
}

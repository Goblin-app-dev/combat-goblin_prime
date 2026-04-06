// ignore_for_file: avoid_print
/// Faction Sweep Validation Test
///
/// Sequential validation of all untested factions from the BSData wh40k-10e repo.
/// Already-tested factions excluded: Space Marines, Tyranids, Leagues of Votann,
/// Agents of the Imperium.
///
/// Run with:
///   flutter test test/faction_sweep_test.dart --concurrency=1 --timeout=300s
///
/// Each faction is validated through phases:
///   P1 — Acquire / dependency check / ingestion sanity
///   P2 — Representative unit inspection (char / infantry / multi-model / special)
///   P3 — V1 query validation (stat, rules, keyword, text search)
///   P4 — Structural difference detection

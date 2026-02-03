# Glossary

This glossary defines all public concepts used in the system.
No implied or informal terminology is allowed.

---

## Gamesystem
A `.gst` file representing the root ruleset context.

## Catalog
A `.cat` file representing a modular data pack loaded under a gamesystem.

## Pack ID
Deterministic identifier for a stored pack directory.

## Raw Pack Bundle
The lossless collection of source files and metadata produced by M1 Acquire.

## Diagnostic
Structured acquisition diagnostics surface; Phase 1A uses empty list by default.

## Dependency Record
Version information for a single dependency catalog; survives raw file deletion for update checking.

## Source Locator
Identifies the upstream source (repo URL, branch) for update checking.

## Pack Manifest
Persisted record of an installed pack containing version tokens for all files; enables update detection after dependency cleanup. Represents content identity and provenance.

## Attempt Status Wrapper
Conceptual workflow state tracking an install attempt (not necessarily a separate type). Distinct from PackManifest. States include: in_progress (M1 succeeded, downstream pending), failed (downstream failed, resumable), completed (manifest persisted, cleanup done), cancelled (user cancelled). Enables crash-resume UX without polluting M1.

## Index (BSData)
Upstream repository manifest (index.bsi / index.xml) that lists available files, versions, and download URLs. Used for dependency resolution and update detection.

## Version Token
Identifier used to detect file changes. Tier 1: index-provided version for cheap checks. Tier 2: SHA-256 fileId for verification after download.

---

Any concept used in code must appear here first.

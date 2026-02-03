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
Persisted record of an installed pack containing version tokens for all files; enables update detection after dependency cleanup.

---

Any concept used in code must appear here first.

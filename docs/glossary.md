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

## Import Dependency
A catalog-to-catalog reference declared via `<catalogueLink targetId="...">` in XML. Represents a required dependency that must be acquired before the referencing catalog can be fully processed.

## Update
The operation of refreshing an installed pack when upstream changes are detected. Definition: delete all pack-associated data (storage + derived) → reacquire all files fresh → reparse → rebind. No incremental reconciliation; always a full reinstall.

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

## Element DTO
Generic representation of any XML element preserving tag name, attributes, child elements, and text content. Document order preserved via ordered child lists.

## Parsed File
A single XML file converted to Element DTO form with source provenance (fileId linking back to raw bytes).

## Parsed Pack Bundle
The complete DTO output for a pack: parsed game system + primary catalog + dependency catalogs. Produced by M2 Parse.

## Parse Failure
Exception thrown when XML parsing fails, with diagnostic context (fileId, sourceIndex, message).

## Node Ref
Strongly-typed handle for node identity within a WrappedFile. Contains nodeIndex. Prevents raw integer indices from leaking outside M3 internals.

## Wrapped Node
Indexed, navigable representation of an XML element with explicit provenance. Contains tag, attributes, text, parent/child references (as NodeRef), depth, and source fileId/fileType. Part of a flat node table in WrappedFile.

## Wrapped File
Per-file node table produced by M3 Wrap. Contains flat list of WrappedNode plus idIndex mapping `id` attribute to List<NodeRef>. No cross-file linking.

## Wrapped Pack Bundle
Complete M3 output for a pack: wrapped game system + primary catalog + dependency catalogs. One-to-one correspondence with ParsedPackBundle. Produced by M3 Wrap.

## Wrap Failure
Exception thrown for structural corruption during M3 wrapping. Not used for duplicate IDs or semantic issues.

## Symbol Table
Cross-file ID registry built by M4 Link. Aggregates idIndex from all WrappedFiles in file resolution order (primaryCatalog → dependencyCatalogs → gameSystem). Maps ID string to list of (fileId, NodeRef) pairs. Lookup returns targets in deterministic order.

## Resolved Ref
Resolution result for a single cross-file reference. Contains sourceFileId, sourceNode (NodeRef), targetId, and list of resolved targets as (fileId, NodeRef) pairs. Targets ordered by file resolution order, then node index within file.

## Link Diagnostic
Non-fatal issue detected during M4 Link resolution. Closed code set: UNRESOLVED_TARGET (targetId not found), DUPLICATE_ID_REFERENCE (targetId found multiple times), INVALID_LINK_FORMAT (missing or empty targetId). Always emitted; never thrown.

## Link Failure
Exception thrown by M4 Link only for corrupted M3 input or internal bugs. In normal operation, no LinkFailure is thrown. Resolution issues are reported via LinkDiagnostic instead.

## Linked Pack Bundle
Complete M4 output for a pack: SymbolTable + resolved references + diagnostics + unchanged WrappedPackBundle reference. Produced by M4 Link (LinkService).

## Link Service
Service that performs cross-file reference resolution. Converts WrappedPackBundle to LinkedPackBundle. Resolves only targetId on link elements (catalogueLink, entryLink, infoLink, categoryLink).

---

Any concept used in code must appear here first.

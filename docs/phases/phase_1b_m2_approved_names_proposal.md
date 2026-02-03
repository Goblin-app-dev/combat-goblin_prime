# Phase 1B — M2 Parse Approved Names (Proposal)

## Purpose
This document proposes the exact internal names (files, classes, fields) needed to implement M2 Parse
without inventing identifiers during coding.

Once approved, these names become authoritative and must be reused exactly.

---

## M2 Scope and Constraints

**Input:** RawPackBundle (from M1)

**Output:** Parsed DTO graph preserving:
- All XML elements and attributes
- Document order (element sequence as declared in source)
- Source provenance (which file each element came from)

**Non-goals for M2:**
- Cross-link resolution (deferred to M3/Phase 2)
- Semantic validation (deferred to later phases)
- Type-specific behavior (all elements treated uniformly)

---

## Design Decision: Generic vs Typed DTOs

**Chosen approach:** Generic element DTOs

**Rationale:**
- Truly lossless: any XML structure preserved without schema knowledge
- Document order preserved naturally via ordered child lists
- No premature commitment to BattleScribe schema details
- Cross-link resolution (which needs typed knowledge) is Phase 2 concern

**Alternative rejected:** Typed DTOs per BattleScribe element type
- Would require exhaustive schema mapping upfront
- Risk of losing unknown/future elements
- Premature interpretation before binding phase

---

## Naming Principles Used
- Suffixes:
  - `*Service` for pure logic
  - `*Dto` for data transfer objects (parsed XML)
  - `*Bundle` for returned collections
- "Id" not "ID"
- Fields are `lowerCamelCase`
- Types are `UpperCamelCase`
- No prohibited IP terms used

---

## Module Public API Barrel
### File
- `lib/modules/m2_parse/m2_parse.dart`

### Barrel Exports (only these are public)
- `services/parse_service.dart`
- `models/parsed_pack_bundle.dart`
- `models/parsed_file.dart`
- `models/element_dto.dart`
- `models/parse_failure.dart`

---

## File & Folder Layout (M2)

Create under:
- `lib/modules/m2_parse/`

```
lib/modules/m2_parse/
├── m2_parse.dart
├── models/
│   ├── parsed_pack_bundle.dart
│   ├── parsed_file.dart
│   ├── element_dto.dart
│   └── parse_failure.dart
└── services/
    └── parse_service.dart
```

---

## Core Types (Proposal — Awaiting Approval)

### ElementDto
**File:** `models/element_dto.dart`

A generic DTO representing any XML element, preserving structure and order.

Fields:
- `String tagName` — XML element tag (e.g., "catalogue", "selectionEntry", "profile")
- `Map<String, String> attributes` — All XML attributes as key-value pairs
- `List<ElementDto> children` — Child elements in document order
- `String? textContent` — Text content if present (null if element has only children)
- `int sourceLineNumber` — Line number in source XML for diagnostics

---

### ParsedFile
**File:** `models/parsed_file.dart`

A parsed XML file with its root element and source provenance.

Fields:
- `String fileId` — SHA-256 from SourceFileMetadata (links back to raw bytes)
- `SourceFileType fileType` — gst or cat
- `String rootId` — Root element's id attribute (from preflight)
- `ElementDto root` — The parsed root element (gameSystem or catalogue)

---

### ParsedPackBundle
**File:** `models/parsed_pack_bundle.dart`

The complete parsed output for a pack.

Fields:
- `String packId` — From RawPackBundle
- `DateTime parsedAt` — When parsing completed
- `ParsedFile gameSystem` — Parsed .gst file
- `ParsedFile primaryCatalog` — Parsed primary .cat file
- `List<ParsedFile> dependencyCatalogs` — Parsed dependency .cat files (document order preserved)

---

### ParseFailure
**File:** `models/parse_failure.dart`

Exception for parse errors with diagnostic context.

Fields:
- `String message` — Human-readable error description
- `String? fileId` — Which file failed (if known)
- `int? lineNumber` — Where in the file (if known)
- `String? details` — Additional context

---

## Services

### ParseService
**File:** `services/parse_service.dart`

Method:
- `Future<ParsedPackBundle> parseBundle({required RawPackBundle rawBundle})`

Behavior:
- Parses each file's bytes into ElementDto tree
- Preserves document order
- Links each ParsedFile back to source via fileId
- Throws ParseFailure on malformed XML

---

## Cross-Module Contract Notes
- M2 consumes `RawPackBundle` only (from M1)
- M2 does NOT consume index, network, or storage directly
- M3 consumes `ParsedPackBundle` only (from M2)
- `ElementDto.tagName` and `attributes["id"]` are used for cross-link resolution in M3

---

## Glossary Additions Required
Before implementation, add to `/docs/glossary.md`:
- **Element DTO** — Generic representation of any XML element preserving tag, attributes, children, and document order
- **Parsed File** — A single XML file converted to DTO form with source provenance
- **Parsed Pack Bundle** — The complete DTO output for a pack (gamesystem + catalogs)

---

## Approval Checklist
- [ ] File layout approved
- [ ] Core model names approved (ElementDto, ParsedFile, ParsedPackBundle, ParseFailure)
- [ ] Service name approved (ParseService)
- [ ] Generic DTO approach approved (vs typed DTOs)
- [ ] Output bundle shape approved

Any change requires explicit approval and documentation update.

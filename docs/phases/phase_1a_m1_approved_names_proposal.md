# Phase 1A — M1 Acquire Approved Names (Proposal)

## Purpose
This document proposes the exact internal names (files, classes, fields) needed to implement M1 Acquire
without inventing identifiers during coding.

Once approved, these names become authoritative and must be reused exactly.

This document uses only generic terms:
- "gamesystem" for `.gst`
- "catalog" for `.cat`

---

## Naming Principles Used
- Suffixes:
  - `*Service` for pure logic
  - `*Repository` for persistence abstraction
  - `*Result` / `*Bundle` for returned values
  - `*Metadata` for metadata records
- “Id” not “ID”
- Fields are `lowerCamelCase`
- Types are `UpperCamelCase`
- No prohibited IP terms used

---

## Module Public API Barrel
### File
- `lib/modules/m1_acquire/m1_acquire.dart`

### Barrel Exports (only these are public)
- `services/acquire_service.dart`
- `models/raw_pack_bundle.dart`
- `models/source_file_type.dart`
- `models/source_file_metadata.dart`
- `models/preflight_scan_result.dart`
- `models/import_dependency.dart`
- `models/acquire_failure.dart`

---

## File & Folder Layout (M1)

Create under:
- `lib/modules/m1_acquire/`



lib/modules/m1_acquire/
├── m1_acquire.dart
├── models/
│ ├── raw_pack_bundle.dart
│ ├── source_file_type.dart
│ ├── source_file_metadata.dart
│ ├── preflight_scan_result.dart
│ ├── import_dependency.dart
│ └── acquire_failure.dart
├── services/
│ ├── acquire_service.dart
│ └── preflight_scan_service.dart
└── storage/
└── acquire_storage.dart


---

## Core Types (Authoritative)

### SourceFileType
**File:** `models/source_file_type.dart`

Enum values:
- `gst`
- `cat`

---

### SourceFileMetadata
**File:** `models/source_file_metadata.dart`

Fields:
- `String fileId`
- `SourceFileType fileType`
- `String externalFileName`
- `String storedPath`
- `int byteLength`
- `DateTime importedAt`

---

### ImportDependency
**File:** `models/import_dependency.dart`

Fields:
- `String targetId`
- `bool importRootEntries`

---

### PreflightScanResult
**File:** `models/preflight_scan_result.dart`

Fields:
- `SourceFileType fileType`
- `String rootTag`
- `String rootId`
- `String? rootName`
- `String? rootRevision`
- `String? rootType`
- `String? declaredGameSystemId`
- `String? declaredGameSystemRevision`
- `String? libraryFlag`
- `List<ImportDependency> importDependencies`

---

### RawPackBundle
**File:** `models/raw_pack_bundle.dart`

Fields:
- `String packId`
- `DateTime createdAt`

- `SourceFileMetadata gameSystemMetadata`
- `PreflightScanResult gameSystemPreflight`
- `List<int> gameSystemBytes`

- `SourceFileMetadata primaryCatalogMetadata`
- `PreflightScanResult primaryCatalogPreflight`
- `List<int> primaryCatalogBytes`

- `List<SourceFileMetadata> dependencyCatalogMetadatas`
- `List<PreflightScanResult> dependencyCatalogPreflights`
- `List<List<int>> dependencyCatalogBytesList`

- `List<Diagnostic> acquireDiagnostics`

---

### AcquireFailure
**File:** `models/acquire_failure.dart`

Fields:
- `String message`
- `String? details`

---

## Services

### PreflightScanService
**File:** `services/preflight_scan_service.dart`

Method:
- `Future<PreflightScanResult> scanBytes({required List<int> bytes, required SourceFileType fileType})`

---

### AcquireStorage
**File:** `storage/acquire_storage.dart`

Methods:
- `Future<SourceFileMetadata> storeFile({required List<int> bytes, required SourceFileType fileType, required String externalFileName, required String rootId, required String fileExtension})`
- `Future<void> deleteCachedGameSystem()`
- `Future<SourceFileMetadata?> readCachedGameSystemMetadata()`
- `Future<List<int>?> readCachedGameSystemBytes()`

---

### AcquireService
**File:** `services/acquire_service.dart`

Method:
- `Future<RawPackBundle> buildBundle({required List<int> gameSystemBytes, required String gameSystemExternalFileName, required List<int> primaryCatalogBytes, required String primaryCatalogExternalFileName, required Future<List<int>?> Function(String missingTargetId) requestDependencyBytes})`

---

## Cross-Module Contract Notes
- M2 consumes `RawPackBundle` only.
- M3 nodes must be able to surface `SourceFileMetadata.fileId` and `SourceFileType`.

---

## Approval Checklist
- [x] File layout approved
- [x] Core model names approved
- [x] Service names approved
- [x] Output bundle shape approved

Any change requires explicit approval and documentation update.

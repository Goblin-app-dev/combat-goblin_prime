# Module IO Registry

## Purpose
Defines explicit inputs and outputs for every module.
Required for phase freeze validation.

---

## M1 Acquire

### Inputs
- User-selected file bytes (gameSystem .gst, primaryCatalog .cat)
- Dependency catalog bytes (via requestDependencyBytes callback)
- SourceLocator (upstream source identification)
- Cached gamesystem state

### Outputs
- RawPackBundle containing:
  - Raw bytes for all files (lossless)
  - Preflight scan results (metadata)
  - Storage metadata (paths, fileIds)
  - PackManifest (for update checking)

### Storage Contracts
- AcquireStorage.storeFile(..., packId)

### Error Contracts
- AcquireFailure with missingTargetIds list (actionable for UI)

---

## Index Reader (Future — Phase 1B+)

Reads and caches the upstream repository index for dependency resolution and update checking.

### Inputs
- SourceLocator (repo URL, branch)
- Cached index state (if available)

### Outputs
- Mapping: rootId → { downloadUrl, versionToken }
- Cache metadata (lastRefreshed, httpETag)

### Behavior
- Parses index.bsi / index.xml from BSData repository
- Provides lookup: given rootId, returns download URL and version token
- Caches parsed index locally with HTTP caching tokens (ETag/Last-Modified)
- Refresh strategy: conditional request (returns "not modified" if unchanged)

### Side Effects
- Writes cached index to local storage

### Stored Artifacts
- Cached index file with timestamp and caching tokens

---

## Downloader (Future — Phase 1B+)

Fetches file bytes from remote URLs.

### Inputs
- Download URL (from Index Reader lookup)

### Outputs
- Raw bytes (List<int>)
- HTTP response metadata (status, headers)

### Behavior
- Performs HTTP GET request
- Returns bytes on success, structured error on failure
- No interpretation of content; bytes passed to M1 Acquire

### Side Effects
- Network I/O only; no local storage

---

## Orchestrator (Future — Phase 1B+)

Coordinates the full acquire → parse → bind workflow and manages attempt state.

### Inputs
- User selection (primary catalog rootId)
- SourceLocator
- Cached game system state

### Outputs
- Workflow completion status
- Persisted PackManifest (only after downstream success)

### Responsibilities
- Calls M1 Acquire with user-selected files
- When M1 throws AcquireFailure(missingTargetIds):
  - Returns structured result to UI with complete list of missing dependencies
  - Does NOT fail silently on first missing dependency
- After dependencies downloaded:
  - Re-calls M1 Acquire until RawPackBundle produced
- After downstream parse/bind success:
  - Persists PackManifest (installed record)
  - Triggers cleanup of raw dependency files
- Maintains attempt status wrapper for crash-resume UX

### Attempt Status Wrapper
Conceptual workflow state (not necessarily a separate type):
- in_progress: M1 succeeded, downstream pending
- failed: downstream failed, resumable
- completed: manifest persisted, cleanup done
- cancelled: user cancelled

This is distinct from PackManifest, which is content identity + provenance.

### Side Effects
- Persists installed PackManifest
- Deletes raw dependency files after success

---

## Cleanup (Future — Phase 1B+)

Deletes raw dependency files after downstream success.

### Inputs
- packId
- List of dependency file paths

### Outputs
- Confirmation of deletion

### Behavior
- Only executes after:
  - Parse succeeded
  - Bind succeeded
  - PackManifest persisted
- Deletes only dependency catalog raw files scoped to packId
- Primary catalog and game system files may be retained (configurable)

### Constraints
- NEVER deletes anything until install success confirmed
- Deletion narrowly scoped to packId-owned paths

---

## Update Checker (Future — Phase 1B+)

Detects upstream changes and orchestrates re-acquisition.

### Inputs
- Persisted PackManifest records
- Refreshed index from Index Reader

### Outputs
- List of packs with updates available
- Update execution status

### Boot-time Behavior
- On boot: conditional refresh of index (ETag/Last-Modified)
- If offline/unavailable: use cached index, surface "update check unavailable" state
- Compare remote version tokens against stored PackManifest values for:
  - Game system
  - Primary catalog
  - Each dependency catalog
- If any changed: mark pack "update available"

### Update Execution
When user accepts update:
1. Delete all pack-associated data (storage + derived)
2. Re-acquire using stored selection (primary rootId) + SourceLocator
3. Run downstream parse/bind pipeline
4. Persist new PackManifest
5. Cleanup raw dependency files

### Definition of "Update"
Update = delete all derived data + reacquire all files fresh.
No incremental reconciliation in initial implementation.

### Version Token Strategy
- Tier 1 (check): index version token for cheap comparison
- Tier 2 (verify): SHA-256 fileId after download

---

Modules may not access data outside their declared IO.

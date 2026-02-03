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

## Pack Manager (Future)

### Inputs
- RawPackBundle from M1 Acquire

### Outputs
- Persisted PackManifest (after downstream success)

### Responsibilities
- Orchestrates acquire → parse → bind flow
- Persists manifest after downstream success
- Handles cleanup on failure

---

## Update Service (Future)

### Inputs
- Persisted PackManifest records
- BSData repository index

### Outputs
- Update availability status per pack

### Responsibilities
- Check upstream for file changes
- Compare version tokens (git blob SHA, fileId)
- Trigger re-acquisition when updates detected

---

Modules may not access data outside their declared IO.

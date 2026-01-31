# Module IO Registry

## Purpose
Defines explicit inputs and outputs for every module.
Required for phase freeze validation.

---

## M1 Acquire

### Inputs
- User-selected file bytes
- Cached gamesystem state

### Outputs
- RawPackBundle
### Storage Contracts
- AcquireStorage.storeFile(..., packId)
  - `gst`: `appDataRoot/gamesystem_cache/{rootId}/{fileId}.{ext}`
  - `cat`: `appDataRoot/packs/{packId}/catalogs/{rootId}/{fileId}.{ext}`

---

Modules may not access data outside their declared IO.

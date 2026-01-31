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

---

Modules may not access data outside their declared IO.

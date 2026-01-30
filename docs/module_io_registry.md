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

---

Modules may not access data outside their declared IO.

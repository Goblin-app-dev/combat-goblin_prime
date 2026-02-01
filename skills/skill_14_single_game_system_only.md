# Skill 14 — Single Game System Only

## Rule
At any time, the app may contain only one game system. Importing a different game system is invalid and must fail unless all existing stored data has been deleted.

## Applies To
- Acquisition
- Storage
- Import validation

## Prohibited
- Multiple game systems stored concurrently
- Importing a different game system without clearing existing stored data

## Rationale
A single active game system prevents cross-system corruption and enforces deterministic, unambiguous data ownership.

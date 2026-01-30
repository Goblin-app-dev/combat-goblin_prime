# Skill 06 — Module Boundary Integrity

## Rule
Each module may only access its declared inputs.

## Prohibitions
- UI touching DTOs or Nodes
- Query resolving links
- Binding leaking into UI
- Side-channel data flow

## Enforcement
All data must flow through documented module inputs/outputs.

Violations invalidate the change.

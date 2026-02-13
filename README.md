# Combat Goblin Prime

A deterministic, multi-phase data pipeline engine built with Flutter/Dart for processing structured game system data.

## Overview

Combat Goblin Prime is a voice-driven assistant backend that transforms raw XML source data into queryable, evaluated game state. The system emphasizes:

- **Determinism**: Same input always produces identical output
- **Lossless preservation**: Source data is never silently modified
- **Explicit data flow**: Clear module boundaries and typed interfaces
- **Phase freeze discipline**: Validated phases are locked from modification

## Architecture

The system is organized into numbered modules (M1-M9+) that form a pipeline:

```
Source Files → M1 Acquire → M2 Parse → M3 Wrap → M4 Link → M5 Bind → M6 Evaluate
                                                                    ↓
                                              ← M8 Modifiers ← M7 Applicability
                                                      ↓
                                               Orchestrator → M9 Index
```

### Module Summary

| Module | Name | Phase | Purpose |
|--------|------|-------|---------|
| M1 | Acquire | 1A | File selection, validation, raw bundle creation |
| M2 | Parse | 1B | XML to DTO conversion, structure preservation |
| M3 | Wrap | 1C | Node identity and provenance assignment |
| M4 | Link | 2 | Cross-file reference resolution |
| M5 | Bind | 3 | Semantic interpretation, typed entities |
| M6 | Evaluate | 4 | Constraint evaluation against selections |
| M7 | Applicability | 5 | Condition evaluation (tri-state: applies/skipped/unknown) |
| M8 | Modifiers | 6 | Value modification operations |
| M9 | Index | - | Search-ready document generation |
| Orchestrator | - | - | Coordinates M6/M7/M8 evaluation flow |

## Prerequisites

- Flutter SDK 3.0.0+
- Dart SDK 3.0.0+

## Setup

```bash
# Clone the repository
git clone <repo-url>
cd combat-goblin_prime

# Get dependencies
flutter pub get
```

## Running Tests

```bash
# Run all tests
flutter test

# Run tests for a specific module
flutter test test/modules/m1_acquire/
flutter test test/modules/m6_evaluate/

# Run pipeline integration tests
flutter test test/pipeline/
```

## Project Structure

```
lib/
├── main.dart              # Flutter app entry point
└── modules/
    ├── m1_acquire/        # Source file acquisition
    ├── m2_parse/          # XML parsing to DTOs
    ├── m3_wrap/           # Node wrapping with identity
    ├── m4_link/           # Cross-file linking
    ├── m5_bind/           # Semantic binding
    ├── m6_evaluate/       # Constraint evaluation
    ├── m7_applicability/  # Condition evaluation
    ├── m8_modifiers/      # Value modification
    ├── m9_index/          # Search index generation
    └── orchestrator/      # Evaluation coordination

docs/
├── design.md              # System design overview
├── glossary.md            # Term definitions
├── module_io_registry.md  # Module input/output contracts
├── naming_contract.md     # Naming conventions
├── name_change_log.md     # Name change history
└── phases/                # Per-phase design and naming proposals

skills/                    # Development discipline rules

test/
├── modules/               # Unit tests per module
└── pipeline/              # Integration tests
```

## Documentation Index

### Start Here
- [System Design Overview](docs/design.md)
- [Glossary](docs/glossary.md)

### Module Contracts
- [Module I/O Registry](docs/module_io_registry.md) - Input/output types for each module

### Naming & Discipline
- [Naming Contract](docs/naming_contract.md)
- [Name Change Log](docs/name_change_log.md)
- [Skills (Development Rules)](skills/README.md)

### Phase Documentation
Design proposals and approved names for each phase are in `docs/phases/`:
- Phase 1A (M1 Acquire): `phase_1a_m1_*`
- Phase 1B (M2 Parse): `phase_1b_m2_*`
- Phase 1C (M3 Wrap): `phase_1c_m3_*`
- Phase 2 (M4 Link): `phase_2_m4_*`
- Phase 3 (M5 Bind): `phase_3_m5_*`
- Phase 4 (M6 Evaluate): `phase_4_m6_*`
- Phase 5 (M7 Applicability): `phase_5_m7_*`
- Phase 6 (M8 Modifiers): `phase_6_m8_*`
- M9 Index: `m9_index_core_names_proposal.md`
- Orchestrator: `orchestrator_v1_names_proposal.md`

### Reference
- [BSD Parsing Reference](docs/bsd-parsing-reference.md)

## Development Principles

This project follows strict development disciplines defined in the `skills/` directory:

1. **Read before write** - Understand existing code before changing it
2. **Single source of truth** - Names are defined in documentation first
3. **No silent renames** - All name changes must be logged
4. **Phase freeze discipline** - Frozen modules cannot change without approval
5. **Deterministic behavior** - Same input must produce same output
6. **Module boundary integrity** - No cross-module data leaks

See [Skills README](skills/README.md) for the complete behavioral contract.

## License

Proprietary - All rights reserved.

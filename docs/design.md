# System Design Overview

## Purpose
This system is a voice-driven assistant built on a deterministic, multi-phase data pipeline.

The pipeline is designed to:
- preserve source data losslessly
- defer interpretation as long as possible
- allow strict freezing between phases
- support explainable answers later

---

## Architecture Overview

The system is divided into phases, each containing one or more modules.

Each phase:
- has strict responsibilities
- produces defined outputs
- may be frozen once validated

---

## Phase 1 — Source Ingestion & Preservation

### M1 — Acquire
- Responsible for file selection, validation, and persistence
- Produces a raw, lossless bundle
- Performs no semantic interpretation

### M2 — DTO Construction
- Converts raw XML into DTOs
- Preserves structure and document order
- Performs no cross-file binding

### M3 — Node Wrapping
- Wraps DTOs with identity and provenance
- Still performs no semantic resolution

---

## Phase 2 — Binding & Resolution
- Cross-file linking
- TargetId resolution
- Semantic interpretation

---

## Core Principles
- Determinism: same input → same output
- Lossless source preservation
- Explicit data flow
- Freeze discipline

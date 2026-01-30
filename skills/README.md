# Skills — Coding Discipline for Combat Goblin

## Purpose
The skills in this directory define the **behavioral contract** for anyone
(human or AI) working on this repository.

They are not guidelines.
They are **rules of operation**.

Together, these skills enforce:
- naming stability
- deterministic behavior
- clean module boundaries
- safe phase freezing
- documentation-first design

Failure to follow these skills invalidates a change, regardless of intent.

---

## How the Skills Work Together

### 1. Docs First, Code Second
Skills 01, 02, 03, and 13 form a single rule cluster:

- **Skill 01 — Read Before Write**
  - You must read existing code and docs before acting.

- **Skill 02 — Single Source of Truth for Names**
  - Names exist in one authoritative place.

- **Skill 03 — No New Names Without Permission**
  - You may not invent identifiers.

- **Skill 13 — Naming Docs Are Authoritative**
  - New or changed names must be written to docs *before* code.

**Resulting workflow (mandatory):**



Design intent
↓
Naming docs updated (glossary / name log)
↓
Explicit approval
↓
Code written using approved names


Reverse order is forbidden.

---

### 2. No Drift, Ever
Skills 04 and 08 protect against silent breakage:

- **Skill 04 — No Silent Renames**
  - Renaming is a breaking change and must be logged.

- **Skill 08 — Phase Freeze Discipline**
  - Frozen modules cannot change without approval.

This prevents:
- API drift
- “small cleanups” that break downstream modules
- erosion of frozen guarantees

---

### 3. Mechanical Safety Nets
Skills 05, 07, and the name audit tool enforce discipline mechanically:

- **Skill 05 — Full File Output Only**
  - Prevents copy/paste and context loss.

- **Skill 07 — Module IO Accountability**
  - Prevents hidden data flow and leaky abstractions.

- **`/tools/name_audit.md`**
  - Ensures every change explicitly checks naming, IO, and documentation updates.

No change is “done” until the audit is complete.

---

### 4. Determinism and Debuggability
Skills 10 and 11 ensure the system is trustworthy:

- **Skill 10 — Deterministic Behavior**
  - Same input → same output.

- **Skill 11 — Debug Visibility**
  - Failures must be explainable, not silent.

This makes:
- diagnostics reliable
- freezes meaningful
- bugs reproducible

---

### 5. Stop When Unsure
Skill 12 is the final guardrail:

- **Skill 12 — Stop When Uncertain**
  - If you don’t know the correct name, boundary, or behavior, STOP.

Asking a question is always cheaper than repairing broken architecture.

---

## Enforcement Summary
A change is invalid if it:
- introduces a name not in docs
- updates code without updating naming docs
- renames silently
- crosses module boundaries
- violates freeze rules
- omits full file outputs
- skips the name audit checklist

These skills exist to make the system:
**clean, elegant, stable, and safe**.

Follow them exactly.

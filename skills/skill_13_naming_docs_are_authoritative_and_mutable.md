# Skill 13 — Naming Docs Are Authoritative and Mutated Explicitly

## Rule
All new or changed public names MUST be recorded in the naming documentation
before or at the same time as code is written.

The authoritative naming documents are:
- `/docs/naming_contract.md`
- `/docs/glossary.md`
- `/docs/name_change_log.md` (for renames or deprecations)

Code MUST NOT be the first place a new public name appears.

---

## When This Skill Applies
This skill applies whenever a coder proposes:
- a new file
- a new class, enum, or public type
- a new public method or field
- a new module-level concept
- a rename or semantic change to an existing name

---

## Required Actions

### For a New Name
Before implementation, the coder must:
1. Propose the name
2. Add it to:
   - `/docs/glossary.md` (definition + intent)
3. Confirm approval
4. Only then write code using that name

### For a Rename or Semantic Change
The coder must:
1. Propose the change
2. Update `/docs/name_change_log.md`
3. Update `/docs/glossary.md` if meaning changes
4. Obtain approval
5. Apply the change consistently across the repo

---

## Prohibited Behavior
- Introducing a new public name only in code
- Updating code without updating naming docs
- Treating naming docs as “informational” instead of authoritative
- Retroactively documenting names after implementation

---

## Rationale
The naming documents are the single source of truth for shared language.
If they are not updated first, drift is inevitable.

Names are part of the API.
APIs must be designed deliberately, not discovered accidentally.

---

## Enforcement
Any change that introduces or alters a public name
without a corresponding documentation update
is considered invalid and incomplete.

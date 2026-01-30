# Skill 02 — Single Source of Truth for Names

## Rule
Every public name exists in exactly one authoritative location.

Once a name exists:
- It is immutable unless explicitly approved
- It must be reused exactly
- It must be imported, not retyped

## Applies To
- Files
- Classes
- Methods
- Fields
- Providers
- Tables / columns
- Enums / enum values

## Prohibited Behavior
- Creating near-duplicate names
- “Improving” naming
- Alias-style renames

## Enforcement
If a name does not exist in code or approved docs, it must not be used.

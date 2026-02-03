# BattleScribe Data (BSD) Parsing Reference

## Design Philosophy

**Lossless paradigm**: All data from BSD files must be preserved and searchable, but provide convenient access patterns for player-expected data.

### What Players Expect to Access
- Unit stat lines (M, T, SV, W, LD, OC)
- Weapon profiles (Range, A, BS/WS, S, AP, D, Keywords)
- Abilities/rules text
- Keywords & categories
- Points costs
- Army/faction rules

---

## File Types

| Extension | Type | Purpose |
|-----------|------|---------|
| `.gst/.gstz` | Game System | Root catalogue, defines `gameSystemId` |
| `.cat/.catz` | Catalogue | Templates for roster building |
| `.ros/.rosz` | Roster | Final army list output |
| `index.xml/.bsi` | Index | Manifest for data distribution |
| `.bsr` | Repository | Zip archive with index + catalogues |

All files are XML, with `z` variants being zip-compressed.

**Hierarchy:**
```
.gst (Game System) ← root, defines gameSystemId
  └── .cat (Catalogues) ← reference the gst
        └── .ros (Rosters) ← output, actual army lists
```

---

## Catalogue Structure

```
Catalogue
├── Cost Types (pts, PL, etc.)
├── Profile Types → Characteristic Types (column definitions)
├── Category Entries (Infantry, HQ, Battleline, etc.)
├── Force Entries (Detachments/battalions)
├── Shared Lists
│   ├── Shared Selection Entries (SSE)
│   ├── Shared Selection Entry Groups (SSEG)
│   ├── Shared Profiles (SP)
│   └── Shared Rules (SR)
└── Root Selection Entries
```

---

## Core Entities

### Selection Entry (SE)
The fundamental building block - represents units, models, upgrades.

**Children:** SEs, SEGs, Entry Links, Profiles, Rules, Info Links, Constraints, Modifiers, Category Links, Costs

**Properties:**
- Basics (id, name)
- Reference (book, page)
- Hidden
- Collective
- Type: `upgrade` | `model` | `unit`

### Selection Entry Group (SEG)
Groups SEs with shared constraints or for visual grouping.

**Same children and properties as SE**, plus:
- Default Selection (optional reference to child SE for auto-selection)

### Profile
Named list of characteristics (stat block row).

**Children:** Characteristics, Modifiers

**Key property:** `typeId` / `typeName` identifies the profile type

### Profile Type
Defines columns (characteristic types) for profiles. Multiple profiles with same type display as a table.

### Rule
Multi-line text entity - the **only** entity guaranteed to preserve line breaks.

**Properties:** Basics, Reference, Hidden, Description (the actual rule text)

### Category Entry
Tag-like entities for organizing/filtering. Can be condition targets.

**Important:** Primary category determines where entry appears in roster editor.

### Force Entry
Represents detachments/battalions. All selections within must originate from single catalogue.

---

## Links

### Entry Link
Reference to shared SE or SEG. Target must be from shared lists in same catalogue (or imported game system).

**Children:** Constraints, Modifiers, Category Links

### Info Link
Reference to shared Profile or Rule.

**Children:** Modifiers

### Category Link
Assigns parent entity to categories. Not directly visible - part of parent's properties.

**Important:** `primary` flag determines display category in roster editor.

---

## Constraints

Represent limits (min/max) on selections.

**Properties:**
- `type`: `min` | `max`
- `value`: integral bound (inclusive)
- `percentage`: if true, value is percentage

**Query properties:**
- `field`: what to sum (`selections` or a cost type)
- `scope`: `parent` | `roster` | `force` | `primary category` | ancestor type
- `shared`: sum all instances in roster vs. per-link-instance
- `includeChildSelections`: sum descendants or just scope's field
- `includeChildForces`: include descendant forces

---

## Modifiers

Change properties of parent or parent's constraints. Can be conditional or repeating.

**Types:**
- `increment` - increase numerical field by value
- `decrement` - decrease numerical field by value
- `set` - set field to value
- `append` - append text to field (space added implicitly)

**Children:** Conditions, Condition Groups, Repeats

---

## Conditions

Prerequisites for modifiers.

**Comparison types:**
- `lessThan`, `greaterThan`, `equalTo`, `atLeast`, `atMost`
- `instanceOf`, `notInstanceOf` (for ancestor scope)

**Query:** Same structure as constraints (field, scope, filters)

### Condition Groups
Apply AND/OR logic to multiple conditions. Can be nested.

---

## Repeats

Like conditions, but cause modifier to apply multiple times.

**Properties:**
- `repeats`: number of times to apply per match
- Same query structure as conditions

---

## Special Behaviors

### Collective

Two behaviors:

**1. Display Grouping**
When all children of an entry are collective → collapse into single line item:
```
Without collective:          With collective:
├── Soldier                  └── 5x Soldier
│   └── Gun, Knife               └── 5x Gun, 5x Knife
├── Soldier
│   └── Gun, Knife
...
```

**2. Synchronized Selection**
Collective entries must have identical selections across all sibling instances sharing a parent:
```
Ninja Squad
├── Ninja → selects Climbing Claws
├── Ninja → automatically gets Climbing Claws
└── Ninja → automatically gets Climbing Claws
```

**Danger:** Collective propagates up through shared parents. Marking wrong level as collective syncs across entire force.

### Default Selections via Constraints

Pattern for default equipment:
```
Commander Wargear (2-4)
├── max 4 Selections in Parent
├── min 2 Selections in Parent
└── Ranged Weapons
    ├── Burst cannon
    │   ├── min 1 Selections in Parent  ← forces default
    │   └── [modifier] set min to 0     ← relaxes constraint
    ├── Missile pod
    │   ├── min 1 Selections in Parent  ← forces default
    │   └── [modifier] set min to 0     ← relaxes constraint
    └── (other weapons - no min constraint)
```

BattleScribe auto-selects items with `min >= 1`, then modifiers relax constraints so player can swap.

---

## Roster JSON Structure (Output Format)

From NewRecruit/BattleScribe exports:

```json
{
  "roster": {
    "name": "...",
    "costs": [{"name": "pts", "typeId": "...", "value": 80}],
    "costLimits": [...],
    "forces": [{
      "selections": [{
        "type": "unit|model|upgrade",
        "name": "...",
        "number": 1,
        "categories": [{"name": "Infantry", "primary": true}],
        "profiles": [{
          "typeName": "Unit|Abilities|Ranged Weapons|Melee Weapons",
          "characteristics": [{"name": "M", "$text": "6\""}]
        }],
        "rules": [{"name": "...", "description": "..."}],
        "selections": [/* nested */],
        "costs": [...]
      }]
    }]
  }
}
```

### Profile Type → Characteristic Index Mapping (40k 10th Ed)

**Unit Profile:**
| Index | Stat |
|-------|------|
| 0 | M (Movement) |
| 1 | T (Toughness) |
| 2 | SV (Save) |
| 3 | W (Wounds) |
| 4 | LD (Leadership) |
| 5 | OC (Objective Control) |

**Ranged Weapons:**
| Index | Stat |
|-------|------|
| 0 | Range |
| 1 | A (Attacks) |
| 2 | BS (Ballistic Skill) |
| 3 | S (Strength) |
| 4 | AP |
| 5 | D (Damage) |
| 6 | Keywords |

**Melee Weapons:**
| Index | Stat |
|-------|------|
| 0 | Range ("Melee") |
| 1 | A (Attacks) |
| 2 | WS (Weapon Skill) |
| 3 | S (Strength) |
| 4 | AP |
| 5 | D (Damage) |
| 6 | Keywords |

---

## Catalogue Authoring Guidelines

1. **Consistency** - Match conventions of other catalogues in same game system
2. **Permissive > Restrictive** - Allow illegal builds rather than block legal ones
3. **Simplicity** - Use defaults, descriptive group names like `"Weapons - choose 2"`

**Implication:** Don't assume catalogue enforces all game rules perfectly.

---

## Common Traversal Patterns

### Finding Units in Roster
```
roster.forces[0].selections.forEach(selection => {
  if (selection.type === "model")
    // extract directly
  else if (selection.type === "unit")
    // dig into selection.selections for models
})
```

### Finding Profiles by Type
```
selection.profiles.filter(p => p.typeName === "Unit")      // stat lines
selection.profiles.filter(p => p.typeName === "Abilities") // abilities
selection.profiles.filter(p => p.typeName.includes("Weapons")) // weapons
```

### Recursive Selection Search
```
function findInSelections(selections, predicate) {
  for (const sel of selections) {
    if (predicate(sel)) yield sel;
    if (sel.selections) yield* findInSelections(sel.selections, predicate);
  }
}
```

### Extracting Rules (Deduplicated)
```
function collectRules(selections, seen = new Set()) {
  for (const sel of selections) {
    for (const rule of sel.rules ?? []) {
      if (!seen.has(rule.name)) {
        seen.add(rule.name);
        yield rule;
      }
    }
    if (sel.selections) yield* collectRules(sel.selections, seen);
  }
}
```

---

## Key IDs and References

- `id` - Unique identifier for the entity
- `entryId` - References the source entry (often compound: `parent::child::grandchild`)
- `typeId` - References a type definition (cost type, profile type, characteristic type)
- `catalogueId` - Which catalogue this came from
- `gameSystemId` - Root game system identifier

---

## Notes

- Characteristics are always stored as text, even if numeric (parsed only during modification)
- Rule entity is the only one guaranteed to preserve line breaks
- Hidden entries cause errors if selected - typically toggled via modifiers
- Shared entries from game system are imported read-only into catalogues

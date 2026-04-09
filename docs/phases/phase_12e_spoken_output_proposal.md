# Combat Goblin Prime — Phase 12E Voice Usability Design Guide

## Purpose

This document is the implementation guide for Phase 12E.

It is written for the coder and the project manager to ensure the remaining voice work is completed:

- in the correct layer
- in the correct sequence
- without reopening solved pipeline/index problems
- in full compliance with the project skills, freeze rules, naming rules, and design constraints

Phase 12E is the final major implementation phase required before the app can be considered a usable voice beta.

---

## 1. Current Project Status

The following are already validated and should be treated as settled unless new evidence proves otherwise:

**Pipeline / data status**

- M1 Acquire: complete
- M2 Parse: complete
- M3 Wrap: complete
- M4 Link: complete
- M5 Bind: complete
- M9 Index: complete
- M10 Structured Search: complete

**Validation status**

- all available BSData factions tested across the accessible repo
- no ingestion failures
- no structural pipeline defects
- no faction-specific indexing dependency
- cross-faction behavior validated

**Answer-layer status**

Implemented / validated:

- canonical name resolver is wired into the coordinator
- deterministic post-search entity quality filtering is in place
- coordinator resolves weapon-backed attributes correctly when the query is specific enough
- ambiguity handling exists for key multi-result cases

Remaining gaps for voice beta:

- spoken answer quality
- short voice-friendly clarification prompts
- broader coverage of spoken query shapes
- movement phrasing support
- plural weapon-stat phrasing support
- rules query answer assembly
- runtime TTS/STT validation on device or emulator

---

## 2. Phase 12E Goal

Phase 12E exists to make the app genuinely usable as a voice-first reference tool.

The goal is **not** to improve data correctness.
The goal is **not** to redesign search.
The goal is **not** to add fuzzy search.
The goal is **not** to add rules-engine behavior.

The goal is:

> Given a natural spoken question, the app should resolve the correct entity or request clarification, then speak a concise, correct, natural answer.

---

## 3. Binding Skills, Rules, and Design Constraints

This section is not optional. All Phase 12E work must comply with the project rules already established in the repo.

### Skill 01 — Read existing code and docs before any change

Before any Phase 12E implementation change, the coder must inspect the current implementation path end-to-end.

Minimum required files to re-read before changes:

- `docs/design.md`
- `docs/handoff/02_skills_and_rules_reference.md`
- `docs/handoff/03_ui_development_plan.md`
- `docs/module_io_registry.md`
- `docs/naming_contract.md`
- `docs/glossary.md`
- `lib/voice/understanding/voice_assistant_coordinator.dart`
- current canonicalization / resolver files
- current spoken response plan / player files
- current voice tests

### Skill 02 — Single source of truth for names

All existing approved names must be reused exactly.
Do not invent new public type names casually.

### Skill 03 — No new names without explicit approval

If a new public name is required for Phase 12E, stop and present:

- need
- proposed name
- scope
- alternatives

### Skill 04 — Renames require approval and name logging

Do not silently rename coordinator concepts, spoken plan concepts, or existing public voice-layer names.

### Skill 05 — Full-file outputs only

All changed files must be produced in full.

### Skill 06 — Module boundary integrity

- Do not move logic down into M9/M10 to solve answer-layer behavior.
- Do not pull answer assembly into UI code.
- Do not bypass the coordinator.

### Skill 07 — Module IO accountability

Any new public data passed between answer-layer components must respect declared module boundaries and be documented if public.

### Skill 08 — Frozen phase discipline

M1–M10 and the orchestrator are effectively frozen unless a proven regression is found.
Phase 12E should not reopen M9/M10 unless the coder proves a current live defect in those layers.

### Skill 09 — IP / terminology guardrail

Do not introduce prohibited copyrighted tabletop IP terms into code or docs unless allowed by existing project rules for external filenames.

### Skill 10 — Deterministic behavior

- Same input must produce same output.
- No hidden stochastic choice.
- No probabilistic ranking.
- No broad fuzzy search.

### Skill 11 — Debug visibility

All important answer-layer branches should remain diagnosable. Silent fallthrough behavior is not acceptable.

### Skill 12 — Stop when uncertain

If the coder is uncertain whether a change belongs in the coordinator, canonicalizer, spoken plan layer, or tests, stop and ask.

### Skill 13 — Naming docs authoritative and mutable

If new public names are approved, update `glossary.md` and, if applicable, `name_change_log.md` before code is considered final.

### Skill 14 — Single game system only

Do not introduce assumptions that require multi-game-system behavior.

---

## 4. Architectural Reality for Phase 12E

This is the most important framing rule.

### 4.1 What Phase 12E is NOT

Phase 12E is not:

- a pipeline phase
- an indexing phase
- a UI formatting phase
- a search-engine redesign
- a rules-engine phase

### 4.2 What Phase 12E IS

Phase 12E is:

- answer assembly
- voice-friendly clarification
- bounded query-shape interpretation
- spoken response planning
- spoken runtime validation

### 4.3 Current correct flow

The intended voice flow should remain:

1. Speech-to-text produces transcript
2. Domain canonicalization cleans transcript
3. Canonical name resolution normalizes user-facing names to BSData-facing names
4. Voice assistant coordinator determines query type and required data path
5. If unambiguous, answer is assembled
6. If ambiguous, clarification prompt is assembled
7. Spoken response plan is generated
8. TTS speaks result

This flow should be extended, not replaced.

---

## 5. Existing Components That Must Be Reused

Do not build parallel systems if the current ones already own the job.

### 5.1 VoiceAssistantCoordinator

This remains the central answer-layer orchestrator.

Use it for:

- query routing
- deciding direct answer vs clarification
- assembling answer intent
- selecting the correct data path

Do not create a second coordinator.

### 5.2 DomainCanonicalizer

This remains the first cleanup stage.

Use it for:

- lowercase normalization
- punctuation cleanup
- lightweight STT-safe cleanup
- trivial spoken-text cleanup

Do not move BSData alias logic into this layer.

### 5.3 CanonicalNameResolver

This is the correct home for deterministic name aliases and bounded canonical mapping.

Use it for:

- faction aliases
- unit aliases
- reordered name handling
- singular/plural handling where already designed

Do not replace it with fuzzy search.

### 5.4 Existing ambiguity/disambiguation path

If the coordinator already handles multiple result disambiguation, extend that path for voice — do not create a separate clarification engine.

### 5.5 Existing weapon-backed attribute path

The coordinator's weapon-backed attribute resolution path is already proven correct.
Use that path for weapon-dependent attributes.
Do not create a second attribute lookup path.

### 5.6 Spoken response plan layer

If a spoken response planning layer already exists, it should own:

- short spoken answer shapes
- clarification prompts
- no-match phrasing
- list summarization

### 5.7 Spoken plan player / TTS abstraction

Continue using the existing TTS abstraction and spoken plan player.
Do not bypass them with direct ad hoc speech calls.

---

## 6. Scope of Phase 12E

Phase 12E has four implementation tracks.

- **Track A** — Spoken Answer Assembly
- **Track B** — Clarification Dialogue
- **Track C** — Query-Shape Coverage
- **Track D** — Runtime Voice Validation

Do not add extra tracks.

---

## 7. Track A — Spoken Answer Assembly

**Objective:** Turn already-correct resolved data into short, natural spoken answers.

### A1. Single stat answers

Examples that must work naturally:

- "What is the toughness of a Carnifex?"
- "How far do Hearthkyn Warriors move?"

Desired answer shapes:

- "Carnifex toughness is 9."
- "Hearthkyn Warriors move 5 inches."

Rules:

- single sentence
- no raw map/list formatting
- no internal terminology
- no unnecessary explanation

### A2. Weapon-dependent stat answers

Examples:

- "What is the BS of Intercessors with bolt rifles?"

Desired answer shape:

- "Bolt rifle ballistic skill is 3 plus."

Rules:

- mention the weapon explicitly
- do not imply the stat belongs to the unit profile if it does not

### A3. Rule list answers

Examples:

- "What rules does a Carnifex have?"
- "Rules for Hive Tyrant"

Desired answer shapes:

- "Carnifex has Synapse, Deadly Demise, and Blistering Assault."

Rules:

- speak rule names clearly
- do not dump pages or internal metadata
- if rule count is large, summarize instead of reading everything

### A4. Ability search answers

Examples:

- "Which units have Synapse?"
- "Which units have [faction-specific ability]?"

Desired answer shape:

- "21 units have Synapse, including Hive Tyrant and Carnifex."

Rules:

- count + examples
- do not enumerate a long result set in full unless explicitly requested

### A5. No-match answers

Desired answer shape:

- "I couldn't find that unit in the loaded data."

Rules:

- concise
- honest
- no hallucinated fallback answer

---

## 8. Track B — Clarification Dialogue

**Objective:** Handle ambiguity conversationally instead of guessing.

### B1. Weapon-dependent stat ambiguity

Examples:

- "What is the BS of Intercessors?"
- "What is the damage of Carnifex weapons?"

Required behavior:

- do not answer with one arbitrary weapon
- ask a short follow-up question

Desired spoken clarification:

- "Which weapon?"
- or "Bolt rifle or bolt pistol?"

### B2. Multi-entity ambiguity

Examples:

- "Rules for Captain"
- "What is the toughness of Intercessor?"

Required behavior:

- if multiple strong matches remain, do not guess
- provide a short option list

Desired spoken clarification:

- "Which Captain? Captain, Captain with Jump Pack, or Captain in Terminator Armour?"

### B3. Too-broad search results

Examples:

- "Which units have infantry?"

Required behavior:

- do not read large lists aloud
- summarize and ask the user to narrow if necessary

### B4. Clarification constraints

All clarification prompts must be:

- short
- natural
- under one sentence if possible
- no more than 3–4 options

Do not use:

- long menus
- technical list dumps
- structural implementation jargon

---

## 9. Track C — Query-Shape Coverage

**Objective:** Close the current known voice gaps without broadening into freeform NLP.

### C1. Movement queries

Support these bounded phrasings:

- "how far do X move"
- "movement of X"
- "move of X"

Map these deterministically to the M characteristic.

### C2. Weapon-stat plural queries

Support these bounded phrasings:

- "what are the bs values for intercessor weapons"
- "what are the weapon skill values for X weapons"

Behavior may be either:

- compact listing of weapon-specific values
- or short summary with one or two named examples

But do not fail back into plain search.

### C3. Rule queries must answer, not merely resolve

Example:

- "rules for carnifex"

Current unacceptable outcome:

- resolves the unit but does not produce a spoken rule answer

Required outcome:

- actually answer with rules

### C4. Bounded attribute synonym support

Support only a bounded explicit list of attribute phrasings.

Minimum set:

| Spoken form | Maps to |
|---|---|
| bs | ballistic skill |
| ws | weapon skill |
| toughness | T |
| move / movement | M |
| save | SV |
| wounds | W |
| leadership | LD |
| objective control | OC |

Do not implement open-ended semantic normalization.

---

## 10. Track D — Runtime Voice Validation

**Objective:** Confirm the actual spoken experience is acceptable on real runtime.

### D1. Required runtime environment

Use device or emulator with TTS enabled.

### D2. Required runtime query set

Run these exact queries in spoken-style form:

1. "what's the bs of intercessors"
2. "how far do jump pack intercessors move"
3. "rules for carnifex"
4. "which units have synapse"
5. "what is the toughness of hive tyrant"
6. "chaos daemons units"

### D3. Validate runtime behavior

For each query, assess:

- was the entity resolved correctly?
- was the answer concise?
- did clarification occur where required?
- was the spoken phrasing natural?
- did the response avoid awkward technical wording?

### D4. Runtime-specific acceptance rules

TTS behavior is acceptable if:

- answer is understandable
- follow-up prompts are short
- interruption / follow-up does not produce confusing speech overlap
- speech is not overly long or robotic

---

## 11. Initial Alias List and Normalization Rule Set

This is the approved starting point for Phase 12E. It is intentionally small.

### 11.1 Philosophy

This is primarily for entity/name resolution now.
It is not yet a general full verbal-query understanding engine.
However, it should be implemented so it can later expand into a broader verbal normalization layer.

### 11.2 Raw text normalization rules

Apply first:

- lowercase everything
- trim whitespace
- collapse multiple spaces to one
- remove safe punctuation noise
- normalize apostrophe forms

Allowed bounded filler cleanup examples:

- what is
- what's
- tell me
- give me
- show me
- how far do
- rules for
- of
- for
- the
- a
- an

These should be used only where safe and deterministic.

### 11.3 Canonical token normalization

Use bounded normalization only.

Examples:

- intercessors → intercessor (internally for candidate generation)
- carnifexes → carnifex
- warriors → warrior
- terminators → terminator

Do not add a broad English stemmer.

### 11.4 Approved faction alias starter list

The initial faction alias list should include:

- chaos daemons → legiones daemonica
- imperial agents → agents of the imperium
- agents → agents of the imperium (only if ambiguity is acceptable in current tests)
- votann → leagues of votann
- leagues → leagues of votann (only if ambiguity is acceptable)

Any additional faction alias must be justified and approved.

### 11.5 Approved unit alias starter list

The initial unit alias list should include:

- jump pack intercessors → assault intercessors with jump pack
- jump pack intercessor → assault intercessors with jump pack

If other exact unit aliases are proposed, they must be justified with:

- current BSData mismatch
- real user phrasing evidence
- no ambiguity introduced

### 11.6 Reordered-name handling

Allow only bounded reordered handling for known-safe patterns.

Examples:

- jump pack intercessors ↔ assault intercessors with jump pack

Do not allow arbitrary token permutation.

### 11.7 Ambiguity behavior for short names

Examples:

- intercessor
- captain

Behavior:

- retrieve a broader candidate pool
- apply deterministic quality filtering
- if exactly one best candidate remains, answer directly
- if several strong candidates remain, clarify

Do not silently choose on alphabetical order alone.

### 11.8 No-match behavior

If no safe candidate exists:

- say the unit could not be found
- optionally offer one safe suggestion only if deterministic

No hallucinations.

---

## 12. Required Tests

### 12.1 Name-resolution tests

Add or extend tests covering:

- exact resolution
- faction aliases
- unit aliases
- singular/plural handling
- ambiguous short names
- no-match behavior

### 12.2 Ambiguity tests

Cover:

- direct answer for unit-level stat
- clarification for weapon-level stat
- clarification for multi-entity match
- direct answer when weapon is explicitly named

### 12.3 Spoken-answer tests

Cover:

- single stat answers
- rule-list answers
- ability search answers
- no-match answers
- concise clarification prompts

### 12.4 Runtime validation record

If runtime/device validation cannot be fully automated, document the manual validation run and outcomes.

---

## 13. Deliverables

At the end of Phase 12E, the coder must return:

### 13.1 Implementation summary

- which files changed
- which existing components were reused
- which new public names were introduced, if any

### 13.2 Alias / normalization summary

- final alias list used
- normalization rules actually implemented
- any approved deviations from the starter list

### 13.3 Test summary

- files added/updated
- pass/fail totals
- coverage of stat/rule/ability/ambiguity cases

### 13.4 Runtime voice summary

- runtime queries tested
- acceptable/not acceptable
- any remaining awkward phrasing noted

### 13.5 Remaining limitation list

Each limitation must be classified as:

- beta-acceptable limitation
- post-beta improvement
- future-update compatibility risk

### 13.6 Final recommendation

Choose one:

- Voice Beta Ready
- Voice Beta Ready With Minor Limitations
- Not Ready

---

## 14. Acceptance Criteria for Phase 12E

Phase 12E is complete only when all of these are true:

- Natural spoken stat questions work for core cases
- Natural spoken rule questions produce actual answers, not only entity matches
- Ability search answers are concise and correct
- Weapon-dependent stats trigger clarification when needed
- Name resolution handles the currently known real-world blockers
- Clarification prompts are short and natural
- No structural regressions are introduced
- Runtime spoken behavior is acceptable on device or emulator

---

## 15. What Must Not Change

The coder must not use Phase 12E as a reason to reopen solved architecture.

Do not change unless a fresh regression is proven:

- M1 Acquire
- M2 Parse
- M3 Wrap
- M4 Link
- M5 Bind
- M9 Index
- M10 Structured Search core behavior

Do not add:

- broad fuzzy search
- probabilistic ranking
- cloud NLP
- rules-engine logic
- roster logic

---

## 16. Final Guidance Statement

Phase 12E is not about making the system smarter in a broad sense.

It is about making the system:

- usable
- natural
- concise
- correct under voice interaction

The coder should treat this as the final usability layer on top of an already-correct deterministic engine.

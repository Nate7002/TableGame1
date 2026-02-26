# AGENTS.md
# TableGame1 — Agent Instructions

These instructions are for Cursor Agent working inside this repository.

This file defines repository-level guidance for Agent execution.

If conflicts arise, follow this hierarchy:

1. TABLEGAME1_SOURCE_OF_TRUTH_V5.md
2. universal_ui_operating_standard.md (UI matters)
3. ChatGPT Operating Rules (V7)
4. Cursor project rules in `.cursor/rules/`
5. This file

Higher levels override lower ones.

---

## Repo Layout (Canonical)

- Server gameplay systems: `src/server/Core/`
- Server plugins/minigames: `src/server/Plugins/`
- Server configs: `src/server/Config/`
- Client UI/controllers: `src/client/UI/`
- Shared utilities/config: `src/shared/`
- UI animation runtime: `ReplicatedStorage/UIAnimations/Modules/`

Do not invent new top-level structure unless explicitly requested.

---

## Collaboration Style

- Preserve what works.
- Fix real bugs first.
- Prefer reversible, additive changes.
- Avoid redesigns unless explicitly requested.
- Follow puzzle-piece modular philosophy.

One system = one responsibility.

---

## Implementation Expectations

- Use existing patterns from the repo.
- Prefer minimal diffs.
- Never rewrite unrelated files.
- When uncertain, inspect with `robloxstudio-mcp`.
- Avoid speculative edits.
- Confirm exact file paths before modification.

Edit safety is mandatory and enforced by `.cursor/rules/edit_safety.mdc`.

---

## Architecture Constraints

UI is presentation-only.

UI must never:

- Own gameplay logic
- Modify authoritative state
- Access DataStore
- Resolve outcomes

Intent must route through controller modules.

No hidden coupling between systems.

---

## UI Rules (Mandatory)

All UI work MUST comply with:

- `universal_ui_operating_standard.md` (canonical specification)
- `.cursor/rules/ui_doctrine.mdc`
- `.cursor/rules/ui_implementation.mdc`
- `.cursor/rules/ui_import.mdc`

The Universal UI Operating Standard is the single source of truth for:

- UI taxonomy (TYPE 0–3)
- Shell hierarchy
- Naming doctrine
- Tag system
- PNG discipline
- Figma → Upload → Studio pipeline
- @GRAY behavior

Cursor rules enforce this specification mechanically.

Do not restate or redefine canonical UI specifications in new files.
Reference the canonical document instead.

---

## UI Behavior Constraints

UI must:

- Display state
- Emit intent
- Animate feedback

UI must not:

- Decide gameplay outcomes
- Mutate authoritative state
- Introduce new lifecycle patterns
- Rebuild UI per state when toggling visuals is sufficient

Do not introduce new UI hierarchies, lifecycles, or structural patterns unless explicitly requested.

---

## Enforcement Model

- Source of Truth defines engine invariants.
- Universal UI Operating Standard defines UI invariants.
- ChatGPT Operating Rules define collaboration behavior.
- Cursor `.mdc` rules enforce mechanical constraints.

AGENTS.md provides repository-level execution guidance only.

Do not duplicate canonical specifications across layers.


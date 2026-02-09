# AGENTS.md
# TableGame1 — Agent Instructions

These instructions are for Cursor Agent working inside this repository.

## Repo Layout (Canonical)
- Server gameplay systems: `src/server/Core/`
- Server plugins/minigames: `src/server/Plugins/`
- Server configs: `src/server/Config/`
- Client UI/controllers: `src/client/UI/`
- Shared utilities/config: `src/shared/`
- UI animation runtime: `ReplicatedStorage/UIAnimations/Modules/`

## Collaboration Style
- Preserve what works.
- Fix real bugs first.
- Prefer reversible, additive changes.
- Avoid redesigns unless explicitly requested.

## Implementation Expectations
- Use existing patterns from the repo.
- Prefer minimal diffs.
- When uncertain, inspect with `robloxstudio-mcp`.
- Avoid speculative edits.

## UI Rules (Mandatory)

All UI work in this repository MUST follow the Cursor UI rules located in:

- `.cursor/rules/ui-doctrine.mdc`
- `.cursor/rules/ui-import.mdc`
- `.cursor/rules/ui-implementation.mdc`

These rules define:
- UI taxonomy (HUD / Button / Menu / Interactive)
- Required Menu hierarchy and locked names
- Import and scaling constraints
- UI behavior wiring and authority boundaries

The **Universal UI Operating Standard** is the human- and reasoning-AI doctrine for UI.
It is not enforced directly by Cursor, but should be referenced for:
- mental models
- planning
- review and validation of UI decisions

UI code must:
- Treat UI as presentation only
- Emit intent, never decide outcomes
- Avoid rebuilding UI per state (toggle visuals instead)

Do not introduce new UI patterns, hierarchies, or lifecycles unless explicitly requested.

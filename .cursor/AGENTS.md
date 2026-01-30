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

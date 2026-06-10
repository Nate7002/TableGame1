# AGENTS.md — TableGame1 AI Agent Instructions (Codex Optimized)

This file defines how AI coding agents (Codex, Cursor, etc.) must operate inside this repository.

The goal of this project is to build **TableGame1**, a modular Roblox PvP table game engine with clean system boundaries.

Agents must preserve architecture and avoid cross‑system mutation.

---

# Project Overview

TableGame1 is a **server-authoritative Roblox engine** for table-based PvP minigames.

The engine is built as modular puzzle pieces.

Each system has a **single responsibility**.

Agents must **extend systems**, not redesign them.

---

# Architecture Map

Server gameplay systems:

```
src/server/Core/
```

Primary systems:

StatsService
Player stats, inventory, streaks

TableService
Seat detection and table state

RoundService
Match lifecycle and round outcomes

ModifierService
Applies round modifiers (powerups)

Modifiers
Isolated mechanics (shield, perks, etc)

---

# System Responsibilities

StatsService

* Player stats
* Inventory (shields, items)
* Streak tracking
* Round stat updates

TableService

* Seating logic
* Seat UI requests
* Player seat state

RoundService

* Round lifecycle
* Determine winners / losers
* Build resultPayload

ModifierService

* Mutate round results
* Apply modifiers before stats

Modifiers

* Isolated mechanics
* Must not store persistent state

---

# Critical Architecture Rules

These rules must never be violated.

1. StatsService is the **single authority** for inventory and stats.
2. UI must never own gameplay state.
3. Systems must not read or mutate another system's internal state.
4. Never duplicate gameplay state across services.
5. Modifier logic must live in **Modifiers**, not RoundService.
6. Prefer seams and adapters over rewriting systems.

Examples of violations:

❌ Reading shields from player objects
❌ Using leaderstats for gameplay logic
❌ Storing duplicate inventory state outside StatsService
❌ Writing gameplay rules inside UI

---

# Repository Layout

```
src/server/Core/       core gameplay systems
src/server/Plugins/    minigame plugins
src/server/Config/     configs

src/client/UI/         UI controllers

src/shared/            shared utilities

ReplicatedStorage/UIAnimations/Modules/
UI animation runtime
```

Agents must **not invent new top-level structure**.

---

# Development Workflow

Use the following workflow:

Build → Test → Commit → Push

Do not skip testing steps.

Agents should prefer **minimal diffs** and avoid rewriting working systems.

---

# Editing Rules

When modifying code:

* Use existing patterns from the repo
* Preserve working behavior
* Avoid speculative refactors
* Confirm file paths before editing
* Keep changes minimal and additive

Never rewrite unrelated files.

---

# Refactor Safety

When refactoring:

* Preserve behavior
* Move logic rather than rewriting
* Introduce seams for future extension
* Maintain determinism in gameplay systems

---

# Output Requirements

All implementation responses must include:

1. Exact file paths modified
2. Clear description of what changed
3. Why the change is architecturally safe
4. Roblox Studio test checklist

---

# Priority Order

When making decisions:

1. Architecture preservation
2. Modular integrity
3. Determinism
4. Clarity
5. Performance
6. Cleverness

Clever solutions must never compromise structure.

---

# Studio Backend Harness (NEW)

TableGame1 now has a Studio-only backend harness for authoritative backend validation.

### Use it when
Use the harness for:
- backend stat mutation checks
- payout branch checks
- VIP multiplier checks
- monetization state inspection
- repeatable regression testing

### Current command surface
- `/dumpstats`
- `/dumpstats all`
- `/dumpmonetization`
- `/setvip on`
- `/setvip off`
- `/testreceipt <productKey>`
- `/testrestore <productKey>`
- `/testround single_win_p1`
- `/testround single_lose_p1`
- `/testround draw`
- `/testround vip_single_win_p1`
- `/testround vip_draw_mixed`
- `/testround both_lose`

### Studio automation note
- current Studio MCP/tooling can start/stop playtests and read output logs
- it cannot directly execute code inside the live play server or inject `player.Chatted` commands during play
- therefore harness commands are normally run manually through Studio chat
- if temporary automation is needed, use a short-lived uncommitted `LocalScript` probe under `StarterPlayerScripts` that sends commands through `TextChatService.TextChannels.RBXGeneral`
- remove the probe after testing
- do not commit the probe or turn it into a permanent/public command surface

### Rules
- `DevTestService` is orchestration-only
- `StatsService` remains the mutation authority
- `MonetizationService` remains the VIP/multiplier authority
- synthetic rivals must remain harness-local only
- do not leak synthetic rivals into Players, UI, persistence, or leaderboards
- do not turn the harness into a second gameplay engine

### Testing doctrine
Use the harness for backend correctness.
Use manual playtests for:
- UI feel
- prompt timing
- seat/join flow
- real multiplayer behavior
- release smoke checks

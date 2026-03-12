---
description: Prevents architectural drift across systems.
alwaysApply: false
---

# Architecture Rule

UI must comply with universal_ui_operating_standard.md.

UI is a client-side presentation layer.

UI must never:

- Own business logic
- Modify authoritative state
- Access DataStore
- Resolve outcomes

Intent must route to controller modules.

Systems must remain:

- Modular
- Composable
- Portable

Reject designs introducing hidden coupling.

## Server Architecture

Gameplay systems must maintain clear ownership.

StatsService
- Owns player stats and inventory.

TableService
- Owns seat detection and table state.

RoundService
- Owns round lifecycle and outcomes.

ModifierService
- Mutates round results through modifiers.

DevTestService
- Studio-only backend test orchestrator.
- May set up scenarios and validate authority seams.
- Must not own gameplay rules, stat mutation, or monetization rules.

Systems must not duplicate gameplay state.
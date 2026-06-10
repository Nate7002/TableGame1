# TableGame1 / RobloxProject

A modular, server-authoritative Roblox/Luau engine for 2-player PvP table minigames.

**Status:** Early-stage public project in active development. Core gameplay, persistence, and monetization backends exist; retention features and a full shop UI are still planned.

## What this is

TableGame1 is a reusable game loop built around seated 1v1 matches at physical table models. Players join via proximity prompts, play a plugin-driven minigame, earn stats and currency, and can use shields and monetized restore offers. The codebase separates server authority, client presentation, and shared configuration.

This repository is maintained as open source for learning, collaboration, and tooling experiments. It is not claiming production scale or adoption metrics.

## Features (implemented in this repo)

Based on files under `src/` and the included place file:

- **Table seating** — 2-seat tables with proximity prompts, leave-seat flow, and match countdown (`TableService`)
- **Round lifecycle** — match start/end, opponent-leave handling, cinematic sync (`RoundService`)
- **Plugin system** — discoverable minigame modules via `PluginRegistry` / `PluginRunner`
- **DoubleDown minigame** — loot spin plus Split / Steal / DoubleDown choice stages (`src/server/Plugins/DoubleDown.lua`)
- **Example plugin** — `HelloPlugin` for reference
- **Player stats** — Cash, Wins, Streak, MaxStreak, GamesPlayed, Gems, Shields (`StatsService`)
- **Round modifiers** — shield protection applied before stat mutation (`ModifierService`, `ShieldModifier`)
- **Persistence** — DataStore save/load with DEV/PROD namespaces and autosave (`DataService`)
- **Leaderboards** — weekly and overall boards for MaxStreak, GamesPlayed, Donations (`LeaderboardService`)
- **Monetization backend** — VIP multiplier, gem/shield dev products, restore offers, receipt routing (`MonetizationService`, `MonetizationConfig`)
- **Client UI** — HUD, toasts, choice popups, seat UI, shield inventory, restore offer, cinematics, intro guides (`src/client/UI/`)
- **Studio dev harness** — chat commands for stat dumps, synthetic rounds, and receipt tests (`DevTestService`, Studio-only)

**Not yet in the repo** (see [ROADMAP.md](ROADMAP.md)): full shop UI, idle/emote systems, daily rewards, and post-release expansion features.

## Architecture overview

```
src/
├── client/          # LocalScripts — UI controllers and presentation only
├── server/
│   ├── Core/        # Authoritative services (stats, rounds, tables, monetization, data)
│   ├── Plugins/     # Minigame plugins (DoubleDown, HelloPlugin)
│   ├── Config/      # Server-side game config (e.g. SpinTable)
│   └── Assets/      # Server-side assets referenced by services
└── shared/          # Config modules replicated to clients (MonetizationConfig, ShieldConfig)
```

| Layer | Responsibility |
|-------|----------------|
| **Server Core** | Gameplay authority, economy, persistence, remotes |
| **Client UI** | Display, input, animations — no gameplay state ownership |
| **Shared** | Read-only config consumed by both sides |

Key services live in `src/server/Core/`:

| Service | Role |
|---------|------|
| `StatsService` | Single authority for stats and inventory mutations |
| `TableService` | Seating, table state, shield arming while waiting |
| `RoundService` | Match lifecycle, plugin execution, result payload |
| `ModifierService` | Applies round modifiers before stats update |
| `DataService` | DataStore load/save |
| `MonetizationService` | Marketplace receipts, VIP, restore offers |
| `UIService` | Creates and fires `ReplicatedStorage.Remotes` events |
| `LeaderboardService` | OrderedDataStore leaderboards |
| `DevTestService` | Studio-only backend test harness |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for data-flow detail.

## Getting started

### Prerequisites

- [Roblox Studio](https://create.roblox.com/)
- [Rojo](https://rojo.space/) 7.x (pinned in [aftman.toml](aftman.toml))
- [Aftman](https://github.com/LPGhatguy/aftman) (recommended for installing Rojo)

### Rojo workflow (configured)

This repo includes `default.project.json` and `aftman.toml`. Rojo maps source files into the DataModel:

| Source path | Roblox location |
|-------------|-----------------|
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/server` | `ServerScriptService.Server` |
| `src/server/Plugins` | `ServerStorage.Plugins` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |

**Typical local workflow:**

1. Clone the repository.
2. Install toolchain: `aftman install`
3. Start Rojo: `rojo serve default.project.json`
4. Open [TableGame1.rbxl](TableGame1.rbxl) in Roblox Studio.
5. Connect the [Rojo Studio plugin](https://rojo.space/docs/v7/getting-started/installation/) to the running server and sync.
6. Press **Play** (or **Start Server** + **Start Player** for multiplayer tests).

**Alternative:** build a place file without live sync:

```bash
rojo build default.project.json -o TableGame1-built.rbxl
```

> **Note:** World geometry (lobby map, table spawn hitboxes, leaderboard parts) lives in the `.rbxl` place file, not only in `src/`. After syncing scripts, confirm `Workspace.Map` and related instances exist in your place.

### Studio-only commands

When running in Studio, chat commands are available for development. Type `/cmds` in chat for the current list. Harness commands (`/dumpstats`, `/testround …`, `/testreceipt …`) are documented in [AGENTS.md](AGENTS.md).

## Testing and validation

| Method | Use for |
|--------|---------|
| **DevTestService harness** | Backend stat mutations, payout branches, VIP multiplier, receipt/restore simulation |
| **Studio chat dev commands** | Quick stat edits, plugin runs, shield tests |
| **Manual multiplayer playtest** | Seat flow, UI timing, opponent leave, real RemoteEvent behavior |
| **Published / live smoke test** | DataStore, Marketplace, and production-only paths |

Harness commands are **Studio-only** and do not run on published servers.

## Security notes

TableGame1 follows standard Roblox trust boundaries:

- **Server authority** — gameplay outcomes, stat changes, and inventory mutations happen in server services (`StatsService`, `RoundService`, `MonetizationService`). Clients display state; they do not own it.
- **RemoteEvents** — `UIService` creates `ReplicatedStorage.Remotes`. Client → server remotes (e.g. `PromptResponse`, `UseShield`, `LeaveSeat`, `RequestRestorePurchase`) must be validated on the server. Treat every client payload as untrusted.
- **DataStore persistence** — `DataService` uses separate DEV/PROD namespaces. Schema changes require careful migration. Test save/load and shutdown behavior before shipping economy changes.
- **Marketplace / receipts** — `MonetizationService` is the purchase authority. Receipt handlers must be idempotent. Never grant currency or items from client-initiated events alone.
- **Economy validation** — all Cash, Gems, and Shields changes should go through `StatsService`. Review multiplier logic (VIP) and restore-offer expiry when touching payout code.

Report security concerns via [SECURITY.md](SECURITY.md).

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

- **Bug reports:** [GitHub Issues](https://github.com/Nate7002/TableGame1/issues/new?template=bug_report.yml)
- **Feature ideas:** [GitHub Issues](https://github.com/Nate7002/TableGame1/issues/new?template=feature_request.yml)
- **Pull requests:** fork, branch, test in Studio, then open a PR against `main`

## Roadmap

High-level plans are in [ROADMAP.md](ROADMAP.md). Realistic near-term next steps:

- [ ] Full shop UI (gems, shields, cosmetics shell)
- [ ] Idle and emote systems (Phase 1 retention layers)
- [ ] Daily rewards and return loops (Phase 2)
- [ ] CI lint/format for Luau (not yet configured)
- [ ] Screenshots and gameplay GIFs for this README

## Screenshots / GIFs

<!-- TODO: Add media after capturing in Studio -->
<!-- Suggested captures: table seating flow, DoubleDown choice UI, stats HUD, restore offer popup -->
<!-- Save files under docs/media/ and reference them here, e.g.: -->
<!-- ![DoubleDown match](docs/media/doubledown-match.png) -->

Media assets are not included yet. To add them:

1. Capture PNG or GIF in Studio or during a playtest.
2. Save under `docs/media/`.
3. Reference the files in this section.

## License

This project is licensed under the [MIT License](LICENSE).

Copyright (c) 2026 Nathan Oh

## Related documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system design and data flow
- [CONTRIBUTING.md](CONTRIBUTING.md) — contributor guide
- [SECURITY.md](SECURITY.md) — vulnerability reporting
- [AGENTS.md](AGENTS.md) — AI agent / harness conventions (maintainers)

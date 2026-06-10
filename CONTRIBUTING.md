# Contributing to TableGame1

Thank you for your interest in contributing. TableGame1 is an early-stage Roblox/Luau project with a strict server-authoritative architecture. This guide helps you set up locally and submit changes that fit the existing design.

## Before you start

- Read [README.md](README.md) for project scope and setup.
- Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for system boundaries.
- Read [AGENTS.md](AGENTS.md) if you will touch backend testing or harness code.

## Local setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/Nate7002/TableGame1.git
   cd TableGame1
   ```

2. **Install tools**
   - [Roblox Studio](https://create.roblox.com/)
   - [Aftman](https://github.com/LPGhatguy/aftman), then run:
     ```bash
     aftman install
     ```
   - Rojo is pinned in `aftman.toml` (currently 7.7.0-rc.1).

3. **Sync source into Studio**
   ```bash
   rojo serve default.project.json
   ```
   Open `TableGame1.rbxl` in Studio, connect the Rojo plugin, and sync.

4. **Verify the place**
   - Confirm `Workspace.Map` and table spawn hitboxes exist (world content is in the `.rbxl` file).
   - Press Play and check the Output window for server boot logs.

## Branch and pull request expectations

- Branch from `main` using a descriptive name (e.g. `fix/shield-remote-validation`, `docs/readme-clarity`).
- Keep PRs focused. Prefer small, reviewable changes over large rewrites.
- Include in the PR description:
  - What changed and why
  - How you tested in Studio
  - Any trust-boundary impact (remotes, stats, purchases, persistence)
- Link related issues when applicable.

Do not commit:

- Local Aftman auth files (`.aftman/`)
- Temporary Studio test probes under `StarterPlayerScripts`
- Place lock files (`*.rbxl.lock`)

## Code style (Luau / Roblox)

- Match existing patterns in the file you edit (naming, module layout, logging via `DebugService`).
- **Server authority:** gameplay rules and state mutations belong in `src/server/Core/`, not in client UI scripts.
- **StatsService** is the single authority for inventory and stat changes. Do not duplicate that state elsewhere.
- **Modifier logic** belongs in `src/server/Core/Modifiers/`, not in `RoundService`.
- **UI** under `src/client/UI/` should react to server events and send validated requests — not compute outcomes.
- Prefer minimal diffs. Extend systems rather than redesigning them.
- Use `DebugService` levels appropriately; avoid noisy `print` in production paths unless consistent with nearby code.

There is no automated Luau linter in CI yet. Manual review and Studio testing are expected.

## Security-sensitive changes

If your change touches any of the following, explain the trust boundary in your PR:

- `RemoteEvent` / `RemoteFunction` handlers
- `StatsService`, `DataService`, or economy fields (Cash, Gems, Shields)
- `MonetizationService`, receipts, restore offers, or VIP multipliers
- Round outcome or modifier pipelines

Guidelines:

- Validate all client input on the server (type, range, timing, player context).
- Never trust client-reported win/loss, currency, or inventory values.
- Keep purchase grants behind `MarketplaceService.ProcessReceipt` (or harness equivalents in Studio).

## Testing expectations

Test what you change:

| Change type | Minimum testing |
|-------------|-----------------|
| UI-only | Studio playtest, verify remotes still fire/receive |
| Round / plugin logic | 2-player Studio server, full match flow |
| Stats / modifiers | Harness: `/testround …` or `/dumpstats` (Studio) |
| Persistence | Join, mutate stats, leave/rejoin, confirm DataStore load |
| Monetization | Harness: `/testreceipt`, `/testrestore`, `/dumpmonetization` (Studio) |
| Multiplayer edge cases | Opponent leave mid-match, disconnect during countdown |

Harness details: [AGENTS.md](AGENTS.md#studio-backend-harness-new).

## Reporting bugs and suggesting features

- **Bugs:** open a [bug report issue](https://github.com/Nate7002/TableGame1/issues/new?template=bug_report.yml)
- **Features:** open a [feature request issue](https://github.com/Nate7002/TableGame1/issues/new?template=feature_request.yml)

Include reproduction steps, expected vs actual behavior, and Studio context (solo vs 2-player, Studio vs published if relevant).

## Questions

Open a GitHub Issue with the **question** label or start a Discussion if enabled on the repository. There is no guaranteed response SLA; this is a maintainer-led early-stage project.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

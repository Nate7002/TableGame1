# Security Policy

## Supported versions

TableGame1 is an **early-stage** open-source Roblox project in active development. There is no long-term support commitment or formal release cadence yet.

| Status | Notes |
|--------|-------|
| `main` branch | Active development; security fixes welcome |
| Published Roblox experience | Not tracked in this repository; verify separately |

Security review and responsible disclosure are encouraged even during early development.

## Reporting a vulnerability

**Do not** open public GitHub issues for exploitable security bugs.

Instead:

1. Use [GitHub Security Advisories](https://github.com/Nate7002/TableGame1/security/advisories/new) (preferred), **or**
2. Email the maintainer via the contact method listed on their [GitHub profile](https://github.com/Nate7002).

Include:

- Description of the issue and impact
- Steps to reproduce (Studio or live, as applicable)
- Affected files or remotes, if known
- Any proof-of-concept that demonstrates the issue without harming users

We aim to acknowledge reports within a reasonable timeframe. This project has no formal SLA.

## Bug bounty

**No public bug bounty is offered** at this time. This may change in the future; this file will be updated if it does.

## Security areas of concern

This codebase handles server-authoritative gameplay, persistence, and monetization. Reviewers and contributors should pay special attention to:

### RemoteEvent abuse

Client → server remotes under `ReplicatedStorage.Remotes` include `PromptResponse`, `UseShield`, `LeaveSeat`, and `RequestRestorePurchase`. Handlers must validate player identity, timing, game phase, and payload shape. Missing checks can allow stat manipulation or out-of-phase actions.

### Client authority mistakes

Gameplay outcomes, currency, inventory, and purchase grants must not be decided on the client. `StatsService` and `MonetizationService` are server authorities. UI scripts must not own or persist gameplay state.

### DataStore corruption / loss

`DataService` manages player profiles with retry logic and schema sanitization. Changes to save timing, schema fields, or shutdown behavior can cause data loss or inconsistent loads. Test join/leave/rejoin and server shutdown paths.

### Purchase receipt handling

`MonetizationService` routes `MarketplaceService.ProcessReceipt`. Handlers must be idempotent, reject invalid product IDs, and grant rewards only through `StatsService`. Studio harness commands simulate receipts for testing — they must remain Studio-only.

### Economy exploits

Review any change to Cash, Gems, Shields, VIP multipliers, restore offers, and round payout branches. Attackers may spam remotes, replay requests, or disconnect to race state. Rate limits and server-side expiry (e.g. restore offer windows) matter.

### Round-state desync

`RoundService` coordinates match phases, cinematics, and plugin execution. Bugs can leave players stuck seated, double-apply rewards, or apply modifiers outside valid windows. Test opponent leave, abort, and timeout paths.

## Secure development practices

- Run relevant harness scenarios in Studio after backend changes (see [AGENTS.md](AGENTS.md)).
- Test with two clients for multiplayer and remote flows.
- Document trust-boundary impact in pull requests.
- Keep dev/chat commands gated to `RunService:IsStudio()` where applicable.

## Disclosure

We appreciate coordinated disclosure. Please allow time to investigate and patch before public details, when reasonable.

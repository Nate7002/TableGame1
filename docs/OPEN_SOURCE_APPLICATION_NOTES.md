# Open Source Application Notes (Codex for Open Source)

Internal draft answers for the [OpenAI Codex for Open Source](https://openai.com/codex) application form. Edit before submitting. Keep field answers under **500 characters** where the form limits length.

---

## Maintainer role

**Draft (<500 chars):**

I am the sole maintainer of TableGame1, a public Roblox/Luau PvP table-game engine on GitHub (Nate7002/TableGame1). I design the architecture, implement server-authoritative gameplay systems, review PRs, and document trust boundaries for stats, DataStore persistence, and Marketplace receipts. The repo is early-stage with no large contributor base yet.

---

## Why this repository qualifies

**Draft (<500 chars):**

TableGame1 is a real, public open-source codebase with modular server services, a plugin minigame system, persistence, monetization backends, and Studio test harnesses. It is actively developed in Luau with clear client/server/shared boundaries— suitable for AI-assisted security review, documentation, and incremental feature work without inventing architecture from scratch.

---

## Why Codex Security is useful

**Draft (<500 chars):**

The project handles RemoteEvents, server-authoritative economy (Cash/Gems/Shields), DataStore saves, and Marketplace receipt routing. Codex Security would help catch client-trust mistakes, remote abuse paths, idempotency gaps in purchases, and round-state desync—areas where manual review is easy to miss in a solo-maintainer Roblox codebase.

---

## How API credits would be used

**Draft (<500 chars):**

Credits would support: (1) security-focused reviews of remotes, StatsService, MonetizationService, and DataService; (2) documentation and contributor onboarding improvements; (3) implementing roadmap items (shop UI, retention loops) with architecture-preserving diffs; (4) expanding the Studio DevTest harness for regression scenarios. No production user data is processed via API.

---

## Project status (honest framing)

**Draft (<500 chars):**

Early-stage public repo. No claimed stars, DAU, or production metrics. Core loop (seating, DoubleDown plugin, stats, shields, persistence, monetization backend, client UI) exists in source. Shop UI, idle/emote systems, and CI are not done. Maintained by one developer; contributions welcome via GitHub Issues and PRs.

---

## Tech stack summary

**Draft (<500 chars):**

Roblox Luau, Rojo 7.x (default.project.json + aftman.toml), Roblox Studio place file (TableGame1.rbxl). ServerScriptService services, ReplicatedStorage remotes, DataStore + OrderedDataStore, MarketplaceService. Client UI in StarterPlayerScripts. MIT License. Docs: README, CONTRIBUTING, SECURITY, docs/ARCHITECTURE.md.

---

## Other notes for OpenAI

- **License:** MIT, Copyright (c) 2026 Nathan Oh — confirm before submit.
- **Organization ID:** Add your OpenAI Organization ID manually when the form asks.
- **No bug bounty** unless you add one later (see SECURITY.md).
- **Harness safety:** DevTestService and chat dev commands are Studio-only; do not expose on live servers.
- **Do not overclaim:** This is a framework/engine-style Roblox project, not a shipped title with adoption stats.
- **Screenshots:** Not in repo yet; add under `docs/media/` before marketing the README.
- **VIP Game Pass ID** in MonetizationConfig is still `0` — production monetization requires configuration.

---

## Suggested repo links for the form

| Item | URL |
|------|-----|
| Repository | https://github.com/Nate7002/TableGame1 |
| README | https://github.com/Nate7002/TableGame1#readme |
| Architecture | https://github.com/Nate7002/TableGame1/blob/main/docs/ARCHITECTURE.md |
| Security | https://github.com/Nate7002/TableGame1/blob/main/SECURITY.md |
| License | https://github.com/Nate7002/TableGame1/blob/main/LICENSE |

---

## Pre-submit checklist

- [ ] Confirm MIT license is the license you want
- [ ] Add OpenAI Organization ID
- [ ] Capture at least one gameplay screenshot or GIF
- [ ] Verify Rojo + Studio setup steps on a clean machine
- [ ] Set real VIP Game Pass ID if applying as a monetized live experience
- [ ] Trim any draft answer that exceeds 500 characters

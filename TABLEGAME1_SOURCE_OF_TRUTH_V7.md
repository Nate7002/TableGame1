# TableGame1 - System Doc (Source of Truth)

Version: **V7**  
Last updated: **Mar 16, 2026**

This document is the **authoritative memory + design contract** for TableGame1.  
It exists so the project can be resumed in *any* future chat without loss of context.

Core philosophy: **puzzle-piece systems**, anti-drown discipline, Cursor-first workflow.

---

## 0) One-Sentence Pitch

A Roblox table-PvP game where players sit at tables, play fast minigames, earn progression, and loop endlessly through social pressure and risk/reward.

---

## 1) Current Reality Snapshot (IMPORTANT)

**Status: Stable, Playable, and Tooling-Backed**

- Step 7 (Data Saving / Loading + round polish) is **complete**.
- Step 9 (Economy Foundation) is **complete**.
- Step 10 backend monetization is **complete**.
- Step 10 included:

  - centralized receipt routing
  - gem developer-product fulfillment
  - shield developer-product fulfillment
  - restore authority seam
  - restore fulfillment

- Step 10F (shield activation / pre-match consumption polish) was reviewed and did **not** require a new implementation slice.
- The game has been **playtested with real players** in multi-client sessions.
- Core loop is stable:

  - join table -> force sit
  - countdown
  - spin cinematic
  - stage UI (choices)
  - resolve outcome
  - cleanup
  - save stats

- Recent backend/system improvements addressed:

  - seat replication/desync
  - spin randomness feel (no consecutive repeats)
  - UI state leaks
  - opponent leave aborts
  - datastore reliability
  - Gems persistence
  - Shields persistence
  - VIP reward multiplier routing
  - explicit stats-update/toast contract cleanup
  - restore offer state, expiry, cooldown, and consumption

- The project now has:

  - centralized receipt routing
  - backend fulfillment for Gems, Shields, and Restore
  - a Studio-only backend test harness for authoritative backend validation

- Current harness/debug coverage includes:

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

- Backend correctness can now be validated through the **live Studio server runtime** without relying on fragile ad hoc command-bar/module-state checks.

**Remaining work is now structured feature expansion, not core-loop rescue.**

This project is no longer prototype territory.  
It is now a real game with working backend foundations, verified progression systems, a reusable internal testing workflow, and a completed backend monetization engine.

---

## 2) Original Vision

Minimalist, addictive, system-driven.

Inspired by:

- Bomb-chip / table minigames
- Split/Steal RNG tension loops

The goal is not one game - it is a **reusable engine** for table-based PvP games.

---

## 3) Core Ideology: Puzzle Pieces (Non-Negotiable)

Each system must be:

- modular
- swappable
- self-contained

Rules:

- One system = one responsibility
- Public APIs only
- No cross-module internal mutation
- Systems communicate via:

  - function calls
  - events
  - shared config/interfaces

---

## 4) Working Relationship Expectation

ChatGPT acts as a **systems partner**, not a yes-man.

It should:

- block bad ideas early
- protect architecture
- prioritize momentum over perfection
- preserve what works

---

## 5) Workflow (Anti-Drown)

Golden loop:  
**Build -> Test -> Commit -> Push**

No skipping steps.

**Testing doctrine update:**

- Use the **Studio-only backend harness** for backend correctness
- Use **manual playtesting** for human-facing validation:

  - UI feel
  - timing/urgency
  - seat/join friction
  - real multiplayer behavior
  - release smoke checks

Rule of thumb:

- automate correctness
- manually verify experience

---

## 6) MCP Arsenal (Available Tools)

Primary:

- robloxstudio-mcp

Secondary:

- brave-search
- browserbase
- github (read-only mindset)
- figma (unused)

MCPs should be used to confirm reality before changing code.

---

## 7) Roadmap (High Level)

### Phase 1 - MVP (DONE)

Steps 0-7 complete.

### Phase 2 - Retention / Economy / Monetization

Completed in this phase:

- Step 8 foundation/pacing work (partially addressed through ongoing polish)
- Step 9 economy foundation
- Step 10 backend monetization

### Step 10 Completed

Step 10 backend monetization is now complete:

- centralized receipt routing complete
- gem dev products complete
- shield dev product complete
- restore authority seam complete
- restore tiered products complete
- shield activation authority reviewed; no new implementation slice required

### Current Next Phase

- Step 11 - Protection Surface (Minimal UI)
- Step 12 - Economy HUD Surface
- Step 13 - Lean Shop

### Later

- Step 14 - Idle System
- Step 15 - Emote System
- later retention / cosmetics / scaling work

---

## 8) Current Systems Overview

### Server Core

- TableService
- RoundService
- SpinService
- UIService
- PluginRunner
- StatsService
- FXService
- **DataService**
- **LeaderboardService**
- **MonetizationService**
- **DevTestService** (Studio-only backend test orchestrator)

### Plugins

- DoubleDown
- HelloPlugin

### Client

- UIController
- CinematicController
- PromptController
- UI Components (ChoicePopup, Toast, Countdown, SeatUI)

---

## 9) Table Join Rules (UX Critical)

- Join via ProximityPrompt
- Touch-sit disabled
- Force sit via code
- Seats are server-owned and reset after matches

---

## 10) DoubleDown Rules (Canonical)

Stage 1:

- SPLIT / STEAL / DOUBLEDOWN

Stage 2:

- SPLIT / STEAL

Standard split/steal rules apply.

---

## 11) Spin Stage (Finalized)

- Fast -> slow item cycling
- Visual RNG only (odds unchanged)
- No consecutive identical items
- Billboard shows name, rarity, value
- Final item locks reward

SpinService is reusable and isolated.

---

## 12) Data & Stats

Saved:

- Cash
- Gems
- Shields
- Wins
- Streak
- MaxStreak
- (Internal tracking exists beyond this list; StatsService is canonical source)

Datastore hardened for disconnects and aborts.

### 12.1 Datastore Isolation (DEV vs PROD) - CRITICAL

**Goal:** Testing in Studio must never touch live/public player data.

We implemented/standardized a **namespace split**:

- **Studio/testing uses DEV**
- **Published live servers use PROD**
- Datastore names are generated from `BaseName + "_" + Namespace`

**What this guarantees:**

- Running Studio tests with fake population or forced stat changes does **not modify** real playerbase data.
- Published servers read/write only PROD keys/stores.
- Existing public data remains intact unless datastore naming is intentionally changed.

**Namespace source-of-truth rule:**

- Namespace is centrally defined by **DataService**
- Other systems (like `LeaderboardService`) fetch it via `DataService.GetNamespace()`

### 12.2 DataService Namespace Contract

DataService exposes:

- `DataService.GetNamespace() -> "DEV" | "PROD" | other`
- `DataService.IsApiEnabled()` remains authoritative for "datastore usable?"

**Recommended default behavior:**

- If `RunService:IsStudio()` -> `"DEV"`
- Else -> `"PROD"`

### 12.3 OrderedDataStore Namespacing for Leaderboards

Leaderboards use OrderedDataStores. These MUST be namespaced too.

Store naming pattern used:

- Overall: `LB_OVERALL_<NAMESPACE>_<CATEGORY>`
- Weekly: `LB_WEEKLY_<NAMESPACE>_<WEEKKEY>_<CATEGORY>`

Where CATEGORY is one of `{MaxStreak, GamesPlayed, Donations}`

This prevents Studio leaderboard testing from polluting live leaderboard values.

### 12.4 Verified Behavior

Confirmed via testing:

- Playing matches in Studio writes to DEV datastores.
- Playing the real game writes to PROD datastores.
- The two do not interfere.

---

## 13) UI Direction

- Roblox UI instances
- React-ready boundary enforced
- UIController is sole PlayerGui owner

UI remains presentation-only.  
It must not own:

- gameplay rules
- persistence
- RNG
- authoritative state

---

## 14) Known Polish / Feature Backlog

- waiting experience engagement
- camera micro-artifacts (rare)
- UI animation runtime hardening
- emotional pacing
- Step 11 protection surface
- Step 12 economy HUD surface
- Step 13 lean shop surface

---

## 15) Testing Discipline for Data Systems

**When testing anything data-related:**

1. Verify namespace in output logs:

   - DataService should print connected datastore name including `_DEV` or `_PROD`
   - LeaderboardService should log namespace when reading/writing if DEBUG enabled

2. In Studio, assume:

   - You are safe to create fake population via forced stat changes
   - Any corruption is limited to DEV namespace only

3. In Live:

   - Never change datastore names unless you intentionally want a wipe/migration.

---

## 16) Studio Backend Test Harness

A Studio-only backend harness now exists for fast authoritative backend validation in live Studio runtime.

### Purpose

This harness exists to validate backend correctness through the real server runtime without relying on fragile ad hoc command-bar reads.

It is used for:

- stat mutation verification
- reward payout verification
- VIP multiplier verification
- no-reward branch verification
- live stats inspection
- live monetization inspection

It is **not** used as proof of:

- UI/UX feel
- real 2-player seat/join flow
- replication polish
- Marketplace/live PROD behavior
- final release smoke confidence

### Architectural Rule

`DevTestService` is an orchestrator only.

It may:

- set up scenario inputs
- create harness-local synthetic rivals
- call real authority seams
- snapshot before/after state
- compare expected vs actual deltas
- print PASS/FAIL

It must not:

- become a second gameplay engine
- own payout rules
- own stat mutation
- own monetization rules
- leak synthetic participants into Players, UI, persistence, or leaderboards

### Authority Seams Used

- `StatsService.ApplyRoundResult` remains the authoritative stat mutation seam
- `MonetizationService` remains the authoritative VIP/multiplier seam
- synthetic rivals are plain harness-local tables with negative UserIds
- leaderboard/UI observers must ignore non-Player payloads

### Current Studio-Only Command Surface

#### Legacy dev commands

- `/plugins`
- `/run <pluginName>`
- `/shields <amount>`
- `/gems <amount>`
- `/shieldtest`

#### Harness/debug commands

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

### Studio Automation Note

- current Studio MCP/tooling can start/stop playtests and read output logs
- it cannot directly execute code inside the live play server or inject `player.Chatted` commands during play
- therefore harness commands are normally run manually through Studio chat
- if temporary automation is needed, use a short-lived uncommitted `LocalScript` probe under `StarterPlayerScripts` that sends commands through `TextChatService.TextChannels.RBXGeneral`
- remove the probe after testing
- do not commit the probe or turn it into a permanent/public command surface

### Final Step 10 Verification Notes

- shield-protected single loss was verified not to open restore
- reconnect cleanup for active restore offers remains environment-limited in local Studio and is not treated as a blocker

### Testing Doctrine

Use the harness for backend correctness.  
Use manual playtesting for human-facing validation.

Rule of thumb:

- automate correctness
- manually verify experience

### Data Safety

The harness is Studio-only and must remain DEV-safe.  
It must never become a production/public command surface.

---

END

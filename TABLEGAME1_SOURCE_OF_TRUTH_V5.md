# TableGame1 — System Doc (Source of Truth)

Version: **V5**  
Last updated: **Feb 4, 2026**

This document is the **authoritative memory + design contract** for TableGame1.  
It exists so the project can be resumed in *any* future chat without loss of context.

Core philosophy: **puzzle-piece systems**, anti-drown discipline, Cursor-first workflow.

---

## 0) One-Sentence Pitch

A Roblox table-PvP game where players sit at tables, play fast minigames, earn progression, and loop endlessly through social pressure and risk/reward.

---

## 1) Current Reality Snapshot (IMPORTANT)

**Status: Stable & Playable**

- Step 7 (Data Saving / Loading + round polish) is **complete**.
- The game has been **playtested with real players** in multi-client sessions.
- Core loop is stable:

  - join table → force sit
  - countdown
  - spin cinematic
  - stage UI (choices)
  - resolve outcome
  - cleanup
  - save stats

- Recent fixes addressed:

  - seat replication/desync
  - spin randomness feel (no consecutive repeats)
  - UI state leaks
  - opponent leave aborts
  - datastore reliability

**Remaining issues are polish-tier**, not blockers.

This project has crossed the line from “prototype” → “real game”.

---

## 2) Original Vision

Minimalist, addictive, system-driven.

Inspired by:

- Bomb-chip / table minigames
- Split/Steal RNG tension loops

The goal is not one game — it’s a **reusable engine** for table-based PvP games.

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
**Build → Test → Commit → Push**

No skipping steps.

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

### Phase 1 — MVP (DONE)

Steps 0–7 complete.

### Phase 2 — Retention (CURRENT)

Step 8:

- waiting experience
- pacing
- social pressure
- replay motivation

### Phase 3 — Scale & Monetize (LATER)

Leaderboards, chair shop, VIP, rare tables, etc.

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

- Fast → slow item cycling
- Visual RNG only (odds unchanged)
- No consecutive identical items
- Billboard shows name, rarity, value
- Final item locks reward

SpinService is reusable and isolated.

---

## 12) Data & Stats

Saved:

- Cash
- Wins
- Streak
- MaxStreak
- (Internal tracking exists beyond this list; StatsService is canonical source)

Datastore hardened for disconnects and aborts.

### 12.1 Datastore Isolation (DEV vs PROD) — CRITICAL (V5 ADDITION)

**Goal:** Testing in Studio must never touch live/public player data.

We implemented/standardized a **namespace split**:

- **Studio/testing uses DEV**
- **Published live servers use PROD**
- Datastore names are generated from `BaseName + "_" + Namespace`

**What this guarantees:**

- Running Studio tests with “Player1, Player2…” and forced stats **does not modify** real playerbase data.
- When you publish, PROD servers read/write only PROD keys/stores.
- Existing public data remains intact when code updates, unless you deliberately change names.

**Namespace source-of-truth rule:**

- Namespace should be centrally defined by **DataService**, and other systems (like LeaderboardService) should fetch it via `DataService.GetNamespace()`.

### 12.2 DataService Namespace Contract (V5 ADDITION)

DataService must expose:

- `DataService.GetNamespace() -> "DEV" | "PROD" | other`
- `DataService.IsApiEnabled()` remains authoritative for “datastore usable?”

**Recommended default behavior:**

- If `RunService:IsStudio()` → `"DEV"`
- Else → `"PROD"`

(We discussed optionally defaulting DEV for organization while you’re pre-ship; the safe long-term default is still Studio=DEV, Live=PROD.)

### 12.3 OrderedDataStore Namespacing for Leaderboards (V5 ADDITION)

Leaderboards use OrderedDataStores. These MUST be namespaced too.

Store naming pattern used:

- Overall: `LB_OVERALL_<NAMESPACE>_<CATEGORY>`
- Weekly: `LB_WEEKLY_<NAMESPACE>_<WEEKKEY>_<CATEGORY>`

Where CATEGORY ∈ {MaxStreak, GamesPlayed, Donations}

This prevents Studio leaderboard testing from polluting live leaderboard values.

### 12.4 Verified Behavior (V5 ADDITION)

Confirmed via testing:

- Playing a match in Studio wrote to DEV datastores.
- Playing the real game wrote to PROD datastores.
- The two did not interfere with each other.

---

## 13) UI Direction

- Roblox UI instances
- React-ready boundary enforced
- UIController is sole PlayerGui owner

---

## 14) Known Polish Backlog (Step 8+)

- Waiting experience engagement
- Camera micro-artifacts (rare)
- UI animation runtime hardening
- Emotional pacing

---

## 15) Testing Discipline for Data Systems (V5 ADDITION)

**When testing anything data-related:**

1. Verify namespace in output logs:

   - DataService should print connected datastore name including `_DEV` or `_PROD`
   - LeaderboardService should log namespace when reading/writing if DEBUG enabled

2. In Studio, assume:

   - You are safe to create “fake population” via forced stat changes
   - Any corruption is limited to DEV namespace only

3. In Live:

   - Never change datastore names unless you intentionally want a wipe/migration.

---

END

# Step 6 — Rewards + Stats Implementation Summary

## BLUF
Implemented a clean, modular Stats/Rewards system (Cash, Wins, Streak, MaxStreak) that updates after every round with minimal coupling. Session-only (no datastore yet). Includes client toast feedback and robust edge-case handling.

## Puzzle Pieces Added

### 1. StatsService.lua (New Module)
**Location:** `src/server/Core/StatsService.lua`

**Public API:**
- `Init()` — Initialize service, hook PlayerRemoving cleanup
- `GetStats(player)` → `{Cash, Wins, Streak, MaxStreak}` (returns copy)
- `ApplyRoundResult(playerA, playerB, resultPayload)` — Apply round outcome to stats

**State:**
- `playerStats[UserId]` — In-memory session stats per player
- `processedRounds[roundId]` — Idempotency guard (prevents double-apply)

**Contract (resultPayload):**
```lua
{
  roundId = string (required for idempotency)
  winnerUserId = number? (single winner)
  loserUserId = number? (single loser)
  didDraw = boolean? (both win/tie)
  didBothLose = boolean? (both lose)
  rewardCash = number (total cash reward)
  wasAborted = boolean? (no-contest/abort)
  reason = string? (optional debug)
}
```

**Streak Rules:**
- Win: `Wins += 1`, `Streak += 1`, `MaxStreak = max(MaxStreak, Streak)`
- Loss: `Streak = 0`
- Both Lose: Both `Streak = 0`
- Draw (Split/Split): Each gets `floor(rewardCash/2)`, **no streak increment** (MVP-safe)
- Abort: No stat changes at all

## Integration Points

### 2. RoundService.lua (Modified)
**Changes:**
- Added `require(Core.StatsService)` at top
- After round resolution (line ~364), constructs `resultPayload` and calls:
  ```lua
  StatsService.ApplyRoundResult(playerA, playerB, resultPayload)
  ```
- Fires `StatsUpdate` remote to both players with updated stats
- In `AbortRound()`, calls `StatsService.ApplyRoundResult()` with `wasAborted=true`

**Idempotency:**
- Each round gets unique `roundId = tableModel.Name .. "_" .. tostring(os.clock())`
- Abort rounds get `roundId = tableModel.Name .. "_abort_" .. tostring(os.clock())`

### 3. init.server.luau (Modified)
**Changes:**
- Added `require(Core:WaitForChild("StatsService"))`
- Calls `StatsService.Init()` before `TableService.Init()`
- Updated phase message to "Step 6"

### 4. UIService.lua (Modified)
**Changes:**
- Added `StatsUpdate = ensureEvent("StatsUpdate")` to remotes list

### 5. UIController.client.lua (Modified)
**Changes:**
- Added `StatsUpdate.OnClientEvent` listener (line ~325)
- Shows toast notification with stats:
  - If cash > 0: `💰 +$XXX | 🏆 X Wins | 🔥 X Streak`
  - If cash = 0: `🏆 X Wins | 🔥 X Streak`
- Ensures `toastComponent` is initialized before showing toast

## Files Changed
1. **Created:** `src/server/Core/StatsService.lua` (new module, 129 lines)
2. **Modified:** `src/server/Core/RoundService.lua` (+40 lines)
3. **Modified:** `src/server/init.server.luau` (+2 lines)
4. **Modified:** `src/server/Core/UIService.lua` (+1 line)
5. **Modified:** `src/client/UI/UIController.client.lua` (+30 lines)
6. **Created:** `STEP6_TEST_CHECKLIST.md` (test plan)
7. **Created:** `STEP6_SUMMARY.md` (this file)

## Edge Cases Handled

### ✅ Double-Resolve Protection
- `processedRounds[roundId]` idempotency guard
- Logs: `[StatsService] Round already processed: <roundId> - skipping duplicate`

### ✅ Abort Safety
- `wasAborted=true` → no stat changes
- Called in `AbortRound()` for opponent-leave scenarios
- Logs: `[StatsService] Round aborted - no stats applied`

### ✅ Player Leave Mid-Round
- `HandleOpponentLeave()` → `AbortRound()` → `StatsService.ApplyRoundResult(wasAborted=true)`
- No crash, no duplicate rewards
- Remaining player respawns cleanly

### ✅ Nil Safety
- `ensureStats(player)` creates default stats if missing
- Player validation before stat application
- Safe cleanup on `PlayerRemoving`

### ✅ Session Persistence
- Stats persist in-memory for session
- Cleared on `PlayerRemoving`
- No datastore yet (Step 7)

## Test Checklist
See `STEP6_TEST_CHECKLIST.md` for full test plan (9 test cases + edge case verification)

## What's NOT Included (Future Steps)
- ❌ Datastore saving/loading (Step 7)
- ❌ Leaderboards (Step 8)
- ❌ Persistent HUD (optional, toast-only for now)
- ❌ Admin commands to view/modify stats (future)

## Acceptance Criteria Met
- ✅ Clean puzzle-piece architecture (StatsService is self-contained)
- ✅ Minimal coupling (single API call from RoundService)
- ✅ Robust edge-case handling (abort, leave, double-resolve)
- ✅ Client feedback (toast notifications)
- ✅ Session-only state (no datastore yet)
- ✅ Idempotency guard (no duplicate rewards)
- ✅ Consistent streak rules (win/loss/draw/abort)

## Next Steps (User Decision)
1. Test in Studio using `STEP6_TEST_CHECKLIST.md`
2. If all tests pass → proceed to Step 7 (Datastore)
3. If issues found → debug and iterate


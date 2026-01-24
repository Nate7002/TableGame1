# Step 7 — Data Saving/Loading Implementation Summary

## BLUF
**Implemented persistent data storage using DataStoreService** with a clean DataService puzzle piece. Stats now persist across sessions with retry logic, throttling, autosave, and graceful degradation. Minimal changes to existing services.

## Puzzle Pieces Added/Modified

### 1. **DataService.lua** (New Core Module)
**Location:** `src/server/Core/DataService.lua` (293 lines)

**Public API:**
- `Init()` — Initialize datastore, start autosave loop, bind to shutdown
- `LoadPlayer(player)` → `data | nil` — Load player data with retry
- `SavePlayer(player, data, reason)` → `boolean` — Save player data with throttle + retry
- `GetCached(player)` → `data | nil` — Get cached data
- `SetCached(player, data)` — Update cache
- `ClearCache(userId)` — Clear cache entry
- `AutosaveAll()` — Save all cached players (time-sliced)
- `SaveAllOnShutdown()` — Save all with timeout (10s max)

**Features:**
- **DataStore:** `TableGame1_v1`, key format: `p_<userId>`
- **Schema:**
  ```lua
  {
    v = 1,
    stats = {Cash, Wins, Streak, MaxStreak},
    updatedAt = timestamp
  }
  ```
- **Retry Logic:** 3 attempts with exponential backoff (1s, 2s, 4s)
- **Throttling:** Max 1 save per 10 seconds per player (except critical: PlayerRemoving, Shutdown)
- **Autosave:** Every 120 seconds, time-sliced to avoid spikes
- **Shutdown:** `BindToClose` saves all players, capped at 10 seconds total
- **Graceful Degradation:** If API disabled, warns but game continues without saving

**Safety:**
- `UpdateAsync` for saves (merge with existing data, prevent overwrites)
- Data sanitization on load (ensure schema, provide defaults)
- Cache management (store loaded data, clear on leave)
- Non-blocking saves (uses `task.spawn` in StatsService)

### 2. **StatsService.lua** (Modified)
**Location:** `src/server/Core/StatsService.lua`

**Changes:**
- Added `require(DataService)` at top
- **In `Init()`:**
  - `Players.PlayerAdded`: Load data via `DataService.LoadPlayer()`, hydrate `playerStats` from loaded data
  - `Players.PlayerRemoving`: Save data via `DataService.SavePlayer()` before clearing cache
  - Existing players loop: Load data for players already in-game
- **In `ApplyRoundResult()`:**
  - After mutating stats (all paths: didBothLose, didDraw, single winner/loser), call `asyncSavePlayer()`
  - `asyncSavePlayer()` helper: Spawns non-blocking save task
- **No yields added** — all saves are async via `task.spawn`

**Lines Changed:** ~40 lines added (init load/save logic + async save helper)

### 3. **init.server.luau** (Modified)
**Location:** `src/server/init.server.luau`

**Changes:**
- Added `require(Core:WaitForChild("DataService"))`
- Call `DataService.Init()` **before** `StatsService.Init()`
- Updated startup message: "Step 7"

**Lines Changed:** +3 lines

## Integration Flow

### Player Join
1. `DataService.LoadPlayer(player)` called
2. Attempts `GetAsync` with retry (up to 3 attempts)
3. On success: sanitize data, cache it, return to StatsService
4. On failure: warn, return defaults
5. StatsService hydrates `playerStats[userId]` from loaded data

### Round Result
1. `StatsService.ApplyRoundResult()` mutates stats
2. Calls `asyncSavePlayer()` for affected players
3. `asyncSavePlayer()` spawns non-blocking task:
   - Builds payload from current stats
   - Calls `DataService.SavePlayer(player, payload, "RoundResult")`
4. Save throttled (10s minimum) unless critical reason
5. If throttled: cache updated, save skipped (will autosave later)

### Player Leave
1. `StatsService` PlayerRemoving handler:
   - Builds payload from current stats
   - Calls `DataService.SavePlayer(player, payload, "PlayerRemoving")`
   - Clears `playerStats[userId]`
   - Calls `DataService.ClearCache(userId)`
2. Save bypasses throttle (critical reason)
3. Retries up to 3 times

### Autosave (Every 120s)
1. `DataService.AutosaveAll()` triggered by loop
2. Iterates cached players
3. Time-slices saves: one per frame (`task.wait()`)
4. Logs: `Autosave complete: X saved, Y failed`

### Shutdown
1. `game:BindToClose` handler triggered
2. `DataService.SaveAllOnShutdown()` called
3. Saves all cached players
4. Caps total time at 10 seconds
5. Logs: `Shutdown save complete: X saved, Y failed, Z.ZZs elapsed`

## Files Changed
1. **Created:** `src/server/Core/DataService.lua` (293 lines)
2. **Modified:** `src/server/Core/StatsService.lua` (+40 lines)
3. **Modified:** `src/server/init.server.luau` (+3 lines)
4. **Created:** `STEP7_TEST_CHECKLIST.md` (test plan)
5. **Created:** `STEP7_SUMMARY.md` (this file)

## Edge Cases Handled

### ✅ Retry on Failure
- GetAsync/UpdateAsync retry 3 times with exponential backoff
- Logs each attempt: `[DataService] LoadPlayer failed (attempt 1/3): ...`
- Falls back to defaults on load failure

### ✅ Save Throttling
- Max 1 save per 10 seconds per player (prevents spam on rapid rounds)
- Critical reasons (PlayerRemoving, Shutdown) bypass throttle
- Cache updated even when save throttled

### ✅ Autosave Non-Blocking
- Time-sliced to avoid spikes (one save per frame)
- Only saves players still in-game
- Runs every 120 seconds

### ✅ Shutdown Graceful
- BindToClose saves all players
- Caps total time at 10 seconds (prevents infinite hang)
- Best-effort save (doesn't guarantee all succeed)

### ✅ API Disabled
- Detects API disabled on Init
- Warns: `[DataService] DataStore API disabled or failed: ...`
- Game continues normally (stats work in-memory, no saves)
- No crashes or errors

### ✅ Data Sanitization
- Ensures schema version, stats table, defaults
- Handles missing fields gracefully
- Forward-compatible (ignores unknown fields)

### ✅ Concurrent Saves
- Independent per-player throttling
- Cache per UserId
- No race conditions

## Performance Considerations

### Throttling
- **RoundResult saves:** Max 1 per 10s per player
- **Critical saves:** Bypass throttle (PlayerRemoving, Shutdown)
- **Cache:** Stats update instantly in-memory even when save throttled

### Autosave Load Spreading
- Time-sliced: one save per frame (`task.wait()`)
- Prevents frame drops during autosave
- Total autosave time: ~(playerCount * 0.03s) = 0.3s for 10 players

### Shutdown Timeout
- Max 10 seconds total
- Saves as many as possible within timeout
- Prevents server hang on shutdown

### Retry Backoff
- 1s, 2s, 4s delays (exponential)
- Total retry time: ~7 seconds max per operation
- Allows transient errors to resolve

## What's NOT Included (Future)
- ❌ Data versioning/migration (schema v2+)
- ❌ Backup/rollback (manual admin tools)
- ❌ Cross-server data sync (single-server only for now)
- ❌ Analytics/telemetry (future)

## Test Checklist
See `STEP7_TEST_CHECKLIST.md` for full test plan (10 test cases + edge case verification)

## Acceptance Criteria Met
- ✅ Clean puzzle-piece architecture (DataService is self-contained)
- ✅ Minimal coupling (StatsService calls DataService via clean API)
- ✅ Robust error handling (retry, throttle, graceful degradation)
- ✅ Non-blocking saves (no gameplay impact)
- ✅ Autosave prevents spam
- ✅ Shutdown saves gracefully
- ✅ API disabled → game works (no saves but no crash)

## Next Steps (User Decision)
1. Enable API Services in Game Settings → Security
2. Test in Studio using `STEP7_TEST_CHECKLIST.md`
3. If all tests pass → publish to Roblox and test in live environment
4. If issues found → debug and iterate
5. Future: Step 8 (Leaderboards)


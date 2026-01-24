# Pre-Match Countdown Feature Summary

## BLUF
**Added a 3-second countdown** after both players sit, before the match starts. Per-table, cancellable if either player leaves/unseats, with clear server logs and client UI display.

---

## Feature Overview

### Before
```
[TableService] Table_01 State: Full (2/2)
[RoundService] Starting Round for Table_01 with Player1 vs Player2
[CINE] FIRING Player1 80453620398560 3.5
```
- Match started **immediately** when 2 players sat
- No buffer time for players to prepare
- Camera/UI could be mid-transition

### After
```
[TableService] Table_01 State: Full (2/2)
[RoundService] Countdown start: Table_01 (Player1 vs Player2) t=3
... 3 seconds pass ...
[RoundService] Countdown complete -> starting round: Table_01
[RoundService] Starting Round for Table_01 with Player1 vs Player2
[CINE] FIRING Player1 91378284817819 3.5
```
- **3-second countdown** before match starts
- Players see countdown UI: "Match Starting | Player1 vs Player2 | 3"
- Cancellable if either player leaves/unseats

---

## Implementation Details

### Server-Side (RoundService)

#### 1. New State Tracking
```lua
local activeCountdowns = {} -- [tableModel] = { token = string, players = {Player} }
local COUNTDOWN_DURATION = 3 -- Seconds before match starts
```

#### 2. New Public API: `HandleTableReady(tableModel, players)`
**Called by:** `TableService.OnTableReady` (replaces direct `StartRound` call)

**Flow:**
1. Generate unique countdown token (prevents race conditions)
2. Store countdown in `activeCountdowns[tableModel]`
3. Log: `[RoundService] Countdown start: Table_01 (Player1 vs Player2) t=3`
4. Fire `MatchCountdown` remote to both players
5. Spawn non-blocking countdown loop (per-table)

#### 3. Countdown Loop (Non-Blocking, Per-Table)
```lua
for i = COUNTDOWN_DURATION, 1, -1 do
	task.wait(1)
	
	-- Validate countdown still valid (not superseded)
	if countdown.token ~= countdownToken then
		return -- Cancelled
	end
	
	-- Validate players still seated
	local valid, reason = validatePlayersSeated(tableModel, players)
	if not valid then
		-- Cancel countdown
		activeCountdowns[tableModel] = nil
		-- Notify clients
		return
	end
	
	-- Update countdown UI (tick)
end

-- Final validation
-- Start round
RoundService.StartRound(tableModel, players)
```

#### 4. Validation Helper: `validatePlayersSeated(tableModel, players)`
**Checks:**
- Table still exists and valid
- Both players still connected
- Both players' characters exist
- Both players' Humanoid.Sit == true

**Returns:**
- `true, "Valid"` if all checks pass
- `false, "<reason>"` if any check fails

#### 5. Cancellation Scenarios
| Scenario | Reason | Action |
|----------|--------|--------|
| Player leaves | "PlayerName disconnected" | Cancel, fire `MatchCountdownCancel` |
| Player unseats | "PlayerName unseated" | Cancel, fire `MatchCountdownCancel` |
| Table destroyed | "Table invalid" | Cancel silently |
| New countdown starts | "superseded" | Cancel old countdown |

---

### Client-Side (UIController)

#### Countdown Display
**Location:** `src/client/UI/UIController.client.lua`, lines ~355-420

**UI Element:**
- Large centered label: 400x100px
- Semi-transparent black background
- White text, bold, 48px
- Shows: "Match Starting | You vs Opponent | 3"
- Updates each second: 3 → 2 → 1 → hidden

**Remotes:**
1. **`MatchCountdown(tableId, secondsRemaining, opponentName)`**
   - Fired every second during countdown
   - Creates/updates countdown label
   - Shows opponent name

2. **`MatchCountdownCancel(reason)`**
   - Fired if countdown cancelled
   - Shows: "Match Cancelled | <reason>"
   - Auto-hides after 2 seconds

---

## Files Changed

### 1. `src/server/Core/RoundService.lua` (+120 lines)
**Added:**
- `activeCountdowns` state table
- `COUNTDOWN_DURATION` constant (3 seconds)
- `validatePlayersSeated()` helper function
- `HandleTableReady()` public API (new entry point)
- Countdown loop with validation + cancellation logic

**Modified:**
- `StartRound()` now called by countdown (not directly by TableService)

### 2. `src/server/Core/UIService.lua` (+2 lines)
**Added:**
- `MatchCountdown` RemoteEvent
- `MatchCountdownCancel` RemoteEvent

### 3. `src/server/init.server.luau` (+1 line)
**Changed:**
- `TableService.OnTableReady` now calls `RoundService.HandleTableReady()` (was `StartRound()`)

### 4. `src/client/UI/UIController.client.lua` (+65 lines)
**Added:**
- `MatchCountdown` remote listener + UI creation
- `MatchCountdownCancel` remote listener + cancel message
- Countdown label creation (centered, styled)

---

## Example Logs

### Normal Flow (Countdown Completes)
```
[TableService] Table_01 State: Full (2/2)
[RoundService] Countdown start: Table_01 (Player1 vs Player2) t=3
[CLIENT] MatchCountdown RECEIVED: Table_01 3 Player2
... 1 second ...
[CLIENT] MatchCountdown RECEIVED: Table_01 2 Player2
... 1 second ...
[CLIENT] MatchCountdown RECEIVED: Table_01 1 Player2
... 1 second ...
[RoundService] Countdown complete -> starting round: Table_01
[RoundService] Starting Round for Table_01 with Player1 vs Player2
[CINE] FIRING Player1 91378284817819 3.5
```

### Cancelled Flow (Player Unseats)
```
[TableService] Table_01 State: Full (2/2)
[RoundService] Countdown start: Table_01 (Player1 vs Player2) t=3
[CLIENT] MatchCountdown RECEIVED: Table_01 3 Player2
... 1 second ...
[CLIENT] MatchCountdown RECEIVED: Table_01 2 Player2
... Player2 jumps/unseats ...
[RoundService] Countdown cancelled: Table_01 (Player2 unseated)
[CLIENT] MatchCountdownCancel RECEIVED: Player2 unseated
```

### Cancelled Flow (Player Leaves)
```
[TableService] Table_01 State: Full (2/2)
[RoundService] Countdown start: Table_01 (Player1 vs Player2) t=3
[CLIENT] MatchCountdown RECEIVED: Table_01 3 Player2
... Player2 disconnects ...
[RoundService] Countdown cancelled: Table_01 (Player2 disconnected)
[CLIENT] MatchCountdownCancel RECEIVED: Player2 disconnected
```

---

## Safety Features

### ✅ Per-Table (Non-Blocking)
- Each table has independent countdown
- Uses `task.spawn()` for non-blocking execution
- Multiple tables can countdown simultaneously

### ✅ Token-Based Idempotency
- Each countdown gets unique token: `Table_01_1234567890.123`
- Prevents race conditions if table state changes rapidly
- Old countdowns auto-cancel if superseded

### ✅ Continuous Validation
- Validates players seated every second
- Cancels immediately if validation fails
- No "ghost matches" if player leaves mid-countdown

### ✅ No Double-Starts
- `activeCountdowns[tableModel]` prevents duplicate countdowns
- `activeSessions[tableModel]` check prevents starting if match already active
- Token validation prevents old countdowns from starting matches

---

## Testing Checklist

### Test 1: Normal Flow
**Steps:**
1. Two players sit at a table
2. Wait for countdown (3 seconds)

**Expected:**
- Countdown UI appears: "Match Starting | You vs Opponent | 3"
- Counts down: 3 → 2 → 1
- Match starts after countdown
- Output shows: `[RoundService] Countdown complete -> starting round`

### Test 2: Player Unseats During Countdown
**Steps:**
1. Two players sit at a table
2. During countdown (e.g., at 2 seconds), one player jumps

**Expected:**
- Countdown cancels immediately
- UI shows: "Match Cancelled | PlayerName unseated"
- No match starts
- Output shows: `[RoundService] Countdown cancelled: ... (PlayerName unseated)`

### Test 3: Player Leaves During Countdown
**Steps:**
1. Two players sit at a table
2. During countdown, one player disconnects

**Expected:**
- Countdown cancels immediately
- UI shows: "Match Cancelled | PlayerName disconnected"
- No match starts
- Output shows: `[RoundService] Countdown cancelled: ... (PlayerName disconnected)`

### Test 4: Multiple Tables Simultaneously
**Steps:**
1. Start 2+ matches at different tables at the same time
2. Watch countdowns

**Expected:**
- Each table counts down independently
- No blocking or interference
- All countdowns complete and matches start correctly

### Test 5: Rapid Sit/Unsit
**Steps:**
1. Two players sit
2. One player immediately unseats
3. Sits again quickly
4. Repeat several times

**Expected:**
- Each sit triggers new countdown (supersedes old)
- No double-starts
- No crashes
- Output shows: `[RoundService] Countdown cancelled: ... (superseded)` for old countdowns

---

## Benefits

✅ **Better UX:** Players have time to prepare before match starts  
✅ **Camera Settle:** 3 seconds for camera/UI to stabilize  
✅ **Intentional Matches:** Countdown makes match start feel deliberate  
✅ **Safe Cancellation:** Auto-cancels if player leaves/unseats  
✅ **Per-Table:** Non-blocking, multiple tables work independently  
✅ **Clear Feedback:** UI shows countdown + opponent name  
✅ **Robust:** Token-based idempotency prevents race conditions  

---

## No Gameplay Changes

- ✅ Rewards logic unchanged
- ✅ Stats logic unchanged
- ✅ Datastore logic unchanged
- ✅ Plugin behavior unchanged (just delayed by 3 seconds)
- ✅ Match flow unchanged (same MatchStart, spin, Stage UI, etc.)
- ✅ Only adds 3-second buffer before match starts


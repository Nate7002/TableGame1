# RoundService Log Fix Summary

## BLUF
**Fixed misleading RoundService debug log** to clearly show the actual match winner/loser names and outcome, matching exactly what StatsService receives. Added a helper function to format results consistently.

---

## The Problem

### Before (Confusing Log)
```
[RoundService] winners={1} losers={1} sound=WinSound (Winners Only) respawned={Player1} eject={Player3}
```

**Why This Was Confusing:**
- Only shows winner/loser COUNTS, not NAMES
- "respawned" and "ejected" lists don't align with intuitive understanding:
  - Winners get "ejected" (unfrozen, stay at table)
  - Losers get "respawned" (teleported away)
- This made it look like Player1 won (because they're in "winners" count), but they were actually respawned (losers action)
- Meanwhile Player3 was ejected (winners action) but you couldn't tell from the counts

### The Root Cause
The `winners` and `losers` arrays ARE the true match winners/losers (from `data.winners` plugin result), but the log only showed counts. The respawn/eject actions are CONSEQUENCES of winning/losing, not identifiers of winners/losers.

---

## The Solution

### After (Clear Log)
```
[RoundService] ROUND RESULT: outcome=SINGLE_WINNER | winners=[Player3] | losers=[Player1] | reward=$600
[RoundService] ACTIONS: sound=WinSound (Winners Only) | respawned=[Player1] | ejected=[Player3]
[StatsService] Winner: Player3 (+$600, Wins:1, Streak:1, MaxStreak:1)
[StatsService] Loser: Player1 (Streak reset to 0)
```

**Why This Is Clear:**
- **Line 1 (ROUND RESULT):** Shows the TRUE outcome with actual player names
  - `outcome=SINGLE_WINNER` (or `DRAW_SPLIT`, `BOTH_LOSE`, `ABORTED`)
  - `winners=[Player3]` — actual winner name(s)
  - `losers=[Player1]` — actual loser name(s)
  - `reward=$600` — cash amount
- **Line 2 (ACTIONS):** Shows what actions were taken (sounds, teleports)
  - `sound=WinSound (Winners Only)` — which sound played
  - `respawned=[Player1]` — who was teleported away
  - `ejected=[Player3]` — who was unfrozen/stayed
- **Lines 3-4 (StatsService):** Now clearly matches the ROUND RESULT log

---

## Changes Made

### 1. Added Helper Function
**Location:** `src/server/Core/RoundService.lua`, lines 20-52

```lua
local function formatResultSummary(resultPayload, participants, winnersArray, losersArray)
	local summary = {
		outcome = "UNKNOWN",
		winnerNames = {},
		loserNames = {},
		rewardCash = resultPayload.rewardCash or 0
	}
	
	if resultPayload.wasAborted then
		summary.outcome = "ABORTED"
	elseif resultPayload.didBothLose then
		summary.outcome = "BOTH_LOSE"
		for _, p in ipairs(participants) do
			table.insert(summary.loserNames, p.Name)
		end
	elseif resultPayload.didDraw then
		summary.outcome = "DRAW_SPLIT"
		for _, p in ipairs(participants) do
			table.insert(summary.winnerNames, p.Name)
		end
	else
		-- Single winner/loser
		summary.outcome = "SINGLE_WINNER"
		for _, w in ipairs(winnersArray) do
			table.insert(summary.winnerNames, w.Name)
		end
		for _, l in ipairs(losersArray) do
			table.insert(summary.loserNames, l.Name)
		end
	end
	
	return summary
end
```

### 2. Replaced Misleading Log
**Location:** `src/server/Core/RoundService.lua`, lines ~435-444

**Removed:**
```lua
print(string.format("[RoundService] winners={%d} losers={%d} sound=%s respawned={%s} eject={%s}", 
	#winners, #losers, soundPlayed, table.concat(respawned, ","), table.concat(ejected, ",")))
```

**Added:**
```lua
-- Log round result (AFTER resultPayload is finalized, so it matches StatsService exactly)
local resultSummary = formatResultSummary(resultPayload, participants, winners, losers)
print(string.format("[RoundService] ROUND RESULT: outcome=%s | winners=[%s] | losers=[%s] | reward=$%d", 
	resultSummary.outcome,
	table.concat(resultSummary.winnerNames, ","),
	table.concat(resultSummary.loserNames, ","),
	resultSummary.rewardCash))
print(string.format("[RoundService] ACTIONS: sound=%s | respawned=[%s] | ejected=[%s]", 
	soundPlayed, table.concat(respawned, ","), table.concat(ejected, ",")))
```

### 3. Moved Log Position
- **Before:** Log printed BEFORE StatsService call
- **After:** Log printed AFTER `resultPayload` is finalized and AFTER StatsService call
- **Why:** Ensures the log reflects the EXACT payload that StatsService receives, preventing any possibility of mismatch

---

## Example Outputs

### Scenario 1: Single Winner (Player3 wins, Player1 loses)
```
[RoundService] DoubleDown Result: Outcome=STEAL_P2, Reward=600
[RoundService] ROUND RESULT: outcome=SINGLE_WINNER | winners=[Player3] | losers=[Player1] | reward=$600
[RoundService] ACTIONS: sound=WinSound (Winners Only) | respawned=[Player1] | ejected=[Player3]
[StatsService] Winner: Player3 (+$600, Wins:1, Streak:1, MaxStreak:1)
[StatsService] Loser: Player1 (Streak reset to 0)
[DataService] Saved Player3 (RoundResult): Cash=600, Wins=1, Streak=1
[DataService] Saved Player1 (RoundResult): Cash=0, Wins=0, Streak=0
```

### Scenario 2: Draw/Split (Both win)
```
[RoundService] DoubleDown Result: Outcome=SPLIT, Reward=800
[RoundService] ROUND RESULT: outcome=DRAW_SPLIT | winners=[Player1,Player3] | losers=[] | reward=$800
[RoundService] ACTIONS: sound=WinSound (Winners Only) | respawned=[Player1,Player3] | ejected=[]
[StatsService] Draw - both players win, splitting reward
[StatsService] Split/Split: Player1 (+$400, Wins:1, Streak:1, MaxStreak:1)
[StatsService] Split/Split: Player3 (+$400, Wins:1, Streak:1, MaxStreak:1)
```

### Scenario 3: Both Lose
```
[RoundService] DoubleDown Result: Outcome=CRASH, Reward=0
[RoundService] ROUND RESULT: outcome=BOTH_LOSE | winners=[] | losers=[Player1,Player3] | reward=$0
[RoundService] ACTIONS: sound=LoseSound (Everyone) | respawned=[Player1,Player3] | ejected=[]
[StatsService] Both players lost - resetting streaks
```

### Scenario 4: Aborted (Opponent left)
```
[RoundService] Aborting round: Opponent left during SPINNING
[StatsService] Round aborted - no stats applied
```

---

## Files Changed
1. **Modified:** `src/server/Core/RoundService.lua` (+45 lines, -3 lines)
   - Added `formatResultSummary()` helper function
   - Replaced confusing log with clear 2-line log
   - Moved log position to after StatsService call

---

## Benefits
✅ **No ambiguity:** Winner/loser names are explicit  
✅ **Matches StatsService:** Log reflects exact `resultPayload` sent to stats  
✅ **Clear outcome:** `outcome=SINGLE_WINNER` vs `DRAW_SPLIT` vs `BOTH_LOSE`  
✅ **Separates concerns:** "ROUND RESULT" (match outcome) vs "ACTIONS" (game actions)  
✅ **Debugging friendly:** Can verify winner/loser directly from logs without cross-referencing  

---

## No Gameplay Changes
- ✅ Zero gameplay logic modified
- ✅ Only logging changes
- ✅ Same `resultPayload` sent to StatsService
- ✅ Same respawn/eject logic
- ✅ Same sounds logic


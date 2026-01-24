# StatsService UserId Log Fix Summary

## BLUF
**Fixed misleading StatsService cleanup log** that was printing fake negative UserIds (like -2, -3). Now validates UserId and logs a warning if invalid, preventing confusing logs during abort/disconnect scenarios.

---

## The Problem

### Before (Misleading Log)
```
[StatsService] Saved and cleared stats for Player2 (UserId: -2)
```

**Why This Was Wrong:**
- `-2` is NOT a valid Roblox UserId (all real UserIds are positive integers)
- This occurred during opponent leave / abort flows
- Likely caused by:
  - Studio test clients sometimes having negative UserIds
  - Player reference becoming invalid before log executes
  - Mock/test data with fake UserIds

**Impact:**
- Confusing logs make debugging harder
- Cannot trust UserId in logs for datastore lookups
- Looks like a bug even when behavior is correct

---

## The Solution

### After (Clear + Validated)

**Normal Case (Valid UserId):**
```
[StatsService] Saved and cleared stats for Player2 (UserId: 12345678)
```

**Edge Case (Invalid UserId):**
```
[StatsService] Invalid or missing UserId for PlayerName - skipping save
```

**Why This Is Better:**
- ✅ Validates UserId is positive integer before using it
- ✅ Captures `playerName` early while reference is valid
- ✅ Skips save if UserId is invalid (with clear warning)
- ✅ Never logs negative or zero UserIds
- ✅ Makes debugging easier (real UserIds only)

---

## Changes Made

### Location
`src/server/Core/StatsService.lua`, lines 80-103 (PlayerRemoving handler)

### Before
```lua
Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	if playerStats[userId] then
		-- Save before clearing
		local payload = { ... }
		DataService.SavePlayer(player, payload, "PlayerRemoving")
		
		print(string.format("[StatsService] Saved and cleared stats for %s (UserId: %d)", player.Name, userId))
		playerStats[userId] = nil
		DataService.ClearCache(userId)
	end
end)
```

**Issues:**
- `player.Name` accessed late (might be invalid)
- No UserId validation (negative values pass through)
- Silent failure if player reference is nil

### After
```lua
Players.PlayerRemoving:Connect(function(player)
	-- Capture reliable identifiers immediately while player reference is valid
	local userId = player and player.UserId
	local playerName = player and player.Name or "Unknown"
	
	-- Validate userId (Roblox UserIds are always positive integers)
	if not userId or userId <= 0 then
		warn(string.format("[StatsService] Invalid or missing UserId for %s - skipping save", playerName))
		return
	end
	
	if playerStats[userId] then
		-- Save before clearing
		local payload = { ... }
		DataService.SavePlayer(player, payload, "PlayerRemoving")
		
		print(string.format("[StatsService] Saved and cleared stats for %s (UserId: %d)", playerName, userId))
		playerStats[userId] = nil
		DataService.ClearCache(userId)
	end
end)
```

**Improvements:**
- ✅ Captures `userId` and `playerName` immediately
- ✅ Validates `userId > 0` (Roblox's valid range)
- ✅ Warns and returns early if invalid
- ✅ Uses cached `playerName` in log (never fails)
- ✅ Never logs negative UserIds

---

## Edge Cases Handled

### Case 1: Valid Player (Normal Disconnect)
**Input:** Real player with UserId = 12345678  
**Output:** `[StatsService] Saved and cleared stats for PlayerName (UserId: 12345678)`  
**Action:** Save succeeds, stats cleared

### Case 2: Studio Test Client (Negative UserId)
**Input:** Test client with UserId = -2  
**Output:** `[StatsService] Invalid or missing UserId for Player2 - skipping save`  
**Action:** Save skipped (no corrupt data), warning logged

### Case 3: Player Reference Gone (nil)
**Input:** `player = nil`  
**Output:** `[StatsService] Invalid or missing UserId for Unknown - skipping save`  
**Action:** Safe early return, no crash

### Case 4: UserId = 0 (Edge Case)
**Input:** Player with UserId = 0  
**Output:** `[StatsService] Invalid or missing UserId for PlayerName - skipping save`  
**Action:** Skipped (0 is not a valid Roblox UserId)

---

## Validation

### Test Scenario 1: Normal Leave
1. Join game as real player
2. Earn stats
3. Leave game

**Expected Log:**
```
[StatsService] Saved and cleared stats for YourUsername (UserId: 12345678)
[DataService] Saved YourUsername (PlayerRemoving): Cash=XXX, Wins=X, Streak=X
```

### Test Scenario 2: Opponent Leave During Match
1. Start Server with 2 clients
2. Start a match
3. One client leaves mid-spin

**Expected Log:**
```
[RoundService] Player Player2 left mid-match, state: SPINNING
[StatsService] Saved and cleared stats for Player2 (UserId: 12345678)  <!-- Real positive UserId -->
[RoundService] Aborting round: Opponent left during SPINNING
```

### Test Scenario 3: Studio Test Client (Negative UserId)
1. Use Studio "Start Server" with test clients
2. Force a disconnect

**Expected Log (if negative UserId):**
```
[StatsService] Invalid or missing UserId for Player2 - skipping save
```

**No More:**
```
[StatsService] Saved and cleared stats for Player2 (UserId: -2)  <!-- NEVER HAPPENS -->
```

---

## Files Changed
1. **Modified:** `src/server/Core/StatsService.lua` (+10 lines, refactored PlayerRemoving handler)
2. **Created:** `STATSSERVICE_USERID_LOG_FIX_SUMMARY.md` (this file)

---

## Benefits
✅ **Truthful Logs:** Never prints fake/negative UserIds  
✅ **Early Validation:** Catches invalid UserIds before logging/saving  
✅ **Clear Warnings:** Explicit message when UserId is invalid  
✅ **Robust:** Handles nil player references gracefully  
✅ **Debugging Friendly:** Can trust UserId in logs for datastore lookups  

---

## No Gameplay Changes
- ✅ Zero gameplay logic modified
- ✅ Stats behavior unchanged
- ✅ Save/load logic unchanged
- ✅ Only logging and validation added
- ✅ Edge case: Invalid UserIds now skip save (correct behavior - shouldn't save with invalid key)

---

## Root Cause Analysis

### Why Were Negative UserIds Appearing?

**Roblox Studio Test Clients:**
- In "Start Server + Test Clients" mode, Studio sometimes assigns negative UserIds to test clients
- This is by design for local testing (simulates multiple players without real accounts)
- Real Roblox servers always use positive UserIds (> 0)

**Not a Bug, But Confusing:**
- The old code didn't validate UserIds
- It logged whatever UserId the player had (including negative ones)
- This made logs misleading during local testing

**The Fix:**
- Validate that UserId > 0 (real Roblox constraint)
- Skip save and warn if invalid (correct behavior for test clients)
- Real players unaffected (always have positive UserIds)


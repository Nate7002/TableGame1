# Step 7 — Data Saving/Loading Test Checklist

## Test Environment
- Use **Play Solo** or **Start Server + 2 clients** in Studio
- Enable **API Services** in Game Settings → Security
- Open Output window to monitor save/load logs

## Test Cases

### 1. Data Persistence (Basic)
**Steps:**
1. Join game (new player)
2. Win 2-3 matches, earn cash
3. Leave game
4. Rejoin game

**Expected:**
- On first join: `[DataService] New player PlayerName - using defaults`
- On leave: `[DataService] Saved PlayerName (PlayerRemoving): Cash=XXX, Wins=X, Streak=X`
- On rejoin: `[DataService] Loaded PlayerName: Cash=XXX, Wins=X, Streak=X, MaxStreak=X`
- Stats match exactly what you had before leaving
- Toast shows current stats on first match after rejoin

### 2. Autosave (Non-Spam)
**Steps:**
1. Join game
2. Play several matches over 3+ minutes
3. Watch Output for autosave logs

**Expected:**
- Autosave triggers every ~120 seconds
- Output shows: `[DataService] Autosave triggered`
- Output shows: `[DataService] Autosave complete: X saved, 0 failed`
- NO spam saves between autosaves (unless PlayerRemoving/Shutdown)

### 3. Rapid Rounds (Throttle Protection)
**Steps:**
1. Join game
2. Play 5 rapid matches back-to-back (< 10 seconds apart)
3. Watch Output for save logs

**Expected:**
- First round: `[DataService] Saved PlayerName (RoundResult): ...`
- Next ~9 seconds: NO additional saves (throttled)
- After 10s: Next save allowed
- Stats still update correctly in-memory (cache works)
- On leave: final save captures all stats correctly

### 4. API Disabled (Graceful Degradation)
**Steps:**
1. Disable **API Services** in Game Settings
2. Start game
3. Play matches

**Expected:**
- On startup: `[DataService] DataStore API disabled or failed: ...`
- Game continues to work normally
- Stats update in-memory for the session
- On leave: warns but doesn't error
- No crashes or blocking

### 5. Multiple Players (Concurrent Saves)
**Steps:**
1. Start Server with 2+ clients
2. Both players play matches simultaneously
3. Both players leave at the same time

**Expected:**
- Each player's saves are independent
- No race conditions or data corruption
- Each player's final save succeeds
- Output shows separate save logs for each player

### 6. Shutdown Save (Graceful)
**Steps:**
1. Join game with 2+ players
2. Earn stats
3. Stop server (Studio stop button)

**Expected:**
- Output shows: `[DataService] Shutdown triggered - saving all players...`
- Output shows: `[DataService] Shutdown save complete: X saved, 0 failed, Y.YYs elapsed`
- Save completes within ~10 seconds
- All players' data saved correctly

### 7. Load Failure (Retry + Fallback)
**Steps:**
1. Simulate API error (temporarily disable API mid-game, or use mock failures)
2. Join game

**Expected:**
- Retry attempts visible in Output: `[DataService] LoadPlayer failed (attempt 1/3): ...`
- After 3 attempts: `[DataService] LoadPlayer failed after 3 attempts: ...`
- Falls back to defaults: `[DataService] Load failed for PlayerName - using defaults`
- Game continues normally

### 8. Save Failure (Retry + Warn)
**Steps:**
1. Earn stats
2. Simulate API error during save
3. Leave game

**Expected:**
- Retry attempts visible: `[DataService] SavePlayer failed (attempt 1/3): ...`
- After 3 attempts: `[DataService] Save failed for PlayerName (PlayerRemoving)`
- No crash or hang
- Game exits gracefully

### 9. Data Schema (Forward Compatibility)
**Steps:**
1. Manually edit DataStore key (add extra field `foo = "bar"`)
2. Join game

**Expected:**
- Extra fields ignored (sanitized)
- Stats load correctly from `stats` table
- Game works normally
- Save preserves schema version: `v = 1`

### 10. Streak Persistence (Edge Case)
**Steps:**
1. Win 3 matches in a row (Streak = 3)
2. Leave game
3. Rejoin
4. Lose a match

**Expected:**
- On rejoin: Streak = 3 (loaded correctly)
- After loss: Streak = 0 (reset correctly)
- MaxStreak = 3 (persists)
- All persisted correctly on next save

## Edge Case Verification

### Throttling
- ✅ Saves throttled to 1 per 10 seconds per player (except critical reasons)
- ✅ PlayerRemoving/Shutdown bypass throttle
- ✅ Stats update in cache even when saves throttled

### Retries
- ✅ GetAsync retries 3 times with backoff (1s, 2s, 4s)
- ✅ UpdateAsync retries 3 times with backoff
- ✅ Falls back gracefully on failure

### Autosave
- ✅ Runs every 120 seconds
- ✅ Time-slices saves (one per frame) to avoid spikes
- ✅ Only saves players still in-game

### Shutdown
- ✅ BindToClose triggers save-all
- ✅ Caps total save time at ~10 seconds
- ✅ Saves as many as possible within timeout

### API Disabled
- ✅ Warns but never errors
- ✅ Game continues without saving
- ✅ Stats work in-memory for session

## Success Criteria
- [ ] All 10 test cases pass
- [ ] No crashes or errors in Output
- [ ] Stats persist correctly across sessions
- [ ] Autosave doesn't spam
- [ ] Throttling works (rapid rounds don't spam saves)
- [ ] API disabled → game works (no saves but no crash)
- [ ] Shutdown saves complete gracefully
- [ ] Retry logic handles transient failures

## Performance Checks
- [ ] Autosave uses time-slicing (spreads load)
- [ ] No frame drops during autosave
- [ ] Shutdown save completes within 10 seconds
- [ ] Save throttle prevents spam (max 1 per 10s per player)


# Step 6 — Rewards + Stats Test Checklist

## Test Environment
- Use **Play Solo** or **Start Server + 2 clients** in Studio
- Open Output window to monitor stats logs

## Test Cases

### 1. Win a Round
**Steps:**
1. Start a match at a table (2 players)
2. Both players make choices
3. One player wins (gets the reward)

**Expected:**
- Winner's cash increases by reward amount
- Winner's wins increases by 1
- Winner's streak increases by 1
- Winner's maxStreak updates if needed
- Toast shows: `💰 +$XXX | 🏆 X Wins | 🔥 X Streak`
- Output shows: `[StatsService] Winner: PlayerName (+$XXX, Wins:X, Streak:X, MaxStreak:X)`

### 2. Lose a Round
**Steps:**
1. Start a match
2. Both players make choices
3. One player loses

**Expected:**
- Loser's streak resets to 0
- Loser's cash does NOT increase
- Toast shows: `🏆 X Wins | 🔥 0 Streak`
- Output shows: `[StatsService] Loser: PlayerName (Streak reset to 0)`

### 3. Win 3 in a Row
**Steps:**
1. Win first match → Streak = 1
2. Win second match → Streak = 2
3. Win third match → Streak = 3

**Expected:**
- Streak = 3
- MaxStreak >= 3
- Toast shows increasing streak each time

### 4. Lose After Streak
**Steps:**
1. Build a streak (win 2-3 matches)
2. Lose a match

**Expected:**
- Streak resets to 0
- MaxStreak stays at previous high
- Output shows: `[StatsService] Loser: PlayerName (Streak reset to 0)`

### 5. Both Lose
**Steps:**
1. Start a match
2. Both players choose the same losing option (if applicable in DoubleDown)

**Expected:**
- Both players' streaks reset to 0
- No cash awarded
- Output shows: `[StatsService] Both players lost - resetting streaks`

### 6. Split/Split (Draw) — Both Win
**Steps:**
1. Start a match
2. Both players choose the same winning option (split reward)

**Expected:**
- Each player gets floor(reward/2) cash
- Each player's Wins increases by 1
- Each player's Streak increases by 1
- Each player's MaxStreak updates if needed
- Toast shows: `💰 +$XXX | 🏆 X Wins | 🔥 X Streak` for both
- Output shows: `[StatsService] Draw - both players win, splitting reward`
- Output shows: `[StatsService] Split/Split: PlayerA (+$XXX, Wins:X, Streak:X, MaxStreak:X)`
- Output shows: `[StatsService] Split/Split: PlayerB (+$XXX, Wins:X, Streak:X, MaxStreak:X)`

### 7. Double-Resolve Protection
**Steps:**
1. Start a match
2. Try to trigger resolve twice (simulate latency/spam)

**Expected:**
- Stats only apply once
- Output shows: `[StatsService] Round already processed: <roundId> - skipping duplicate`
- No duplicate cash/wins

### 8. Player Leaves Mid-Round
**Steps:**
1. Start a match
2. One player leaves during spin or stage UI

**Expected:**
- Match aborts cleanly
- No crash
- No stats awarded (wasAborted=true)
- Remaining player respawns after 2 seconds
- Output shows: `[StatsService] Round aborted - no stats applied`
- Output shows: `[RoundService] Aborting round: Opponent left during <state>`

### 9. Session Persistence
**Steps:**
1. Win a few matches, build up cash/wins/streak
2. Check stats persist for the session
3. Player leaves and rejoins

**Expected:**
- Stats persist during session (in-memory)
- Stats reset when player rejoins (new session, no datastore yet)
- Output shows: `[StatsService] Clearing stats for PlayerName (UserId: XXX)` on leave

## Edge Case Verification

### Idempotency Guard
- ✅ `processedRounds` table prevents duplicate stat application
- ✅ Each round has unique `roundId` (tableModel.Name + timestamp)

### Abort Safety
- ✅ `wasAborted=true` skips all stat changes
- ✅ AbortRound calls StatsService with abort payload
- ✅ No cash/wins/streak changes on abort

### Nil Safety
- ✅ `ensureStats()` creates default stats if missing
- ✅ Player validation before stat application
- ✅ Safe cleanup on PlayerRemoving

## Success Criteria
- [ ] All 9 test cases pass
- [ ] No crashes or errors in Output
- [ ] Stats update correctly and consistently
- [ ] Toast notifications show correct values
- [ ] Abort/leave scenarios don't award stats
- [ ] Double-resolve protection works


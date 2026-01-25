# Neutral Round Fix (Both Timeout)

## Changes

### File 1: `src/server/Core/StatsService.lua`

**1. Updated resultPayload contract comment (lines 143-155):**
- Added `isNeutral = boolean? (no-contest; do not change stats)` to the contract.

**2. Added neutral round early return (lines 169-173):**
```lua
-- Neutral: no rewards, no stat changes (both timeout)
if resultPayload.isNeutral then
	print("[StatsService] Neutral round - no stats applied")
	return
end
```
- Placed immediately after idempotency guard and before `wasAborted` check.
- No wins, no streak changes, no cash changes, no max streak changes.
- Still marks round as processed (idempotent).
- Does NOT save players (no changes to save).

### File 2: `src/server/Core/RoundService.lua`

**Added neutral detection (lines 536-539):**
```lua
-- Check for neutral outcome (both timeout)
if data.outcome == "BOTH_TIMEOUT" or data.outcome == "BOTH_TIMEOUT_S2" then
	resultPayload.isNeutral = true
end
```
- Detects both timeout outcomes from DoubleDown plugin.
- Sets `isNeutral = true` in `resultPayload` before calling `StatsService.ApplyRoundResult()`.

## Behavior

### Neutral Round (Both Timeout)
- **Outcome:** `BOTH_TIMEOUT` (Stage 1) or `BOTH_TIMEOUT_S2` (Stage 2)
- **Winners:** Empty array `{}`
- **Reward:** `$0`
- **Stats Changes:** None
  - Cash: unchanged
  - Wins: unchanged
  - Streak: unchanged
  - MaxStreak: unchanged
- **Round Processed:** Yes (idempotent)
- **Save Triggered:** No (nothing changed)

### Comparison with Other No-Contest Outcomes

| Outcome | Wins | Streak | Cash | Save |
|---------|------|--------|------|------|
| **Neutral (Both Timeout)** | No change | No change | No change | No |
| **Aborted (Player Left)** | No change | No change | No change | No |
| **Both Lose (Steal/Steal)** | No change | Reset to 0 | No change | Yes |

## Test Checklist

1. **Force Both Timeout (Stage 1):**
   - Start a match, both players let the timer expire.
   - **Expected Logs:**
     - `[RoundService] Stage1 choices (raw): Player1=TIMEOUT Player2=TIMEOUT`
     - `[DoubleDown] outcome=BOTH_TIMEOUT`
     - `[StatsService] Neutral round - no stats applied`
   - **Expected Behavior:**
     - No stats change for either player.
     - Both players respawn to SpawnLocation.

2. **Force Both Timeout (Stage 2):**
   - Start a match, both pick `DOUBLEDOWN` (Stage 1), then both let Stage 2 timer expire.
   - **Expected Logs:**
     - `[RoundService] Stage2 choices (raw): Player1=TIMEOUT Player2=TIMEOUT`
     - `[DoubleDown] outcome=BOTH_TIMEOUT_S2`
     - `[StatsService] Neutral round - no stats applied`
   - **Expected Behavior:**
     - No stats change for either player.
     - Both players respawn to SpawnLocation.

3. **Single Timeout (Should NOT be Neutral):**
   - Player A picks, Player B times out.
   - **Expected:** Player B's choice is randomized, outcome resolved normally (NOT neutral).
   - **Expected Log:** `[DoubleDown] Player2 timed out -> random choice: ...`
   - **Expected Behavior:** Stats change based on resolved outcome.

4. **Verify Idempotency:**
   - If `StatsService.ApplyRoundResult()` is called twice with the same `roundId` and `isNeutral=true`:
   - **Expected:** Second call logs `Round already processed: ... - skipping duplicate`.


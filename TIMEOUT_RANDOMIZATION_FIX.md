# Timeout Randomization Fix

## Changes
- **File:** `src/server/Plugins/DoubleDown.lua`

### New Behavior
- **Single Timeout:** If exactly one player times out, their choice is randomly selected from the valid options for that stage.
  - Stage 1: `SPLIT`, `STEAL`, `DOUBLEDOWN`
  - Stage 2: `SPLIT`, `STEAL`
- **Both Timeout:** Keeps existing behavior (`BOTH_TIMEOUT` / `BOTH_TIMEOUT_S2`, no winners, $0 reward).

### Implementation Details
1. **Added `pickRandomChoice(player, stage)` helper:**
   - Randomly selects from `STAGE1_OPTIONS` or `STAGE2_OPTIONS`.
   - Logs: `[DoubleDown] PlayerX timed out -> random choice: STEAL (stage 1)`.

2. **Updated Stage 1 resolution:**
   - After `getChoices()`, checks if exactly one player timed out.
   - Replaces `TIMEOUT` with a random choice before outcome computation.
   - Logs final choices: `[DoubleDown] Stage1 final choices: P1=SPLIT P2=STEAL`.

3. **Updated Stage 2 resolution:**
   - Same logic for Stage 2 (Sudden Death).
   - Logs final choices: `[DoubleDown] Stage2 final choices: P1=SPLIT P2=STEAL`.

4. **Preserved `BOTH_TIMEOUT` behavior:**
   - If both players time out, outcome remains `BOTH_TIMEOUT` (Stage 1) or `BOTH_TIMEOUT_S2` (Stage 2).
   - No winners, $0 reward.

### Test Checklist
1. **Single Timeout (Stage 1):**
   - P1 picks `SPLIT`, P2 times out.
   - **Expected:** P2's choice is randomly selected (e.g., `STEAL`), outcome resolved normally (e.g., `STEAL_P2` if random was `STEAL`).
   - **Log:** `[DoubleDown] Player2 timed out -> random choice: STEAL (stage 1)`.

2. **Single Timeout (Stage 2):**
   - Both pick `DOUBLEDOWN` (Stage 1), then P1 picks `SPLIT` (Stage 2), P2 times out.
   - **Expected:** P2's choice is randomly selected (e.g., `STEAL`), outcome resolved normally (e.g., `STEAL_P2`).
   - **Log:** `[DoubleDown] Player2 timed out -> random choice: STEAL (stage 2)`.

3. **Both Timeout (Stage 1):**
   - Both players time out.
   - **Expected:** Outcome `BOTH_TIMEOUT`, no winners, $0 reward.
   - **Log:** `[RoundService] Stage1 choices (raw): Player1=TIMEOUT Player2=TIMEOUT`.

4. **Both Timeout (Stage 2):**
   - Both pick `DOUBLEDOWN` (Stage 1), then both time out (Stage 2).
   - **Expected:** Outcome `BOTH_TIMEOUT_S2`, no winners, $0 reward.

5. **No Timeout:**
   - Both players pick normally.
   - **Expected:** No randomization, outcome resolved as before.


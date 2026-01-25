# SeatUI & Sound Fixes

## Overview
Fixed the SeatUI visibility bug where buttons never appeared because the seated state wasn't propagating. Also extended the spinning sound to loop until the choice card appears.

### 1. SeatUI Visibility Fix
**Problem:** `SeatUI` was never receiving the `seated=true` signal, so it always thought the player was standing.
**Fix:**
- **PromptController:** Added `SeatedChanged` BindableEvent to broadcast seated state changes.
- **UIController:** Wired `PromptController.SeatedChanged` to `SeatUI:SetSeated()`.
- **Result:** When you sit, `SeatUI` now receives the signal and shows the "Invite Friend" / "Leave Seat" buttons (unless in a match).

### 2. Spinning Sound Extension
**Problem:** The spinning sound was too short and stopped before the cinematic ended or the card appeared.
**Fix:**
- **CinematicController:**
  - Set `SpinningSound.Looped = true`.
  - Added `StopSpinSound(reason)` method.
  - `Stop()` calls `StopSpinSound("Stop()")` as a safety fallback.
- **UIController:**
  - In `onPromptChoice` (when the card pops up), explicitly call `CinematicController.StopSpinSound("PromptChoice")`.
- **Result:** The ticking sound now loops continuously during the spin and cuts off *exactly* when the choice UI appears.

## Files Changed
- `game.StarterPlayer.StarterPlayerScripts.Client.UI.PromptController` (+Signal)
- `game.StarterPlayer.StarterPlayerScripts.Client.UI.UIController` (+Wiring)
- `game.StarterPlayer.StarterPlayerScripts.Client.UI.CinematicController` (+Looping/Stop method)

## Verification Checklist
1.  **SeatUI:** Sit at a table (no match). **Verify:** "Invite Friend" / "Leave Seat" buttons appear.
2.  **Spin Sound:** Start a match. **Verify:** Ticking sound loops and stops *only* when the "Double Down" card appears.
3.  **Cleanup:** Finish match. **Verify:** No lingering sounds or UI.


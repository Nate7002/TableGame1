# Reminder Sound & Waiting Text Fix

## Changes
- **File:** `src/client/UI/Components/ChoicePopup.lua`
- **Reminder Sound:**
  - In `_showReminder`, clones `ReplicatedStorage.Assets.FX.ReminderSound`, parents to `SoundService`, plays it, and adds to Debris.
  - Tracks the sound instance in `self._reminderSound`.
  - Stops/destroys existing sound in `_cancelReminder` (called on Hide, Waiting, or new schedule) to prevent stacking.
- **Waiting Text Color:**
  - In `ShowWaitingState`, sets `self._statusLabel.TextColor3 = Color3.new(1, 1, 1)` (White).
  - Ensures "PICK AN OPTION!" remains Red (`Color3.fromRGB(255, 85, 85)`).

## Test Checklist
1. **Start 2-Client Test:**
   - Player A and Player B join a table.
2. **Trigger Reminder:**
   - Player A picks an option immediately.
   - Player B waits.
   - **Expectation:** After 3 seconds, Player B sees "⚡ PICK AN OPTION! ⚡" (Red) and hears `ReminderSound`.
3. **Check Waiting State:**
   - Player B picks an option.
   - **Expectation:** Reminder stops/cleans up. Status text changes to "Waiting on opponent..." and is **WHITE**.
4. **Cleanup:**
   - Round resolves.
   - **Expectation:** UI closes, sound is cleaned up if still playing.


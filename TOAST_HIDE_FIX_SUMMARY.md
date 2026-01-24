# Toast Hide Fix Summary

## Problem
Toast was not properly hiding/easing out when spammed (e.g., countdown 3→2→1). The hide animation would start but never complete, leaving lingering toasts on screen.

## Root Cause
`_cancelTweens()` was cancelling `self._hideTask`, which meant when the delayed hide task fired, it would cancel itself mid-execution, preventing the hide tween from completing and the frame from being destroyed.

## Solution
Split cancellation responsibilities into two separate functions:

### 1. `_cancelTweens()` - Only cancels active tweens
```lua
function Toast:_cancelTweens()
	for _, tween in ipairs(self._activeTweens) do
		if tween then tween:Cancel() end
	end
	self._activeTweens = {}
end
```

### 2. `_cancelHideTask()` - Only cancels scheduled hide task
```lua
function Toast:_cancelHideTask()
	if self._hideTask then
		task.cancel(self._hideTask)
		self._hideTask = nil
	end
end
```

## Changes Made

### A) Animation Functions
- **`_animateShow()`**: Cancels both tweens AND previous hide task (prevents overlap)
- **`_animateHide()`**: Cancels ONLY tweens (does NOT cancel hide task, allowing completion)

### B) Show() Function
- Calls `_cancelHideTask()` before scheduling new hide (prevents multiple hide timers)
- Removed redundant manual frame state reset (handled by initial state)

### C) Initial State
- `_ensureFrame()` now sets all properties to transparent/hidden state on creation
- Ensures first-time show eases in smoothly instead of popping

### D) Memory Leak Prevention
- Changed `frameTween.Completed:Connect(onComplete)` to `:Once(onComplete)`
- Prevents event connection leaks when toasts are recreated

## Result
✅ Toast always eases in (Quad Out, 0.15s)  
✅ Toast always eases out (Quad In, 0.12s)  
✅ Toast fully disappears and destroys after duration  
✅ Countdown spam (3→2→1) works without stuck/overlapping toasts  
✅ No lingering stroke/shadow/background elements  
✅ No memory leaks from event connections  

## Test Scenario
1. Start a match
2. Watch pre-match countdown toast: "Match starting in 3...2...1"
3. Each update should smoothly ease in/out
4. No toasts should remain visible after their duration
5. No visual artifacts (strokes/shadows) should linger

**Expected:** Clean, smooth transitions with no stuck UI elements.


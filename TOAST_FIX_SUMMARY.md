# Toast Animation Fix Summary

## BLUF
**Fixed Toast hide animation** so nothing lingers (text stroke/shadow/background all fade together), made hide faster (0.12s), and added tween cancellation to prevent overlap during countdown updates.

---

## The Problem

### Symptom
- When toast hides, a dark "backing/stroke/shadow" text remains visible longer than main text
- During countdown (3→2→1), multiple toast updates cause ghosting/overlap
- Stroke never fully fades (stays partially visible)

### Root Cause
**Missing TextStrokeTransparency animation:**
```lua
// Old code - line 67, 81
local textTweenIn = TweenService:Create(label, info, { TextTransparency = 0 })
local textTweenOut = TweenService:Create(label, info, { TextTransparency = 1 })
// MISSING: TextStrokeTransparency animation!
```

**Also missing:**
- `labelStroke.Transparency` animation (UIStroke on label)
- Tween cancellation (overlapping animations)
- Fast hide (was 0.5s, needed 0.12s)
- Reusable frame (created new toast every call)

---

## The Solution

### Key Changes

#### 1. **Animate ALL Transparency Properties**
**Before (incomplete):**
- ✅ `frame.BackgroundTransparency`
- ✅ `label.TextTransparency`
- ✅ `uiStroke.Transparency` (frame stroke)
- ❌ `label.TextStrokeTransparency` (MISSING!)
- ❌ `labelStroke.Transparency` (label stroke, MISSING!)

**After (complete):**
```lua
-- Show
local labelTween = TweenService:Create(self._label, showInfo, {
	TextTransparency = 0,
	TextStrokeTransparency = Theme.Stroke.Transparency -- NOW INCLUDED
})

local labelStrokeTween = TweenService:Create(self._labelStroke, showInfo, {
	Transparency = Theme.Stroke.Transparency -- NOW INCLUDED
})

-- Hide
local labelTween = TweenService:Create(self._label, hideInfo, {
	TextTransparency = 1,
	TextStrokeTransparency = 1 -- Fully hide stroke
})

local labelStrokeTween = TweenService:Create(self._labelStroke, hideInfo, {
	Transparency = 1 -- Fully hide label stroke
})
```

#### 2. **Faster Hide Animation**
**Before:** 0.5s (Quad/Out)  
**After:** 0.12s (Quad/In)

```lua
local SHOW_DURATION = 0.15
local HIDE_DURATION = 0.12
```

#### 3. **Tween Cancellation (No Overlap)**
**Added:**
```lua
function Toast:_cancelTweens()
	for _, tween in ipairs(self._activeTweens) do
		if tween then
			tween:Cancel()
		end
	end
	self._activeTweens = {}
	
	-- Cancel hide task
	if self._hideTask then
		task.cancel(self._hideTask)
		self._hideTask = nil
	end
end
```

**Called at start of:**
- `_animateShow()` — prevents overlap when updating
- `_animateHide()` — prevents multiple hide tweens

#### 4. **Reusable Frame**
**Before:** Created new frame every `Show()` call (wasteful, caused overlap)  
**After:** Reuses `self._frame` (updates text only)

```lua
function Toast:_ensureFrame()
	if self._frame and self._frame.Parent then
		return -- Already exists
	end
	-- Create only if needed
end

function Toast:Show(text, duration)
	self:_ensureFrame()
	self._label.Text = text -- Update existing label
	self:_animateShow()
end
```

---

## Implementation Details

### New Properties
```lua
function Toast.new(parentGui)
	local self = setmetatable({}, Toast)
	self._parent = parentGui
	self._frame = nil -- Reusable frame
	self._label = nil
	self._uiStroke = nil -- Frame stroke
	self._labelStroke = nil -- Label stroke
	self._activeTweens = {} -- Track tweens for cancellation
	self._hideTask = nil -- Track hide delay task
	return self
end
```

### New Methods

#### `Toast:_cancelTweens()`
- Cancels all active tweens
- Cancels hide delay task
- Prevents overlap/ghosting

#### `Toast:_ensureFrame()`
- Creates frame if it doesn't exist
- Reuses existing frame if valid
- Stores references to all UI elements

#### `Toast:_animateShow()`
- Cancels existing tweens first
- Animates ALL properties to visible state:
  - Frame: Position + BackgroundTransparency
  - Label: TextTransparency + TextStrokeTransparency
  - Frame stroke: Transparency
  - Label stroke: Transparency
- Duration: 0.15s, Quad/Out

#### `Toast:_animateHide(onComplete)`
- Cancels existing tweens first
- Animates ALL properties to hidden state (all → 1)
- Duration: 0.12s, Quad/In (faster!)
- Calls `onComplete` callback when done

### Updated `Show()` Method
```lua
function Toast:Show(text, duration)
	-- 1. Ensure frame exists (or reuse)
	self:_ensureFrame()
	
	-- 2. Update text
	self._label.Text = text
	
	-- 3. Reset to start position if hidden
	if self._frame.BackgroundTransparency >= 0.9 then
		-- Snap to hidden state
	end
	
	-- 4. Animate to visible (cancels existing tweens)
	self:_animateShow()
	
	-- 5. Schedule hide (cancels previous hide task)
	self._hideTask = task.delay(duration, function()
		self:_animateHide(function()
			-- Destroy frame after hide completes
		end)
	end)
end
```

---

## Files Changed

### `src/client/UI/Components/Toast.lua` (Complete Rewrite)
**Lines:** ~200 lines (was ~99 lines)

**Added:**
- Constants: `SHOW_DURATION`, `HIDE_DURATION`
- Properties: `_frame`, `_label`, `_uiStroke`, `_labelStroke`, `_activeTweens`, `_hideTask`
- Methods: `_cancelTweens()`, `_ensureFrame()`, `_animateShow()`, `_animateHide()`

**Fixed:**
- TextStrokeTransparency now animates (was missing)
- labelStroke.Transparency now animates (was missing)
- Tweens cancel before new animations (no overlap)
- Hide is faster (0.12s vs 0.5s)
- Frame is reused (not recreated every call)

---

## Testing

### Test 1: Countdown (3→2→1)
**Before:**
- Ghost text lingered between updates
- Stroke remained visible after text faded
- Multiple overlapping toasts

**After:**
- Clean updates every second
- No lingering stroke
- Single toast updates smoothly

### Test 2: Rapid Show/Hide
**Before:**
- Half-faded states
- Overlap/ghosting
- Stroke artifacts

**After:**
- Clean transitions
- No artifacts
- Immediate cancellation

### Test 3: Hide Completeness
**Before:**
- Stroke visible after hide (BackgroundTransparency=1, TextTransparency=1, but TextStrokeTransparency undefined)
- Label stroke never animated

**After:**
- ALL properties → 1 (fully hidden)
- Clean disappearance

---

## Benefits

✅ **No Lingering Artifacts:** All transparency properties animate together  
✅ **Faster Hide:** 0.12s vs 0.5s (less overlap)  
✅ **No Overlap:** Tween cancellation prevents ghosting  
✅ **Reusable:** Frame updates instead of recreating  
✅ **Countdown-Friendly:** Updates every second without artifacts  
✅ **Clean Code:** Modular helpers (`_animateShow`, `_animateHide`)  

---

## Technical Comparison

### Before
| Property | Show | Hide | Issue |
|----------|------|------|-------|
| `frame.BackgroundTransparency` | 1→0.1 | 0.1→1 | ✅ OK |
| `label.TextTransparency` | 1→0 | 0→1 | ✅ OK |
| `label.TextStrokeTransparency` | ❌ Not animated | ❌ Not animated | ❌ **LINGERED** |
| `uiStroke.Transparency` | 1→0.8 | 0.8→1 | ✅ OK |
| `labelStroke.Transparency` | ❌ Not animated | ❌ Not animated | ❌ **LINGERED** |
| **Duration** | 0.5s | 0.5s | ⚠️ Too slow |
| **Easing** | Quad/Out | Quad/Out | ⚠️ Same for both |
| **Tween Cancel** | ❌ No | ❌ No | ❌ **OVERLAP** |

### After
| Property | Show | Hide | Issue |
|----------|------|------|-------|
| `frame.BackgroundTransparency` | 1→0.1 | 0.1→1 | ✅ OK |
| `label.TextTransparency` | 1→0 | 0→1 | ✅ OK |
| `label.TextStrokeTransparency` | 1→Theme.Stroke.Transparency | Theme.Stroke.Transparency→1 | ✅ **FIXED** |
| `uiStroke.Transparency` | 1→0.8 | 0.8→1 | ✅ OK |
| `labelStroke.Transparency` | 1→Theme.Stroke.Transparency | Theme.Stroke.Transparency→1 | ✅ **FIXED** |
| **Duration** | 0.15s | 0.12s | ✅ Faster hide |
| **Easing** | Quad/Out | Quad/In | ✅ Different |
| **Tween Cancel** | ✅ Yes | ✅ Yes | ✅ **NO OVERLAP** |

---

## No Gameplay Changes

- ✅ Toast behavior unchanged (show/hide/duration)
- ✅ Only animation quality improved
- ✅ Zero impact on rewards/stats/datastore
- ✅ Works with existing Toast.new() calls
- ✅ Backward compatible API


# Universal UI Operating Standard

**Status:** Living document  
**Audience:** Humans first  
**Scope:** All current and future projects

This document defines **how UI is built**, not **what UI exists**.

You should be able to:

- Read this months later and remember how to build UI
- Hand this to someone new and they understand what to do
- Build UI without re‑deciding fundamentals every time

If something is unclear here, the document—not you—is wrong.

---

## 0. Core Mental Model (Read This First)

UI is **presentation**, not logic.

UI exists to:

- Show state
- Forward player intent
- Animate feedback

UI does **not** exist to:

- Decide outcomes
- Own game rules
- Mutate authoritative state

A useful test:

> If all UI disappeared, could the game still run?

If the answer is no, UI is doing too much.

---

## Engine Setup (Studio Bootstrap — Do This First)

Before building or importing any UI, the engine shell must exist.

Open Studio.
Open the **Command Bar**.
Paste this exactly once:

```lua
local starterGui = game:GetService("StarterGui")

-- Create ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "UI_ENGINE"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.Parent = starterGui

-- MenuRoot
local menuRoot = Instance.new("Frame")
menuRoot.Name = "MenuRoot"
menuRoot.Size = UDim2.fromScale(1, 1)
menuRoot.Position = UDim2.fromScale(0, 0)
menuRoot.BackgroundTransparency = 1
menuRoot.ZIndex = 0
menuRoot.Parent = screenGui

-- Dimmer
local dimmer = Instance.new("Frame")
dimmer.Name = "Dimmer"
dimmer.AnchorPoint = Vector2.new(0, 0)
dimmer.Position = UDim2.fromScale(0, 0)
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
dimmer.BackgroundTransparency = 0.4
dimmer.ZIndex = 1
dimmer.Parent = menuRoot

-- Container
local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.Position = UDim2.fromScale(0.5, 0.5)
container.Size = UDim2.fromScale(0.6, 0.6)
container.BackgroundTransparency = 1
container.ZIndex = 2
container.Parent = menuRoot

-- Aspect Ratio Constraint
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 1004 / 744
aspect.Parent = container

-- Content
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.fromScale(1, 1)
content.BackgroundTransparency = 1
content.ClipsDescendants = true
content.ZIndex = 2
content.Parent = container
```

This creates the **UI engine shell**.

Important:

- This shell is infrastructure.
- It is NOT exported from Figma.
- All menu visuals are inserted inside **Content** only.
- You do not recreate this per menu.

---



## 1. UI Taxonomy (Locked)

Every piece of UI must fit into **exactly one** category. These categories are not stylistic—they determine **how the UI behaves and how it is built**.
---

## TYPE 0 — HUD UI (Passive, Persistent)

### Mental Model

HUD UI is a **dashboard**. It reflects the game but does not interrupt it.
### Examples

- Currency counters
- Speed / jump indicators
- Timers
- Buff durations

### What HUD UI Owns

- Visual representation of state

### What HUD UI Never Owns

- Input focus
- Navigation
- Scrolling
- Gameplay logic

### Locked Rules

- Always visible (or predictably visible)
- No open/close lifecycle
- Never blocks gameplay
- Reads state only

---

## TYPE 1 — Button UI (Atomic)

### Mental Model

A button is a **port**. It forwards intent and nothing else.

If a button starts to feel "smart," something is wrong.

### Examples

- Shop button
- VIP button
- Confirm / Cancel
- Buy buttons

### What a Button Owns

- Hitbox
- Visual feedback (hover, press)

### What a Button Never Owns

- Game logic
- State transitions
- Decision making

### Locked Rules

- `ImageButton` = hitbox only
- Visuals are child `ImageLabel`s
- Tight hitbox, no overlap
- Animations are cosmetic
- Buttons never own logic

---

## TYPE 2 — Menu UI (Stateful Containers)

### Mental Model

A menu is a **shell**. It organizes UI and manages visibility.

It does not decide gameplay.

---
### Examples

- Shop
- Inventory / chair shop
- Index
- Rebirth
- Exit confirmation

Menus exist to **organize UI**, not to run the game.

---

### What a Menu Owns

- Open / close lifecycle
- Layout and structure
- Input forwarding

### What a Menu Never Owns

- Game rules
- Outcomes
- Persistence

---

### Required Structure (Locked)

Every menu **must** follow this hierarchy:

### Required Hierarchy (Inside UI_ENGINE)

```
UI_ENGINE (ScreenGui)
└─ MenuRoot
   ├─ Dimmer
   └─ Container
      └─ Content
```

This structure is universal and non‑negotiable.

All imported or designed menu visuals must live inside:

```
Container
└─ Content
   └─ (Your Menu UI Here)
```

Rules:

- Only **Content** may scroll.
- AspectRatioConstraint belongs only on **Container**.
- The engine shell is never exported from design tools.
- You only design what goes inside Content.

---

## TYPE 3 — Interactive UI (State Machines)

### Mental Model

Interactive UI is a **visual machine**.

It reacts to data over time.

It is not a collection of buttons. It is not rebuilt per use.

### Examples

- Spin wheels
- Reward reveals
- Countdown bars
- Animated multipliers

---

### Core Rule (Locked)

Interactive UI is **one object**:

- One root
- One lifecycle
- One controller

It is reused, not recreated.

---

### Ownership Rules

Interactive UI **never owns**:

- ScreenGui
- MenuRoot
- Dimmer
- Container

It is mounted inside:

```
Container
└─ Content
   └─ InteractiveUIRoot
```

---

### Lifecycle (Locked)

All Interactive UI follows this state flow:

```
Idle → Armed → Active → Resolving → Cooldown → Idle
```

**State meanings**

- **Idle:** Dormant, waiting
- **Armed:** Input accepted, anticipation
- **Active:** Main animation running
- **Resolving:** Outcome revealed
- **Cooldown:** Settle before reset

States are never skipped.

---

### Data Contract

Interactive UI:

- Does not roll RNG
- Does not decide outcomes
- Does not modify game state

It receives:

- Input intent
- Outcome data

It outputs:

- Visual feedback only

---

### Animation Rules (Locked)

- Animations are state‑bound
- Start on state entry
- Stop on state exit
- Never run freely

---

# 3. Import & Construction Pipeline

UI is built in layers.

---

## Phase A — Design

Design tools are for layout only.

- No logic
- No dynamic behavior
- One screen at a time
- Design only what belongs inside **Content**

Never design the engine shell.

---

## Phase B — Import

Recreate hierarchy inside:

```
UI_ENGINE → MenuRoot → Container → Content
```

Imports must not:

- Create new ScreenGuis
- Recreate Dimmer
- Recreate Container

---

## Phase C — Studio Hardening

Verify:

1. Correct hierarchy
2. Correct scaling
3. Correct clipping
4. No accidental shell duplication

---

## Phase D — Behavior Attachment

Only after visuals are stable:

- Bind button intent
- Attach state readers
- Attach animations

Never attach gameplay logic inside UI.

---

# 4. Asset Strategy

Assets should be neutral and reusable.



### Grayscale Rule

Base panels and surfaces should remain neutral.

Color is applied in-engine.

This allows:

- Recoloring
- Theming
- Reuse across systems

---

### Text Handling

- Text is created in-engine
- Text is not baked into images
- Decorative text is the only exception

---

# 5. Naming Conventions

Consistency enables clarity.

Names should:

- Describe purpose
- Avoid randomness
- Avoid visual-only descriptions

Bad:

- Frame1
- Rectangle 23
- Diamond

Good:

- ShopMenu_Tab_Defenses_Frame
- Header_CloseButton
- RewardCard_Buy_Button

---

# 6. What UI Must Never Do

UI must never:

- Own gameplay rules
- Own persistence
- Decide outcomes
- Communicate directly with datastores
- Rebuild itself per state

UI serves the engine.

---

# 7. Relationship to Project Docs

This document defines **how UI is built**.

Project documents define:

- What UI exists
- When UI appears
- What data is shown

Do not redefine UI structure per project.

---

# 8. Document Status

This is a living doctrine.

Changes should be:

- Minimal
- Intentional
- Backwards-compatible

UI consistency is a feature.

---

**End of Universal UI Operating Standard**


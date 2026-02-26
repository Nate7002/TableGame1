---
description: Controls how UI is implemented in Roblox Studio.
alwaysApply: false
---

# UI Implementation Enforcement Rule

This rule enforces compliance with:

universal_ui_operating_standard.md

## Shell Ownership

Menus must live inside the canonical UI_ENGINE shell structure.

The shell must never be recreated via JSON import.

## Property Discipline

Enforce:

- Deterministic scaling
- AnchorPoint correctness
- AspectRatioConstraint placement rules
- ClipsDescendants on Content

Reject:

- Arbitrary constraint stacking
- Casual AnchorPoint modification
- Random ZIndex changes
- Structural shell mutations

## Logic Separation

UI must:

- Emit intent
- Animate feedback
- Display state

UI must not:

- Modify authoritative state
- Resolve gameplay
- Access persistence


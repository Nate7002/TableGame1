---
description: Governs Figma JSON import and PNG upload workflow.
alwaysApply: false
---

# UI Import Enforcement Rule

This rule enforces compliance with:

universal_ui_operating_standard.md

## Standard Pipeline Enforcement

Ensure Figma → JSON → ZIP → upload.js → rbxassetid workflow matches the canonical UI Operating Standard.

Shell structure must never be generated from Figma.

## Tag Validation

Enforce:

- Uppercase tag usage
- Correct stacking
- Single TYPE tag per node
- @GRAY used only for recolorable surfaces

Reject:

- Duplicate grayscale PNG layers
- Re-exported recreatable shapes
- Structural shell imports


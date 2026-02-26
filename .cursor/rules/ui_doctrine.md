---
description: Enforces deterministic UI structure and tagging before export.
alwaysApply: false
---

# UI Doctrine Enforcement Rule

This rule enforces compliance with:

universal_ui_operating_standard.md

When working on UI:

1. Enforce UI_ENGINE shell hierarchy as defined in the UI Operating Standard.
2. Enforce deterministic naming conventions.
3. Enforce tag correctness and uppercase usage.
4. Enforce PNG minimization discipline.
5. Enforce Skin@GROUP structural grouping.
6. Enforce correct @GRAY usage for recolorable surfaces.

Reject changes that:

- Introduce ambiguous naming
- Bypass Content container
- Add gameplay logic into UI
- Add unnecessary PNGs
- Use multiple TYPE tags on one node
- Attempt to export shell structure from Figma

This rule enforces — it does not redefine — the UI Operating Standard.


---
description: Prevents architectural drift across systems.
alwaysApply: false
---

# Architecture Rule

UI must comply with universal_ui_operating_standard.md.

UI is a client-side presentation layer.

UI must never:

- Own business logic
- Modify authoritative state
- Access DataStore
- Resolve outcomes

Intent must route to controller modules.

Systems must remain:

- Modular
- Composable
- Portable

Reject designs introducing hidden coupling.


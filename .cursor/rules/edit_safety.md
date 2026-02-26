---
description: Prevents unsafe edits and structural hallucination.
alwaysApply: true
---

# Edit Safety Rule

Before generating any Cursor prompt:

1. Use MCP to inspect structure.
2. Confirm affected files.
3. Request file contents if required.
4. Confirm scope.
5. Generate minimal deterministic prompt.

Never:

- Invent file paths
- Rewrite unrelated files
- Perform broad refactors without approval
- Modify shell without explicit instruction

All edits must be:

- Minimal
- Additive
- Reversible
- Deterministic


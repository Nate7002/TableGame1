# Table PvP Game — Roadmap (Anti-Drown)

## Golden Rule
**Only build the next step after the current step works.**
After each step: **Test → Commit → Push.**

---

# ✅ MVP PHASE 1 — Get Playable (Ship the loop)
Goal: A working game loop with one minigame and saved progression.

### ✅ STEP 0 — Setup
- [ ] Rojo sync working
- [ ] Repo structure clean
- [ ] `.cursorrules` in place
- [ ] Lobby exists with table models (can be rough)

### ✅ STEP 1 — Table Join + Force Sit (2 seats)
- [ ] Each table has SeatA / SeatB
- [ ] Each seat has ProximityPrompt (JoinPromptA/B)
- [ ] Press prompt → force sit player
- [ ] Touching seat does NOT auto-sit
- [ ] Track table state: Empty / Waiting / Full

### ✅ STEP 2 — Match Start + Round Session Skeleton
- [ ] When both seats filled → create RoundSession
- [ ] Freeze players (optional)
- [ ] Handle leaving/disconnect cleanly

### ✅ STEP 3 — Basic UI Plumbing
- [ ] Popup UI framework
- [ ] RemoteEvents wired
- [ ] Notifications/toasts system

### ✅ STEP 4 — Plugin System (Generic)
- [ ] Plugin runner calls any plugin via `Run(context) -> result`
- [ ] Plugin registry / loading system

### ✅ STEP 5 — Implement 1 Minigame (DoubleDown)
- [ ] Loot spin → rarity/value
- [ ] Split/Steal/DoubleDown choices
- [ ] Resolve outcome
- [ ] Results UI

### ✅ STEP 6 — Rewards + Stats
- [ ] Cash
- [ ] Wins
- [ ] Streak
- [ ] MaxStreak
- [ ] Update after every round

### ✅ STEP 7 — Data Saving / Loading
- [ ] DataStore save/load
- [ ] Session safety / retry
- [ ] Auto-save interval

### ✅ STEP 8 — Simple Leaderboards
- [ ] OrderedDataStore: Top Cash
- [ ] OrderedDataStore: Top MaxStreak
- [ ] Display in lobby

### ✅ STEP 9 — Chair Shop (Basic)
- [ ] Buy chair
- [ ] Equip chair
- [ ] Chair bonus placeholder logic

### ✅ STEP 10 — Monetization (Basic)
- [ ] VIP tag + 2x wins
- [ ] 2x cash
- [ ] 2x wins
- [ ] 2x streak gain
- [ ] Central multiplier logic

✅ **PHASE 1 DONE = playable game you can ship.**

---

# ✅ PHASE 2 — Retention (Daily return loops)
Goal: Players come back daily and invite friends.

- [ ] Daily rewards
- [ ] Daily quests (play 5 rounds, win 3, duel friend)
- [ ] Invite friends while waiting at table
- [ ] Group join rewards
- [ ] Occasional purchase prompts (rate-limited)

---

# ✅ PHASE 3 — Scale + Monetize (Long-term grind)
Goal: Increase conversion + progression depth.

- [ ] Rare tables (higher rewards + stat requirements)
- [ ] VC-only servers (portal prompt)
- [ ] Better chair stats (multipliers + streak protection)
- [ ] Win store + cash store

---

# Notes
- Keep systems modular (“puzzle pieces”) so they can be reused in future games.
- Avoid adding Phase 2/3 features before Phase 1 loop is solid.

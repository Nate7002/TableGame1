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

### ✅ STEP 9 — Economy Foundation (Dual Currency + Inventory)
- [ ] Add Gems to player profile (persistent)
- [ ] Add Shields to player profile (persistent)
- [ ] Extend DataService schema safely (Gems + Shields)
- [ ] Expand StatsChanged pipeline to include Gems + Shields
- [ ] Add save-status signal (server → UI ready hook)

### ✅ STEP 10 — Monetization Engine (Core)
- [ ] Create MonetizationConfig (all IDs centralized)
- [ ] Create MonetizationService (Marketplace authority)
- [ ] VIP detection + caching
- [ ] Central reward multiplier logic (VIP 2x cash)
- [ ] Implement Shield inventory logic (stackable + configurable max)
- [ ] Implement Shield activation system (pre-match only)
- [ ] Implement Restore offer system (post-loss, 5.9s server-validated)
- [ ] Implement Gem purchase dev products
- [ ] Implement Shield purchase dev product
- [ ] Implement Restore tiered dev products
- [ ] Centralized receipt routing

### ✅ STEP 11 — Protection Surface (Minimal UI)
- [ ] Lower-right Shield counter (X / MaxShields)
- [ ] “Use Shield” button (visible only while waiting)
- [ ] Restore popup with countdown (5.9s urgency)
- [ ] Server expiration validation for restore
- [ ] Restore rate limiting safeguards

### ✅ STEP 12 — Economy HUD Surface
- [ ] Top-left Cash display
- [ ] Top-left Gems display
- [ ] Save indicator UI
- [ ] Expand StatsUpdate remote to support Gems + Shields

### ✅ STEP 13 — Shop (Lean Version)
- [ ] Shop UI shell (TYPE 2 compliant)
- [ ] Gems purchase tab
- [ ] Shield purchase tab (direct Robux)
- [ ] Cosmetics tab (Cash + Gems ready)
- [ ] Currency refresh bindings

### ✅ STEP 14 — Idle System (Cosmetic Status Layer)
- [ ] IdleConfig
- [ ] IdleService
- [ ] Idle unlock dev products
- [ ] Idle equip system
- [ ] Idle menu UI
- [ ] VIP exclusive idle

### ✅ STEP 15 — Emote System (Personality Layer)
- [ ] Emote config
- [ ] Emote unlock logic
- [ ] Emote menu UI
- [ ] AURA premium emote labeling

✅ **PHASE 1 DONE = Playable, Monetizable, Ship-Ready Core**

---

# ✅ PHASE 2 — Retention (Daily Return Loops)
Goal: Increase return rate and session consistency.

- [ ] Daily rewards
- [ ] Daily quests (play X rounds, win X, duel friend)
- [ ] Group join rewards
- [ ] Limited-time discounts (Saturday protection discount)
- [ ] Rate-limited restore prompts
- [ ] Live update log surface

---

# ✅ PHASE 3 — Expansion + Scale (Post-Release Growth)
Goal: Increase ARPU, progression depth, and long-term engagement.

- [ ] AFK Chamber / AFK World (cash drip, capped)
- [ ] Rare tables (reward multipliers + stat requirements)
- [ ] High-streak-only lobbies
- [ ] VC-only servers
- [ ] Table skins / visual upgrades
- [ ] Seasonal cosmetic drops
- [ ] Win store + cash store
- [ ] Event-based gem rewards (optional later)

---

# Notes
- Keep systems modular (“puzzle pieces”) so they can be reused in future games.
- Avoid adding Phase 2/3 features before Phase 1 loop is solid.

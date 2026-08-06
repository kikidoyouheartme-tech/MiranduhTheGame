# GAME_SPEC.md

## 1. Game Overview & Core Loop

- **Title (working):** MiranduhTheGame
- **Genre:** 2D side-scrolling beat-em-up / brawler
- **Perspective:** 2D, horizontal side-view, no camera scrolling currently implemented (static viewport, world position maps directly to screen position)
- **Engine:** Godot 4.x (GDScript)
- **Core Loop:** Player traverses a side-scrolling level, encounters enemies, engages in melee combat (walk up, punch combos, block incoming attacks), defeats enemies for progression, manages health and stamina resources during encounters.
- **Tone/Style:** Pixel art, character-based sprites (player and enemies modeled as stylized personas), casual/comedic visual style layered on core brawler mechanics.

---

## 2. Player Character Specs

### Node Structure (`scenes/Player.tscn`)
- `Player` (`CharacterBody2D`, script: `player.gd`)
  - `AnimatedSprite2D` — animations: `idle`, `walk`, `jump`, `attack1`, `attack2`, `attack3`, `block`, `hurt`, `death_knockback`, `death_ground`
  - `AttackHitbox` (`Area2D`, script: `attack_hitbox.gd`)
    - `CollisionShape2D`
  - Collision Layer: `2` (characters), Collision Mask: `1` (floor only — does not physically collide with enemies)

### Movement
- Horizontal movement via `ui_left`/`ui_right` input, constant `SPEED = 150.0`
- Jump via `ui_up` when `is_on_floor()`, `JUMP_VELOCITY = -350.0`, `GRAVITY = 900.0`
- Facing direction (`facing`) flips sprite (`flip_h`) based on input direction
- Scale system: `PLAYER_SCALE = 0.7` base, `JUMP_SCALE = 1.3` multiplier while airborne, `DEATH_SCALE = 1.3` multiplier during death sequence

### Combat — Attacks
- Attack input handled via `_unhandled_input()` (event-based, not polled) to avoid double-registering a single press across physics substeps
- 3-hit combo system: `attack1` → `attack2` → `attack3`, chained via `combo_buffered` flag if attack is pressed again within `COMBO_WINDOW = 0.5s` during the current swing's animation
- `AttackHitbox` position mirrors based on `facing` (`abs(position.x) * facing`)
- `attack_hitbox.gd` exposes `@export var damage: int = 15` — the source of truth for damage dealt per swing
- Damage application: **enemy-side** `HurtBox.area_entered` reads `damage` directly off the incoming `AttackHitbox` and calls `take_hit()` on itself (single authoritative path — do NOT also wire a duplicate call from the player's side, as this causes double-damage)

### Combat — Block & Stamina
- Hold `block` action while grounded and `GameManager.block_stamina > 0` to enter `BLOCK` state (immobile, plays `block` animation)
- `BLOCK_DRAIN_PER_SEC = 25.0` — stamina drains while holding block
- `BLOCK_HIT_COST = 20.0` — additional stamina cost per blocked hit landed
- `BLOCK_REGEN_PER_SEC = 15.0`, `BLOCK_REGEN_DELAY = 0.6s` after releasing block before regen starts
- `CHIP_DAMAGE_PERCENT = 0.2` — 20% of incoming damage still applies as "chip damage" even while successfully blocking
- **Guard Break:** if stamina hits 0 while blocking, triggers `_guard_break()` → `GUARD_BREAK_STUN = 0.8s` stunned state, plays `"idle"` (NOT `"hurt"` — guard break is a distinct event from being hit, must not reuse the hit-reaction animation)

### Health & Death
- Health managed externally via `GameManager` autoload (`GameManager.take_damage()`, `GameManager.died` signal)
- `take_hit(amount)`: if blocking, apply chip damage; otherwise apply full damage, set `HURT` state, play `"hurt"` animation (only on genuine unblocked hits — not on stamina depletion)
- On death (`GameManager.died` signal): `_die()` sets `is_dead = true`, applies knockback (`KNOCKBACK_FORCE = 250.0`), plays `death_knockback` → `death_ground` animation sequence, scales up via `DEATH_SCALE`

### Rendering
- `Z Index = 1` on Player root (Enemy stays at `0`) — ensures player always renders above enemies regardless of scene tree order or position

---

## 3. Enemy AI & Combat

### Node Structure (`scenes/Enemy.tscn`)
- `Enemy` (`CharacterBody2D`, script: `enemy.gd`)
  - `AnimatedSprite2D` — animations: `idle`, `walk`, `punch`, `dead` (native art orientation faces **right**; `flip_h` used to face left)
  - `AttackHitbox` (`Area2D`) — with `@export var damage` if extended per-enemy-type tuning is desired
    - `CollisionShape2D`
  - `HurtBox` (`Area2D`, group: `enemy_hurtbox`) — direct child of `Enemy` root (required, since damage calls use `area.get_parent().take_hit()`)
    - `CollisionShape2D`
  - Collision Layer: `2` (characters, shared with player), Collision Mask: `1` (floor only — does not physically collide with the player)

### Exported Stats (tunable per-instance in Inspector, enables scene duplication for new enemy types without code changes)
- `speed: float = 80.0`
- `attack_range: float = 350.0` *(tune per level's coordinate scale — use live debug distance readings to calibrate, not visual guessing)*
- `attack_cooldown: float = 1.2`
- `attack_damage: int = 10`
- `enemy_scale: float = 0.7` — applied to the **root node's `scale`**, not just the sprite, so it automatically resizes the body collision, `AttackHitbox`, and `HurtBox` together
- `max_health: int = 30`
- `knockback_force: float = 120.0`

### AI Behavior Logic
- `_find_player()`: locates player via `get_tree().get_nodes_in_group("player")`; retries every frame if not yet found (resilient to load-order timing)
- Facing/flip recalculated **every physics frame unconditionally** (before any state branching) — critical fix, since gating this inside specific state branches caused stale facing during attack/cooldown states
- **Distance check uses horizontal (X-axis) distance only** (`abs(player.global_position.x - global_position.x)`), NOT full 2D `distance_to()` — the two characters can sit at different Y anchor points due to sprite pivot differences, and full 2D distance made the attack range mathematically unreachable
- Simplified two-state range logic (no separate "chase range" — removed as an unnecessary/confusing tuning axis):
  - If `x_distance <= attack_range`: hold position; attack if cooldown ready, otherwise idle-hold during cooldown
  - Else: always walk toward the player, regardless of how far away (no "give up" distance)
- On death: `is_dead = true`, disables hurtbox/attack hitbox, applies knockback away from the killing blow's direction, plays `dead` animation, waits `FADE_OUT_DELAY = 0.4s`, then tweens sprite alpha to 0 over `FADE_OUT_DURATION = 0.6s` before `queue_free()`

### Combat & Damage
- `take_hit(amount, source)`: reduces `current_health`, applies directional knockback based on attacker's position, triggers `hurt` animation + `HURT_FLINCH_TIME = 0.2s` flinch, or `_die()` if health reaches 0
- **Single source of truth for incoming damage:** only `HurtBox.area_entered` → `_on_hurt_box_area_entered()` → `take_hit()`. Do not also wire a duplicate `take_hit()` call from the player's `AttackHitbox.area_entered` — Godot fires `area_entered` independently on both overlapping `Area2D`s, so dual-wiring causes every hit to register twice

---

## 4. UI & HUD System

### Required Nodes (`hud.tscn`)
- Player portrait icon (circular framed avatar)
- **HealthBar** (`TextureProgressBar`) — red, linked to `GameManager` health value/signal
- **StaminaBar** (`TextureProgressBar`) — blue, linked to `GameManager.block_stamina` value

### Signal/Data Flow
- `GameManager` (autoload) exposes:
  - Player health state + `died` signal (emitted at 0 HP, connected to `Player._die()`)
  - `block_stamina` / `block_stamina_max` (floats, drained/regenerated by `player.gd`'s block logic each frame)
- HUD script (`hud.gd`) should connect to `GameManager` signals/values to update bar fill percentages in real time — avoid polling where possible in favor of signal-driven updates
- Health bar and stamina bar assets are pre-styled texture progress bars (custom pixel-art frame graphics), not default Godot theme bars

---

## 5. Level Design & Environment

### Ground/Floor
- Static collision body (`StaticBody2D` or `TileMap`) on **Collision Layer `1`** exclusively — reserved purely for environment geometry, separate from the character layer (`2`) to allow characters to pass through each other while still respecting floor collision independently

### Level Scene Structure
- `scenes/levels/Level1.tscn` — root level scene instancing `Player.tscn` and one or more `Enemy.tscn` instances as children
- No `Camera2D` currently implemented — viewport is static, world coordinates map 1:1 to screen coordinates (relevant for any future distance/positioning debugging — rules out camera zoom/pan as a variable)
- World coordinate scale is notably larger than intuitive "pixel-close" expectations — always verify tuning values (ranges, speeds) using live debug print output of actual `global_position`/distance values rather than assuming round numbers will "feel right"

### Groups (Project-Wide)
- `player` — assigned to `Player.tscn` root node (required for enemy AI to locate the player via `get_tree().get_nodes_in_group()`)
- `player_attack` — assigned to `Player.tscn`'s `AttackHitbox` node
- `enemy_hurtbox` — assigned to `Enemy.tscn`'s `HurtBox` node

---

## 6. Action Plan / Task List

- [ ] Verify/finalize `attack_range` tuning using live in-game distance debug prints (current default `350.0`, must match actual visual melee reach for this level's coordinate scale)
- [ ] Confirm enemy `speed` is competitive with player `SPEED` (150.0) so enemies can realistically close distance and land hits rather than perpetually trailing
- [ ] Extend `enemy.gd`/`Enemy.tscn` into distinct enemy-type scenes via duplication (different sprites + tuned exported stats), reusing the single shared script for maintainability
- [ ] Wire enemy's own `AttackHitbox` to actually damage the player (currently only the enemy's incoming-damage path via `HurtBox` is confirmed; player-side damage-taking from enemy punches needs an equivalent single-source-of-truth wiring, mirroring the enemy's `HurtBox` pattern — avoid dual-wiring both sides)
- [ ] Implement/verify HUD signal connections for both `HealthBar` and `StaminaBar` reacting live to `GameManager` state changes
- [ ] Add remaining combo balance pass (per-hit damage values across `attack1`/`attack2`/`attack3`, decide whether combo chains should deal escalating or flat damage)
- [ ] Build out additional levels under `scenes/levels/` following `Level1.tscn`'s structure (floor on layer `1`, characters on layer `2`)
- [ ] Add camera system (`Camera2D`) if scrolling levels are planned — currently absent, meaning all listed distance/positioning math assumes a static viewport
- [ ] Clean up any remaining temporary debug `print()` statements in `enemy.gd`/`player.gd` once final tuning is confirmed
- [ ] Playtest full combat loop end-to-end: approach → combo attack → block/guard-break → enemy death → fade-out, across multiple enemy placements

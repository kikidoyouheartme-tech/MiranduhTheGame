extends CharacterBody2D

const SPEED = 150.0
const JUMP_VELOCITY = -350.0
const GRAVITY = 900.0
const COMBO_WINDOW = 0.5
const JUMP_SCALE := 1.3       # multiplier applied on top of base_scale during jump
const DEATH_SCALE := 1.3      # multiplier applied on top of base_scale during death
const PLAYER_SCALE := 0.7     # overall size of the player, adjust to size down/up
const KNOCKBACK_FORCE := 250.0
const KNOCKBACK_FRICTION := 800.0

# --- Block/guard tuning ---
const BLOCK_STAMINA_MAX := 100.0
const BLOCK_DRAIN_PER_SEC := 25.0   # stamina lost per second just holding block
const BLOCK_HIT_COST := 20.0        # extra stamina lost each time a blocked hit lands
const BLOCK_REGEN_PER_SEC := 15.0   # stamina regen when not blocking
const BLOCK_REGEN_DELAY := 0.6      # seconds after releasing block before regen starts
const CHIP_DAMAGE_PERCENT := 0.2    # % of incoming damage that still gets through while blocking
const GUARD_BREAK_STUN := 0.8       # seconds stunned/vulnerable after guard breaks

enum State { IDLE, WALK, JUMP, ATTACK, HURT, BLOCK, GUARD_BREAK }
var state: State = State.IDLE
var facing: int = 1

var combo_step: int = 0
var combo_buffered: bool = false
var combo_timer: float = 0.0
var base_scale: Vector2
var is_dead: bool = false

var block_stamina: float = BLOCK_STAMINA_MAX
var block_regen_timer: float = 0.0
var is_blocking: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D

func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	GameManager.died.connect(_die)
	attack_shape.disabled = true
	base_scale = Vector2(PLAYER_SCALE, PLAYER_SCALE)
	sprite.scale = base_scale

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity.y += GRAVITY * delta
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0, KNOCKBACK_FRICTION * delta)
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if combo_timer > 0:
		combo_timer -= delta
	else:
		combo_step = 0

	_update_block_stamina(delta)

	if state == State.GUARD_BREAK:
		velocity.x = move_toward(velocity.x, 0, KNOCKBACK_FRICTION * delta)
		move_and_slide()
		return

	if state == State.ATTACK:
		var input_dir := Input.get_axis("ui_left", "ui_right")
		velocity.x = input_dir * SPEED * 0.5
		if input_dir != 0:
			facing = 1 if input_dir > 0 else -1
			sprite.flip_h = facing < 0
			attack_hitbox.position.x = abs(attack_hitbox.position.x) * facing

		if Input.is_action_just_pressed("ui_up") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			state = State.JUMP
			sprite.scale = base_scale * JUMP_SCALE
			sprite.play("jump")
			attack_shape.disabled = true
			move_and_slide()
			return

		_check_attack_input()
		move_and_slide()
		return

	if state == State.HURT:
		move_and_slide()
		return

	# --- Block handling ---
	if Input.is_action_pressed("block") and is_on_floor() and block_stamina > 0:
		if not is_blocking:
			is_blocking = true
			state = State.BLOCK
			velocity.x = 0
			sprite.scale = base_scale
			sprite.play("block")
		velocity.x = 0
		move_and_slide()
		return
	elif is_blocking:
		is_blocking = false
		state = State.IDLE
		sprite.play("idle")

	var input_dir := Input.get_axis("ui_left", "ui_right")

	if input_dir != 0:
		velocity.x = input_dir * SPEED
		facing = 1 if input_dir > 0 else -1
		sprite.flip_h = facing < 0
	else:
		velocity.x = 0

	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# DEBUG: Shift + Attack simulates a lethal hit to test the death sequence.
	# Remove this block once real enemies can call take_hit() themselves.
	if Input.is_key_pressed(KEY_SHIFT) and Input.is_action_just_pressed("attack"):
		take_hit(999)
		return

	if Input.is_action_just_pressed("attack") and is_on_floor():
		_start_attack()
		move_and_slide()
		return

	_update_state()
	move_and_slide()

func _update_block_stamina(delta: float) -> void:
	if is_blocking:
		block_stamina = max(block_stamina - BLOCK_DRAIN_PER_SEC * delta, 0)
		block_regen_timer = BLOCK_REGEN_DELAY
		if block_stamina <= 0:
			_guard_break()
	else:
		if block_regen_timer > 0:
			block_regen_timer -= delta
		else:
			block_stamina = min(block_stamina + BLOCK_REGEN_PER_SEC * delta, BLOCK_STAMINA_MAX)

func _guard_break() -> void:
	is_blocking = false
	state = State.GUARD_BREAK
	block_regen_timer = BLOCK_REGEN_DELAY
	sprite.scale = base_scale
	sprite.modulate = Color(1, 0.6, 0.6)
	sprite.play("hurt") if sprite.sprite_frames.has_animation("hurt") else sprite.play("idle")
	await get_tree().create_timer(GUARD_BREAK_STUN).timeout
	sprite.modulate = Color(1, 1, 1)
	if state == State.GUARD_BREAK:
		state = State.IDLE
		sprite.play("idle")

func _update_state() -> void:
	var new_state: State
	if not is_on_floor():
		new_state = State.JUMP
	elif velocity.x != 0:
		new_state = State.WALK
	else:
		new_state = State.IDLE

	if new_state != state:
		state = new_state
		match state:
			State.IDLE:
				sprite.scale = base_scale
				sprite.play("idle")
			State.WALK:
				sprite.scale = base_scale
				sprite.play("walk")
			State.JUMP:
				sprite.scale = base_scale * JUMP_SCALE
				sprite.play("jump")

func _start_attack() -> void:
	state = State.ATTACK
	sprite.scale = base_scale
	velocity.x = 0
	combo_step = min(combo_step + 1, 3)
	combo_timer = COMBO_WINDOW
	combo_buffered = false
	sprite.play("attack%d" % combo_step)
	attack_hitbox.position.x = abs(attack_hitbox.position.x) * facing
	attack_shape.disabled = false

func _check_attack_input() -> void:
	if Input.is_action_just_pressed("attack"):
		combo_buffered = true

func _on_animation_finished() -> void:
	if is_dead:
		if sprite.animation == "death_knockback":
			sprite.scale = base_scale * DEATH_SCALE
			sprite.play("death_ground")
		return

	if state != State.ATTACK:
		return

	attack_shape.disabled = true

	if combo_buffered and combo_step < 3:
		_start_attack()
	else:
		combo_step = 0
		state = State.IDLE
		sprite.scale = base_scale
		sprite.play("idle")

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	state = State.HURT
	attack_shape.disabled = true
	velocity.x = -facing * KNOCKBACK_FORCE
	velocity.y = -150
	sprite.scale = base_scale * DEATH_SCALE
	sprite.play("death_knockback")

func take_hit(amount: int) -> void:
	if is_dead:
		return

	if is_blocking and state == State.BLOCK:
		var chip: int = int(ceil(amount * CHIP_DAMAGE_PERCENT))
		GameManager.take_damage(chip)
		block_stamina = max(block_stamina - BLOCK_HIT_COST, 0)
		if block_stamina <= 0:
			_guard_break()
		if is_dead:
			return
		return

	GameManager.take_damage(amount)
	if is_dead:
		return
	state = State.HURT
	sprite.modulate = Color(1, 0.3, 0.3)
	await get_tree().create_timer(0.2).timeout
	sprite.modulate = Color(1, 1, 1)
	state = State.IDLE

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		GameManager.take_damage(20)

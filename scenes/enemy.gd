extends CharacterBody2D

@export var speed: float = 80.0
@export var chase_range: float = 200.0
@export var attack_range: float = 28.0
@export var attack_cooldown: float = 1.2
@export var attack_damage: int = 10
@export var enemy_scale: float = 0.7
@export var max_health: int = 30
@export var knockback_force: float = 120.0

const GRAVITY := 900.0
const HURT_FLINCH_TIME := 0.2
const KNOCKBACK_FRICTION := 600.0
const DEATH_KNOCKBACK_FORCE := 250.0
const FADE_OUT_DELAY := 0.4
const FADE_OUT_DURATION := 0.6

enum State { IDLE, WALK, ATTACK, HURT, DEAD }
var state: State = State.IDLE
var facing: int = -1  # -1 = facing left (art's native orientation is right, so -1 means flipped)

var current_health: int
var attack_timer: float = 0.0
var player: Node2D = null
var attack_hitbox_base_x: float = 0.0
var is_dead: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var hurt_box: Area2D = $HurtBox

func _ready() -> void:
	sprite.animation_finished.connect(_on_animation_finished)
	attack_shape.disabled = true

	scale = Vector2(enemy_scale, enemy_scale)
	attack_hitbox_base_x = abs(attack_hitbox.position.x)

	sprite.flip_h = facing < 0
	current_health = max_health
	hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	_find_player()

func _find_player() -> void:
	if player != null and is_instance_valid(player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		facing = 1 if player.global_position.x > global_position.x else -1
		sprite.flip_h = facing < 0

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity.y += GRAVITY * delta
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0, KNOCKBACK_FRICTION * delta)
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if attack_timer > 0:
		attack_timer -= delta

	if state == State.HURT:
		velocity.x = move_toward(velocity.x, 0, KNOCKBACK_FRICTION * delta)
		move_and_slide()
		return

	if state == State.ATTACK:
		velocity.x = 0
		move_and_slide()
		return

	if player == null or not is_instance_valid(player):
		_find_player()
		_set_state(State.IDLE)
		move_and_slide()
		return

	var distance: float = global_position.distance_to(player.global_position)
	facing = 1 if player.global_position.x > global_position.x else -1
	sprite.flip_h = facing < 0

	if distance <= attack_range and attack_timer <= 0:
		_start_attack()
	elif distance <= chase_range:
		velocity.x = facing * speed
		_set_state(State.WALK)
	else:
		velocity.x = 0
		_set_state(State.IDLE)

	move_and_slide()

func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	match state:
		State.IDLE:
			sprite.play("idle")
		State.WALK:
			sprite.play("walk")

func _start_attack() -> void:
	state = State.ATTACK
	velocity.x = 0
	attack_timer = attack_cooldown
	attack_hitbox.position.x = attack_hitbox_base_x * facing
	sprite.play("punch")
	attack_shape.disabled = false

func _on_animation_finished() -> void:
	if is_dead:
		return

	if state == State.ATTACK and sprite.animation == "punch":
		attack_shape.disabled = true
		state = State.IDLE
		sprite.play("idle")

func _on_hurt_box_area_entered(area: Area2D) -> void:
	if area.is_in_group("player_attack"):
		var damage: int = area.get("damage") if area.get("damage") != null else 10
		take_hit(damage, area)

func take_hit(amount: int, source: Area2D = null) -> void:
	if is_dead:
		return
	current_health = max(current_health - amount, 0)

	var knock_dir: int = facing
	if source:
		knock_dir = 1 if global_position.x > source.global_position.x else -1

	if current_health <= 0:
		_die(knock_dir)
		return

	velocity.x = knock_dir * knockback_force
	state = State.HURT
	attack_shape.disabled = true
	if sprite.sprite_frames.has_animation("hurt"):
		sprite.play("hurt")
	await get_tree().create_timer(HURT_FLINCH_TIME).timeout
	if state == State.HURT:
		state = State.IDLE
		sprite.play("idle")

func _die(knock_dir: int = 0) -> void:
	if is_dead:
		return
	is_dead = true
	state = State.DEAD
	attack_shape.disabled = true
	hurt_box.set_deferred("monitoring", false)

	if knock_dir == 0:
		knock_dir = -facing
	velocity.x = knock_dir * DEATH_KNOCKBACK_FORCE
	velocity.y = -150

	if sprite.sprite_frames.has_animation("dead"):
		sprite.play("dead")
	else:
		queue_free()
		return

	await get_tree().create_timer(FADE_OUT_DELAY).timeout
	_fade_out()

func _fade_out() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, FADE_OUT_DURATION)
	tween.tween_callback(queue_free)

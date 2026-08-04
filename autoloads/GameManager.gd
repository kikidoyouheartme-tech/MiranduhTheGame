extends Node

var current_health: int = 100
var max_health: int = 100
var score: int = 0
var unlocked_level: int = 1
var master_volume: float = 1.0
var sfx_volume: float = 1.0

func reset_run() -> void:
	current_health = max_health
	score = 0

func add_score(amount: int) -> void:
	score += amount

func take_damage(amount: int) -> void:
	current_health = max(current_health - amount, 0)

func heal(amount: int) -> void:
	current_health = min(current_health + amount, max_health)

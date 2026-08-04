extends Control

@onready var health_bar: TextureProgressBar = $HealthBar

func _process(_delta: float) -> void:
	health_bar.value = GameManager.current_health

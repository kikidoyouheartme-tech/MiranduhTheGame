extends Control

@onready var health_bar: TextureProgressBar = $HealthBar
@onready var stamina_bar: TextureProgressBar = $StaminaBar

func _process(_delta: float) -> void:
	health_bar.value = GameManager.current_health
	stamina_bar.value = GameManager.block_stamina

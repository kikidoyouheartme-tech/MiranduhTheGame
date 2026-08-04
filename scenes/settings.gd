extends Control

@onready var master_slider: HSlider = $VBoxContainer/MasterSlider
@onready var sfx_slider: HSlider = $VBoxContainer/SFXSlider
@onready var back_button: Button = $VBoxContainer/BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

extends Node2D

@onready var video_player: VideoStreamPlayer = $VideoStreamPlayer

func _ready() -> void:
	video_player.finished.connect(_on_video_finished)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event is InputEventMouseButton:
		_on_video_finished()

func _on_video_finished() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

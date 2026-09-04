extends Node2D

@export var radius: float = 11.0
@export var fill_color: Color = Color(0.22, 0.22, 0.24)

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color)

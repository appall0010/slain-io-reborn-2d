extends Node2D
## Простой "кулак" — рисуется кругом, как в оригинальном Slain.io.
## Не требует отдельной текстуры: если захочешь заменить на спрайт,
## просто добавь Sprite2D ребёнком и убери _draw().

@export var radius: float = 11.0
@export var fill_color: Color = Color(0.22, 0.22, 0.24) # тёмно-серый, как тело
@export var outline_color: Color = Color(0.1, 0.1, 0.11)

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 24, outline_color, 2.0)

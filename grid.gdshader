shader_type canvas_item;

// Настройки цветов (как на вашем скриншоте)
uniform vec4 bg_color : source_color = vec4(0.8, 0.95, 0.85, 1.0); // Светло-зеленый
uniform vec4 grid_color : source_color = vec4(0.7, 0.85, 0.75, 1.0); // Чуть более темный зеленый для линий

uniform float grid_size = 64.0; // Размер одной клетки в пикселях
uniform float line_thickness = 1.0; // Толщина линии

void fragment() {
	// Получаем глобальные координаты пикселя в мире
	// Если фон не двигается, можно использовать UV * vec2(ширина, высота)
	// Но для бесконечного/большого мира проще привязаться к UV и масштабу:
	vec2 pixel_pos = UV / TEXTURE_PIXEL_SIZE;
	
	// Вычисляем положение внутри конкретной клетки
	vec2 grid = mod(pixel_pos, grid_size);
	
	// Проверяем, находится ли пиксель на границе линии
	if (grid.x < line_thickness || grid.y < line_thickness) {
		COLOR = grid_color;
	} else {
		COLOR = bg_color;
	}
}

extends Control

const Style = preload("res://scripts/ui/style.gd")


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var center := size * Vector2(0.50, 0.51)
	var radius := minf(size.x, size.y) * 0.34
	var guide := Color("#263b47")
	var rule := Color("#4b6470")
	draw_style_box(Style.flat(Color("#13222c"), Style.EDGE, 12), Rect2(Vector2.ZERO, size))
	for index in range(-4, 5):
		var shift := index * radius * 0.23
		draw_line(center + Vector2(shift, -radius * 1.12), center + Vector2(shift, radius * 1.12), guide)
		draw_line(center + Vector2(-radius * 1.13, shift), center + Vector2(radius * 1.13, shift), guide)
	for scale_factor: float in [1.0, 0.76, 0.53]:
		draw_arc(center, radius * scale_factor, 0, TAU, 96, rule, 1.0, true)
	draw_arc(center, radius * 1.08, -0.67, 0.46, 44, Style.ACCENT, 2.2, true)
	draw_arc(center, radius * 1.08, 2.48, 3.59, 44, Style.ACCENT, 2.2, true)
	for index in range(32):
		var direction := Vector2.from_angle(index * TAU / 32.0)
		draw_line(center + direction * radius * 0.90, center + direction * radius * 0.96, rule, 1.0, true)
	draw_circle(center, radius * 0.32, Color("#673b32"), true, -1.0, true)
	draw_circle(center, radius * 0.24, Style.ACCENT, true, -1.0, true)
	draw_circle(center, radius * 0.17, Color("#eda07b"), true, -1.0, true)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(center + direction * radius * 0.058, center + direction * radius * 0.12, Style.INK, 2.0, true)
	draw_circle(center, 2.0, Style.INK)

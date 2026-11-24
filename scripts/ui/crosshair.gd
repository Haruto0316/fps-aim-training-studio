extends Control

var feedback := 0.0
var shot_flash := 0.0
var ads := false


func _draw() -> void:
	var center := size * 0.5
	var gap := 4.0 if ads else 5.0
	var length := 8.0 if ads else 12.0
	var paint := Color("#fff5df").lerp(Color("#ff936d"), shot_flash)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(center + direction * gap, center + direction * length, Color("#172129"), 4.0)
		draw_line(center + direction * gap, center + direction * length, paint, 2.0)
	draw_circle(center, 2.5, Color("#172129"))
	draw_circle(center, 1.3, Color("#fff5df"))
	if feedback > 0.0:
		var hit_color := Color(1.0, 0.62, 0.43, feedback)
		for diagonal: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + diagonal * 9.0, center + diagonal * 15.0, hit_color, 2.0, true)

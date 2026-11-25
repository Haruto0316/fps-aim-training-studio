extends Control

const Style = preload("res://scripts/ui/style.gd")
const Draft = preload("res://scripts/editor/editor_draft.gd")
const Route = preload("res://scripts/scenarios/route_path.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const FRAME := Vector2(320, 120)
const CENTER := Vector2(160, 55)
const AIM := Color("#88ece1")
const TRACK := Color("#537c85")
const GRID := Color("#223744")
const GROUND := Color("#101e29")
const CLICK_SPOTS := [Vector2(74, 52), Vector2(218, 39), Vector2(165, 75), Vector2(257, 65), Vector2(111, 30)]
const GROUP_SPOTS := [Vector2(68, 34), Vector2(148, 65), Vector2(245, 38), Vector2(98, 75),
	Vector2(211, 76), Vector2(166, 24), Vector2(274, 69), Vector2(41, 65)]
const REACTIVE_SPOTS := [Vector2(55, 64), Vector2(134, 31), Vector2(114, 72), Vector2(235, 43),
	Vector2(260, 70), Vector2(171, 63)]
const REACTIVE_BEATS := [0.65, 0.35, 0.95, 0.34, 0.70, 1.12]

var scenario: Dictionary
var time := 0.0
var redraw_wait := 0.0
var paths := {}
var areas := {}


func _init(definition: Dictionary, minimum: Vector2) -> void:
	scenario = definition
	custom_minimum_size = minimum
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if scenario.type == "custom":
		for entry: Dictionary in scenario.objects:
			if entry.kind == "spawn_area":
				areas[entry.id] = Draft.vector(entry.position)
			elif Draft.is_target(entry.kind) and not entry.route_points.is_empty():
				paths[entry.id] = Route.new(entry, scenario.objects)


func _ready() -> void:
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	set_process(is_visible_in_tree())


func _process(delta: float) -> void:
	time += delta
	redraw_wait += delta
	if redraw_wait >= 1.0 / 30.0:
		redraw_wait = fmod(redraw_wait, 1.0 / 30.0)
		queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, GROUND)
	var ratio := minf(size.x / FRAME.x, size.y / FRAME.y)
	if ratio <= 0.0:
		return
	var frame_transform := Transform2D(0.0, Vector2.ONE * ratio, 0.0, (size - FRAME * ratio) * 0.5)
	draw_set_transform_matrix(frame_transform)
	if scenario.type == "custom":
		_draw_custom(frame_transform)
	else:
		_draw_lane()
		match scenario.type:
			"static_clicking", "movement_practice":
				_draw_clicking()
			Scenario.APEX_HUMANOID:
				_draw_humanoid()
			"multi_target", "target_switching":
				_draw_group()
			_:
				_draw_tracking()
	draw_set_transform(Vector2.ZERO)
	draw_rect(bounds.grow(-0.5), Style.EDGE, false, 1.0)


func _draw_lane() -> void:
	var horizon := 83.0
	for x in range(16, 320, 24):
		draw_line(Vector2(x, 8), Vector2(x, horizon), GRID)
	for y in range(11, 83, 18):
		draw_line(Vector2(8, y), Vector2(312, y), GRID)
	for x in range(-120, 441, 40):
		draw_line(Vector2(160 + (x - 160) * 0.25, horizon), Vector2(x, 120), GRID)
	for y in [83, 91, 105]:
		draw_line(Vector2(0, y), Vector2(320, y), GRID)


func _draw_clicking() -> void:
	var beat := time / 1.15
	var index := int(beat) % CLICK_SPOTS.size()
	var phase := fposmod(beat, 1.0)
	var point: Vector2 = CLICK_SPOTS[index]
	if scenario.type == "movement_practice":
		draw_colored_polygon(PackedVector2Array([Vector2(20, 99), Vector2(87, 78), Vector2(149, 78), Vector2(149, 99)]), Color("#345965"))
		draw_line(Vector2(20, 99), Vector2(87, 78), TRACK, 2.0, true)
		draw_rect(Rect2(207, 81, 87, 16), Color("#345965"))
		_draw_player(54 + 211 * pingpong(time * 0.52, 1.0))
	var previous: Vector2 = CLICK_SPOTS[posmod(index - 1, CLICK_SPOTS.size())]
	if phase < 0.78:
		_draw_target(point)
	_draw_reticle(previous.lerp(point, smoothstep(0.08, 0.73, phase)))
	if phase >= 0.78:
		_draw_hit(point, inverse_lerp(0.78, 1.0, phase))


func _draw_humanoid() -> void:
	var beat := time / 1.2
	var index := int(beat)
	var phase := fposmod(beat, 1.0)
	var height := 35.0 * float(scenario.target.height) / 1.8
	var center := Vector2(CLICK_SPOTS[index % CLICK_SPOTS.size()].x, 87)
	var head := center - Vector2(0, height * 0.91)
	var torso := center - Vector2(0, height * 0.65)
	var leg := center + Vector2(height * 0.065, -height * 0.25)
	var aim_points := [head, torso, leg]
	var point: Vector2 = aim_points[index % aim_points.size()]
	if phase < 0.78:
		var paint := Style.ACCENT
		draw_circle(head, height * 0.081, paint.lightened(0.28), true, -1.0, true)
		draw_line(torso - Vector2(0, height * 0.10), torso + Vector2(0, height * 0.10), paint, height * 0.24, true)
		for side: float in [-1.0, 1.0]:
			var shin := center + Vector2(side * height * 0.065, -height * 0.05)
			draw_line(shin, shin - Vector2(0, height * 0.40), paint.darkened(0.21), height * 0.11, true)
			var shoulder := torso + Vector2(side * height * 0.155, -height * 0.13)
			draw_line(shoulder, shoulder + Vector2(0, height * 0.28), paint.darkened(0.05), height * 0.09, true)
	var previous_x: float = CLICK_SPOTS[posmod(index - 1, CLICK_SPOTS.size())].x
	_draw_reticle(Vector2(previous_x, 56).lerp(point, smoothstep(0.10, 0.72, phase)))
	if phase >= 0.78:
		_draw_hit(point, inverse_lerp(0.78, 1.0, phase))


func _draw_group() -> void:
	var switching: bool = scenario.type == "target_switching"
	var count: int = scenario.target.count
	var beat := time / 1.1
	var step := int(beat)
	var phase := fposmod(beat, 1.0)
	var index := step % count
	var points: Array[Vector2] = []
	for slot in range(count):
		var point: Vector2 = GROUP_SPOTS[slot]
		if not switching:
			var visits := floori(float(step - slot + count - 1) / count)
			point.y += 12.0 * sin(visits * PI * 0.5)
		points.append(point)
		if switching or slot != index or phase < 0.78:
			_draw_target(point, not switching or slot == index)
	var active := points[index]
	if switching:
		draw_colored_polygon(PackedVector2Array([active + Vector2(-5, -19), active + Vector2(5, -19), active + Vector2(0, -12)]), AIM)
	_draw_reticle(points[posmod(index - 1, count)].lerp(active, smoothstep(0.05, 0.73, phase)))
	if phase >= 0.78:
		_draw_hit(active, inverse_lerp(0.78, 1.0, phase))


func _draw_tracking() -> void:
	var kind: String = scenario.type
	var speed := clampf(float(scenario.target.speed) / 3.0, 0.35, 2.6)
	var t := time * speed
	var elimination := kind in ["strafe_elimination", "elimination_training"]
	var beat := 3.0 if kind == "elimination_training" else 2.15
	var phase := fposmod(t, beat) / beat
	var point := _tracking_position(t)
	var trail := PackedVector2Array()
	for index in range(13):
		trail.append(_tracking_position(t - 0.67 + index * 0.05))
	draw_polyline(trail, TRACK, 1.7, true)
	if scenario.player.movement_enabled:
		_draw_player(160 + 98 * sin(t * 1.25 + 0.7))
	var reticle := _tracking_position(t - 0.07)
	if kind == "cover_tracking":
		var cover := Rect2(133, 17, 54, 74)
		_draw_target(point)
		draw_rect(cover, Color("#365260"))
		draw_rect(cover, TRACK, false, 2.0)
		for x in [145, 160, 175]:
			draw_line(Vector2(x, 20), Vector2(x, 88), Color("#476773"))
		_draw_reticle(reticle, Color("#7b969a") if cover.has_point(point) else AIM)
	elif not elimination or phase < 0.83:
		_draw_target(point)
		if elimination:
			var health: int = scenario.target.health
			var damage: int = scenario.weapon.damage
			var hits := ceili(float(health) / damage)
			var remaining := health - floori(phase / 0.83 * hits) * damage
			var width := 42.0 if kind == "elimination_training" else 32.0
			var top := point - Vector2(width * 0.5, 21)
			draw_rect(Rect2(top, Vector2(width, 4)), GRID)
			draw_rect(Rect2(top, Vector2(width * remaining / health, 4)), AIM)
		_draw_reticle(reticle)
	elif phase < 0.95:
		_draw_hit(point, inverse_lerp(0.83, 0.95, phase))


func _tracking_position(t: float) -> Vector2:
	match scenario.type:
		"smooth_tracking":
			var wave := t * TAU / 3.6
			match scenario.target.behavior:
				"vertical": return CENTER + Vector2(0, 28 * sin(wave))
				"circle": return CENTER + Vector2(79 * cos(wave), 27 * sin(wave))
				_: return CENTER + Vector2(100 * sin(wave), 0)
		"reactive_tracking":
			var moment := fposmod(t, 4.11)
			for index in range(REACTIVE_BEATS.size()):
				if moment <= REACTIVE_BEATS[index]:
					return REACTIVE_SPOTS[index].lerp(REACTIVE_SPOTS[(index + 1) % REACTIVE_SPOTS.size()], moment / REACTIVE_BEATS[index])
				moment -= REACTIVE_BEATS[index]
		"movement_tracking":
			var jump := fposmod(t * 1.15, 1.0)
			return Vector2(66 + 190 * pingpong(t * 0.74, 1.0), 75 - 142 * jump * (1.0 - jump))
		"strafe_elimination", "elimination_training":
			return CENTER + Vector2(102 * sin(t * 2.45), 9 * sin(t * 4.2))
	return CENTER + Vector2(105 * sin(t * 1.72), 0)


func _draw_player(x: float) -> void:
	draw_line(Vector2(48, 107), Vector2(272, 107), TRACK, 1.2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(x, 97), Vector2(x - 6, 112), Vector2(x + 6, 112)]), AIM)


func _draw_target(point: Vector2, highlighted := true) -> void:
	var radius := remap(scenario.target.radius, 0.08, 0.65, 5.5, 11.0)
	var color := Style.ACCENT if highlighted else Color("#a37365")
	draw_circle(point, radius + 3, Color(color, 0.24), true, -1.0, true)
	draw_circle(point, radius, color, true, -1.0, true)
	draw_circle(point + Vector2(-2, -2), radius * 0.32, Color("#ffd7bf"), true, -1.0, true)


func _draw_reticle(point: Vector2, color := AIM) -> void:
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(point + direction * 6, point + direction * 14, color, 2.0, true)


func _draw_hit(point: Vector2, phase: float) -> void:
	draw_arc(point, 7 + 11 * phase, 0, TAU, 22, Color(AIM, 1.0 - phase), 2.2, true)


func _draw_custom(frame_transform: Transform2D) -> void:
	var map_scale := minf(270.0 / scenario.map.width, 96.0 / scenario.map.depth)
	var map_size := Vector2(scenario.map.width, scenario.map.depth) * map_scale
	var map_rect := Rect2((FRAME - map_size) * 0.5, map_size)
	draw_rect(map_rect, Color("#182c38"))
	draw_rect(map_rect, TRACK, false, 1.0)
	for entry: Dictionary in scenario.objects:
		if Draft.is_target(entry.kind) or entry.kind == "route_point":
			continue
		var origin := Draft.vector(entry.position)
		var dimensions := Draft.vector(entry.size)
		var marker := _project(origin, map_scale)
		var color := Color(entry.color)
		if entry.kind == "player_start":
			draw_circle(marker, 4.0, color, true, -1.0, true)
		else:
			var footprint := Vector2(dimensions.x, dimensions.z) * map_scale
			draw_set_transform_matrix(frame_transform * Transform2D(-deg_to_rad(entry.rotation[1]), marker))
			draw_rect(Rect2(-footprint * 0.5, footprint), color, entry.kind != "spawn_area")
			draw_set_transform_matrix(frame_transform)
	for entry: Dictionary in scenario.objects:
		if not Draft.is_target(entry.kind):
			continue
		var origin: Vector3 = areas.get(entry.spawn_area_id, Draft.vector(entry.position))
		var path: Route = paths.get(entry.id)
		if path != null and path.length > 0.0:
			var trace := PackedVector2Array()
			for index in range(21):
				trace.append(_project(path.curve.sample_baked(path.length * index / 20.0), map_scale))
			draw_polyline(trace, TRACK, 1.5, true)
			origin = path.position_at(time * entry.speed)
		elif entry.behavior != "static":
			var wave: float = entry.amplitude * sin(time * entry.speed / entry.amplitude)
			match entry.behavior:
				"vertical": origin.y += wave
				"jump": origin.y += absf(wave)
				"reactive": origin += Vector3(wave, 0.3 * entry.amplitude * sin(time * entry.speed), 0)
				_: origin.x += wave
		var point := _project(origin, map_scale)
		var color := Color(entry.color)
		draw_circle(point, 6, Color(color, 0.26), true, -1.0, true)
		draw_circle(point, 3.7, color, true, -1.0, true)


func _project(point: Vector3, map_scale: float) -> Vector2:
	return FRAME * 0.5 + Vector2(point.x, point.z - 0.22 * point.y) * map_scale

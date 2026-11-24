extends RefCounted

const Arena = preload("res://scripts/training/arena.gd")
const Scenario = preload("res://scripts/scenarios/scenario.gd")
const INACTIVE_COLOR := Color("#6d91a3")

var arena: Arena
var targets: Array[StaticBody3D] = []
var spawn_regions: Array[Rect2] = []
var spawn_z: float
var slots := {}
var presented_at := {}
var pending: Array[StaticBody3D] = []
var rng: RandomNumberGenerator
var switching: bool
var cue: Label3D
var eye: Vector3
var radius: float
var color: Color
var active: StaticBody3D
var previous: StaticBody3D
var cue_since := -1
var switch_count := 0


func _init(stage: Arena, tuning: Dictionary, origin: Vector3, is_switching: bool, random: RandomNumberGenerator) -> void:
	arena = stage
	rng = random
	switching = is_switching
	color = Color.html(tuning.color)
	eye = origin
	radius = tuning.radius
	targets.append(arena.target)
	for index in range(1, int(tuning.count)):
		targets.append(arena.create_target(tuning.radius, color))
	for body in targets:
		body.collision_layer = 0
		pending.append(body)
	spawn_z = origin.z - tuning.depth
	_build_spawn_regions(tuning)
	if switching:
		cue = Label3D.new()
		cue.text = "▼"
		cue.pixel_size = clampf(radius * 0.025, 0.003, 0.009)
		cue.outline_size = 4
		cue.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cue.hide()
		arena.add_child(cue)


func _build_spawn_regions(tuning: Dictionary) -> void:
	var bottom := maxf(eye.y - tuning.y_extent, radius + 0.055)
	var corner := Vector2(eye.x - tuning.x_extent, bottom)
	var span := Vector2(2.0 * tuning.x_extent, eye.y + tuning.y_extent - bottom)
	var spacing := 2.0 * (radius + 0.045)
	var needed := targets.size() + 1
	# Keep a spare region so a replacement can leave its previous region even at minimum extents.
	var layouts: Array[Vector2i] = [Vector2i(Scenario.group_columns(targets.size()), 2)]
	for rows in range(1, needed + 1):
		if rows == 2:
			continue
		var columns := ceili(float(needed) / rows)
		if (columns - 1) * spacing <= span.x and (rows - 1) * spacing <= span.y:
			layouts.append(Vector2i(columns, rows))
	var layout := layouts[rng.randi_range(0, layouts.size() - 1)]
	# Separate the regions by the minimum center distance while using all remaining room for variation.
	var room := (span - Vector2(layout - Vector2i.ONE) * spacing).max(Vector2.ZERO) / Vector2(layout)
	var stride := room + Vector2.ONE * spacing
	for row in range(layout.y):
		for column in range(layout.x):
			spawn_regions.append(Rect2(corner + Vector2(column, row) * stride, room))


func present(timestamp: int) -> void:
	for body in pending:
		var occupied := slots.values()
		var available: Array[int] = []
		for index in range(spawn_regions.size()):
			if index not in occupied:
				available.append(index)
		var slot := available[rng.randi_range(0, available.size() - 1)]
		slots[body] = slot
		var region := spawn_regions[slot]
		var x := rng.randf_range(region.position.x, region.end.x)
		var y := rng.randf_range(region.position.y, region.end.y)
		body.position = Vector3(x, y, spawn_z)
		body.collision_layer = 2
		body.force_update_transform()
		body.show()
		presented_at[body] = timestamp
		if switching:
			arena.set_target_color(body, INACTIVE_COLOR)
	pending.clear()
	if switching and active == null:
		var choices := targets.duplicate()
		choices.erase(previous)
		active = choices[rng.randi_range(0, choices.size() - 1)]
		arena.set_target_color(active, color)
		var front := (eye - active.position).normalized() * (radius + 0.03)
		cue.position = active.position + front + Vector3.UP * (radius * 0.45)
		cue.show()
		cue_since = timestamp


func reaction_at(body: Variant, timestamp: int) -> int:
	if switching:
		return timestamp - cue_since if active != null and body == active else -1
	var shown: int = presented_at.get(body, -1)
	return timestamp - shown if shown >= 0 else -1


func accept(body: StaticBody3D) -> void:
	if switching:
		arena.set_target_color(active, INACTIVE_COLOR)
		previous = active
		active = null
		cue.hide()
		switch_count += 1
		return
	presented_at.erase(body)
	body.hide()
	body.collision_layer = 0
	pending.append(body)

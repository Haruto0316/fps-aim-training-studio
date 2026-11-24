extends Node3D

const Draft = preload("res://scripts/editor/editor_draft.gd")
const Geometry = preload("res://scripts/editor/object_geometry.gd")
const PLAY_AREA_LAYER := 8

var target: StaticBody3D


func build(scenario: Dictionary) -> void:
	if scenario.type == "custom":
		_build_environment(Color.html(scenario.map.background), scenario.map.light)
		if scenario.player.movement_enabled:
			_add_boundaries(scenario.map.width, scenario.map.depth)
		return
	var wall := Color.html(scenario.map.backdrop_color)
	var floor_color := Color("#202d35")
	var trim := Color("#46636e")
	var guide := Color("#304651")
	var accent := Color("#ef9466")
	_build_environment(wall.darkened(0.32), 0.75)

	box(Vector3(0, -0.15, -5), Vector3(13, 0.3, 16), floor_color, true)
	box(Vector3(0, 2.5, -11), Vector3(13, 5, 0.25), wall, true)
	for side: int in [-1, 1]:
		box(Vector3(side * 6.3, 2.5, -5), Vector3(0.35, 5, 16), wall.darkened(0.26), true)
		box(Vector3(side * 5.75, 2.37, -10.82), Vector3(0.20, 4.74, 0.14), trim)
		box(Vector3(side * 5.72, 1.38, -10.73), Vector3(0.032, 2.2, 0.04), accent, false, true)
	box(Vector3(0, 5.0, -5), Vector3(13, 0.18, 16), wall.darkened(0.3), true)
	box(Vector3(0, 2.5, 3), Vector3(13, 5, 0.25), wall.darkened(0.3), true)
	for y in range(1, 10):
		box(Vector3(0, y * 0.45, -10.86), Vector3(11.35, 0.013, 0.02), guide)
	for x in range(-5, 6):
		box(Vector3(x, 2.35, -10.86), Vector3(0.013, 4.7, 0.02), guide)
		box(Vector3(x, 0.004, -5.5), Vector3(0.014, 0.008, 10.7), guide)
	for z in range(-10, 1):
		box(Vector3(0, 0.004, z), Vector3(11.35, 0.008, 0.014), guide)
	box(Vector3(0, 4.65, -10.74), Vector3(11.4, 0.035, 0.04), trim, false, true)
	box(Vector3(0, 0.08, -10.73), Vector3(11.4, 0.044, 0.04), accent, false, true)
	for obstacle: Dictionary in scenario.map.get("obstacles", []):
		var center := Vector3(obstacle.center[0], obstacle.center[1], obstacle.center[2])
		var dimensions := Vector3(obstacle.size[0], obstacle.size[1], obstacle.size[2])
		box(center, dimensions, Color.html(obstacle.color), true, false, obstacle.pitch)
	target = create_target(scenario.target.radius, Color.html(scenario.target.color), scenario.target.has("health"))


func _build_environment(background: Color, energy: float) -> void:
	var atmosphere := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = background
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#cfe9f0")
	environment.ambient_light_energy = 0.85
	atmosphere.environment = environment
	add_child(atmosphere)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-33.0, -25.0, 0.0)
	light.light_energy = energy
	add_child(light)


func _add_boundaries(width: float, depth: float) -> void:
	for side: float in [-1.0, 1.0]:
		_add_boundary(Vector3(side * (width * 0.5 + 0.1), 0, 0), Vector3(0.2, 102.0, depth + 0.4))
		_add_boundary(Vector3(0, 0, side * (depth * 0.5 + 0.1)), Vector3(width + 0.4, 102.0, 0.2))


func _add_boundary(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PLAY_AREA_LAYER
	body.position = center
	add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)


func create_custom_object(entry: Dictionary, is_target: bool) -> StaticBody3D:
	var body: StaticBody3D
	if is_target:
		var mover := AnimatableBody3D.new()
		mover.sync_to_physics = false
		body = mover
		body.collision_layer = 0
		body.collision_mask = 0
		body.hide()
	else:
		body = StaticBody3D.new()
	body.position = Draft.vector(entry.position)
	body.rotation_degrees = Draft.vector(entry.rotation)
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(body)
	var render_mesh := Geometry.mesh_for(entry.get("shape", "box"))
	var size := Draft.vector(entry.size)
	var collider := CollisionShape3D.new()
	collider.shape = Geometry.collision_for(render_mesh, size)
	body.add_child(collider)
	var render := MeshInstance3D.new()
	render.mesh = render_mesh
	render.scale = size / render_mesh.get_aabb().size
	render.material_override = _material(Color.html(entry.color))
	render.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(render)
	return body


func box(
	center: Vector3, dimensions: Vector3, color: Color, solid := false, luminous := false, pitch := 0.0
) -> void:
	var parent: Node3D = self
	var location := center
	if solid:
		var body := StaticBody3D.new()
		body.position = center
		body.rotation_degrees.x = pitch
		add_child(body)
		var collision := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = dimensions
		collision.shape = box_shape
		body.add_child(collision)
		parent = body
		location = Vector3.ZERO
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = _material(color, luminous)
	instance.mesh = mesh
	instance.position = location
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func create_target(radius: float, color: Color, moving := false) -> StaticBody3D:
	var body: StaticBody3D
	if moving:
		var mover := AnimatableBody3D.new()
		mover.sync_to_physics = false
		body = mover
	else:
		body = StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	body.hide()
	add_child(body)

	var shape := SphereShape3D.new()
	shape.radius = radius
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	var paint := _material(color)
	paint.emission_enabled = true
	paint.emission = color
	paint.emission_energy_multiplier = 0.26
	sphere.material = paint
	var instance := MeshInstance3D.new()
	instance.mesh = sphere
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(instance)
	return body


func set_target_color(body: StaticBody3D, paint: Color) -> void:
	var instance: MeshInstance3D = body.get_child(1)
	var material: StandardMaterial3D = instance.mesh.material
	material.albedo_color = paint
	material.emission = paint


func _material(color: Color, luminous := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if luminous:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

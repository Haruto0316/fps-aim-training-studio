extends SubViewportContainer

signal picked(id: int)
signal moved(id: int, position: Vector3)

const Draft = preload("res://scripts/editor/editor_draft.gd")
const Geometry = preload("res://scripts/editor/object_geometry.gd")
const Route = preload("res://scripts/scenarios/route_path.gd")
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_COLORS := [Color("#ec7f78"), Color("#89ce9e"), Color("#7bacf5")]
const ACCENT := Color("#ffad83")

var world: Node3D
var camera: Camera3D
var environment: Environment
var light: DirectionalLight3D
var grid := ImmediateMesh.new()
var outline := ImmediateMesh.new()
var route_lines := ImmediateMesh.new()
var lines := StandardMaterial3D.new()
var nodes := {}
var selected := 0
var axis := -1
var snap := true
var pivot := Vector3(0, 0.8, -3.0)
var yaw := deg_to_rad(30.0)
var pitch := deg_to_rad(37.0)
var distance := 12.0
var drag_id := 0
var drag_mouse := Vector2.ZERO
var drag_origin := Vector3.ZERO
var drag_started := false
var route: Route
var route_ghost: MeshInstance3D
var preview_speed := 0.0
var preview_travel := 0.0


func _ready() -> void:
	stretch = true
	mouse_target = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var sky := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d4e5ef")
	environment.ambient_light_energy = 0.8
	sky.environment = environment
	world.add_child(sky)
	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-49.0, -31.0, 0.0)
	world.add_child(light)
	lines.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.vertex_color_use_as_albedo = true
	lines.no_depth_test = true
	for mesh: ImmediateMesh in [grid, outline, route_lines]:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(instance)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 180.0
	world.add_child(camera)
	camera.make_current()
	set_process(false)
	get_window().focus_exited.connect(cancel_drag)
	_update_camera()


func update_map(settings: Dictionary) -> void:
	environment.background_color = Color.html(settings.background)
	light.light_energy = settings.light
	var width: float = settings.width * 0.5
	var depth: float = settings.depth * 0.5
	grid.clear_surfaces()
	# The ground grid shares the floor plane and remains visible at open edges.
	grid.surface_begin(Mesh.PRIMITIVE_LINES, _grid_style())
	for x in range(ceili(-width), floori(width) + 1):
		var color := Color("#597178") if x == 0 else Color("#314955")
		_line(grid, Vector3(x, 0.012, -depth), Vector3(x, 0.012, depth), color)
	for z in range(ceili(-depth), floori(depth) + 1):
		var color := Color("#597178") if z == 0 else Color("#314955")
		_line(grid, Vector3(-width, 0.012, z), Vector3(width, 0.012, z), color)
	for side: float in [-1.0, 1.0]:
		_line(grid, Vector3(side * width, 0.014, -depth), Vector3(side * width, 0.014, depth), Color("#6f949d"))
		_line(grid, Vector3(-width, 0.014, side * depth), Vector3(width, 0.014, side * depth), Color("#6f949d"))
	grid.surface_end()


func update_object(id: int, entry: Dictionary) -> void:
	var node: MeshInstance3D = nodes.get(id)
	if entry.is_empty():
		if node != null:
			nodes.erase(id)
			node.hide()
			node.queue_free()
		_rebuild_outline()
		return
	if node == null:
		node = MeshInstance3D.new()
		world.add_child(node)
		nodes[id] = node
	var shape: String = entry.get("shape", "box")
	if node.mesh == null or node.get_meta("shape", "") != shape:
		node.mesh = Geometry.mesh_for(shape)
		node.set_meta("shape", shape)
	node.position = Draft.vector(entry.position)
	node.rotation_degrees = Draft.vector(entry.rotation)
	node.scale = Draft.vector(entry.size) / node.get_aabb().size
	var paint := Color.html(entry.color)
	var material := StandardMaterial3D.new()
	material.albedo_color = paint
	material.roughness = 0.85
	if entry.kind in ["spawn_area", "route_point", "player_start"]:
		material.emission_enabled = true
		material.emission = paint
		material.emission_energy_multiplier = 0.18
	if entry.kind == "spawn_area":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.23
	node.material_override = material
	_rebuild_outline()


func show_route(path: Route, entry: Dictionary, preview: bool) -> void:
	route = path
	route_lines.clear_surfaces()
	if route_ghost != null:
		route_ghost.hide()
	set_process(false)
	if route == null or route.length <= 0.0:
		return
	var points := route.curve.get_baked_points()
	route_lines.surface_begin(Mesh.PRIMITIVE_LINES, lines)
	for index in range(1, points.size()):
		_line(route_lines, points[index - 1], points[index], Color("#87dfc7"))
	route_lines.surface_end()
	if not preview:
		return
	if route_ghost == null:
		route_ghost = MeshInstance3D.new()
		var paint := StandardMaterial3D.new()
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		paint.albedo_color = Color(0.45, 0.87, 0.74, 0.68)
		route_ghost.material_override = paint
		world.add_child(route_ghost)
	route_ghost.mesh = Geometry.mesh_for(entry.shape)
	route_ghost.scale = Draft.vector(entry.size) / route_ghost.mesh.get_aabb().size
	route_ghost.rotation_degrees = Draft.vector(entry.rotation)
	route_ghost.position = route.position_at(0.0)
	route_ghost.show()
	preview_speed = entry.speed
	preview_travel = 0.0
	set_process(true)


func _process(delta: float) -> void:
	preview_travel += delta * preview_speed
	route_ghost.position = route.position_at(preview_travel)


func select_object(id: int) -> void:
	selected = id
	_rebuild_outline()


func focus_selection() -> void:
	var node: MeshInstance3D = nodes.get(selected)
	if node != null:
		pivot = node.position
		distance = clampf((node.scale * node.get_aabb().size).length() * 2.1, 3.0, 45.0)
	else:
		pivot = Vector3(0, 0.8, -3)
		distance = 12.0
	_update_camera()


func cancel_drag() -> bool:
	if drag_id == 0:
		return false
	var node: MeshInstance3D = nodes.get(drag_id)
	if node != null:
		node.position = drag_origin
	drag_id = 0
	drag_started = false
	_rebuild_outline()
	return true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus()
				_begin_drag(event.position)
			else:
				if drag_id != 0:
					_preview_drag(event.position)
				_finish_drag()
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.87 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.15), 1.3, 75.0)
			_update_camera()
			accept_event()
	elif event is InputEventMouseMotion:
		if drag_id != 0:
			_preview_drag(event.position)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.009
			pitch = clampf(pitch + event.relative.y * 0.008, deg_to_rad(8.0), deg_to_rad(86.0))
			_update_camera()
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			pivot += (-camera.basis.x * event.relative.x + camera.basis.y * event.relative.y) * distance * 0.002
			_update_camera()


func pick_at(point: Vector2) -> int:
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var nearest := INF
	var chosen := 0
	for id: int in nodes:
		var node: MeshInstance3D = nodes[id]
		var inverse := node.global_transform.affine_inverse()
		var local_origin := inverse * origin
		var local_direction := inverse.basis * direction
		var intersection: Variant = node.get_aabb().intersects_ray(local_origin, local_direction)
		if intersection == null:
			continue
		if node.mesh is SphereMesh:
			intersection = _sphere_hit(local_origin, local_direction)
			if intersection == null:
				continue
		var hit: Vector3 = node.global_transform * intersection
		var depth := origin.distance_squared_to(hit)
		if depth < nearest:
			nearest = depth
			chosen = id
	return chosen


func _sphere_hit(origin: Vector3, direction: Vector3) -> Variant:
	var a := direction.length_squared()
	var b := direction.dot(origin)
	var squared := b * b - a * (origin.length_squared() - 0.25)
	if squared < 0.0:
		return null
	var near := (-b - sqrt(squared)) / a
	var far := (-b + sqrt(squared)) / a
	var distance_to_hit := near if near >= 0.0 else far
	return origin + direction * distance_to_hit if distance_to_hit >= 0.0 else null


func _begin_drag(point: Vector2) -> void:
	drag_id = pick_at(point)
	picked.emit(drag_id)
	if drag_id != 0:
		drag_mouse = point
		drag_origin = nodes[drag_id].position
		drag_started = false


func _preview_drag(point: Vector2) -> void:
	var offset := point - drag_mouse
	if not drag_started and offset.length_squared() < 16.0:
		return
	drag_started = true
	var node: MeshInstance3D = nodes.get(drag_id)
	if node == null:
		cancel_drag()
		return
	var next := drag_origin
	if axis < 0:
		var plane := Plane(Vector3.UP, drag_origin.y)
		var start: Variant = plane.intersects_ray(camera.project_ray_origin(drag_mouse), camera.project_ray_normal(drag_mouse))
		var end: Variant = plane.intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
		if start == null or end == null:
			return
		next += end - start
		if snap:
			next.x = snappedf(next.x, 0.5)
			next.z = snappedf(next.z, 0.5)
	else:
		var direction: Vector3 = AXES[axis]
		var projected := camera.unproject_position(drag_origin + direction) - camera.unproject_position(drag_origin)
		if projected.length_squared() < 16.0:
			return
		next += direction * (offset.dot(projected) / projected.length_squared())
		if snap:
			next[axis] = snappedf(next[axis], 0.5)
	node.position = next.clamp(Vector3.ONE * -50, Vector3.ONE * 50)
	_rebuild_outline()


func _finish_drag() -> void:
	var id := drag_id
	var should_commit := drag_started
	drag_id = 0
	drag_started = false
	if should_commit and nodes.has(id):
		moved.emit(id, nodes[id].position)


func _update_camera() -> void:
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.look_at_from_position(pivot + direction * distance, pivot, Vector3.UP)


func _rebuild_outline() -> void:
	outline.clear_surfaces()
	var node: MeshInstance3D = nodes.get(selected)
	if node == null:
		return
	var bounds := node.get_aabb().grow(0.025)
	var transform_3d := node.global_transform
	outline.surface_begin(Mesh.PRIMITIVE_LINES, lines)
	for i in range(8):
		for bit in [1, 2, 4]:
			if not (i & bit):
				_line(outline, transform_3d * bounds.get_endpoint(i), transform_3d * bounds.get_endpoint(i | bit), ACCENT)
	var center := node.position
	var length := clampf((node.scale * node.get_aabb().size).length() * 0.65, 0.55, 2.5)
	for index in range(3):
		var color: Color = AXIS_COLORS[index]
		if axis >= 0 and axis != index:
			color = color.darkened(0.6)
		_line(outline, center, center + AXES[index] * length, color)
	outline.surface_end()


func _grid_style() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	return material


func _line(mesh: ImmediateMesh, first: Vector3, last: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(first)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(last)

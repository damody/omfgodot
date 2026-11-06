# 2.5D look test: generated terrain and real wall geometry under a tilted perspective camera,
# with billboard units. World units map to x/-z at 1/100.
# godot --path omgd/game --script res://tests/hd25_preview.gd -- OUT.png LAYOUT.json
extends SceneTree

const WORLD_SCALE := 0.01
const WALL_HEIGHT := 1.6
const BRUSH_HEIGHT := 0.7
const HERO_HEIGHT := 2.2
const SHOT_AFTER_MS := 2500

var out_path := ""
var started := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_path = args[0]
	started = Time.get_ticks_msec()
	root.size = Vector2i(1280, 720)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var world := Node3D.new()
	root.add_child(world)
	_add_environment(world)
	_add_ground(world, layout)
	for rect: Dictionary in layout.terrain:
		_add_block(world, rect, WALL_HEIGHT, _material(Color(0.47, 0.45, 0.41), 0.09))
	for rect: Dictionary in layout.brushes:
		_add_block(world, rect, BRUSH_HEIGHT, _material(Color(0.22, 0.42, 0.17), 0.16))

	var middle := _extent(layout).get_center()
	var center := _world(middle.x, middle.y)
	var cases := [["idle", true], ["move", true], ["attack", true], ["idle", false], ["move", false], ["attack", false]]
	for i in cases.size():
		var unit := UnitSprite3D.new()
		world.add_child(unit)
		if not unit.setup("saika_magoichi", HERO_HEIGHT):
			printerr("missing sprite")
			quit(2)
			return
		unit.position = center + Vector3(-5.5 + (i % 3) * 5.5, 0, -2.5 + (i / 3) * 5.0)
		unit.play_slot(cases[i][0])
		unit.set_facing_right(cases[i][1])
		unit.animation_finished.connect(unit.play_slot.bind(cases[i][0]))
		_add_contact_shadow(world, unit.position)

	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.far = 400.0
	world.add_child(camera)
	camera.look_at_from_position(center + Vector3(0, 20.0, 18.0), center, Vector3.UP)
	camera.attributes = _camera_attributes()
	camera.make_current()


func _add_environment(world: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	world.add_child(sun)
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.5, 0.62, 0.72)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.62, 0.68, 0.82)
	settings.ambient_light_energy = 0.55
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.ssao_enabled = true
	settings.ssao_intensity = 2.5
	settings.glow_enabled = true
	settings.glow_intensity = 0.25
	var holder := WorldEnvironment.new()
	holder.environment = settings
	world.add_child(holder)


func _camera_attributes() -> CameraAttributesPractical:
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = 34.0
	attributes.dof_blur_far_transition = 18.0
	attributes.dof_blur_amount = 0.06
	return attributes


func _add_ground(world: Node3D, layout: Dictionary) -> void:
	var extent := _extent(layout)
	var low: Vector2 = extent.position
	var high: Vector2 = extent.end
	var mesh := PlaneMesh.new()
	mesh.size = (high - low) * WORLD_SCALE
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://art/maps/three_lane_training.jpg")
	material.roughness = 1.0
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.position = _world((low.x + high.x) / 2.0, (low.y + high.y) / 2.0)
	world.add_child(ground)


# Same extent render_layout.py used for the guide the terrain was painted from.
func _extent(layout: Dictionary) -> Rect2:
	if layout.bounds != null:
		var low := Vector2(layout.bounds.min[0], layout.bounds.min[1])
		return Rect2(low, Vector2(layout.bounds.max[0], layout.bounds.max[1]) - low)
	var extent := Rect2()
	var seeded := false
	var points: Array = []
	for rect: Dictionary in layout.terrain + layout.brushes:
		points.append(rect.min)
		points.append(rect.max)
	for lane: Dictionary in layout.lanes:
		points.append_array(lane.waypoints)
	for point: Array in points:
		var at := Vector2(point[0], point[1])
		extent = extent.expand(at) if seeded else Rect2(at, Vector2.ZERO)
		seeded = true
	return extent


func _add_block(world: Node3D, rect: Dictionary, height: float, material: Material) -> void:
	var mesh := BoxMesh.new()
	var width: float = (rect.max[0] - rect.min[0]) * WORLD_SCALE
	var depth: float = (rect.max[1] - rect.min[1]) * WORLD_SCALE
	mesh.size = Vector3(width, height, depth)
	mesh.material = material
	var block := MeshInstance3D.new()
	block.mesh = mesh
	block.position = _world((rect.min[0] + rect.max[0]) / 2.0, (rect.min[1] + rect.max[1]) / 2.0) + Vector3(0, height / 2.0, 0)
	world.add_child(block)


func _add_contact_shadow(world: Node3D, at: Vector3) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.7, 1.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.55))
	gradient.set_color(1, Color(0, 0, 0, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var blob := MeshInstance3D.new()
	blob.mesh = mesh
	blob.position = at + Vector3(0, 0.02, 0)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(blob)


func _material(color: Color, variation: float) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.04
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, color.darkened(variation * 2.0))
	ramp.set_color(1, color.lightened(variation))
	texture.color_ramp = ramp
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.5, 0.5, 0.5)
	material.roughness = 1.0
	return material


func _world(x: float, y: float) -> Vector3:
	return Vector3(x * WORLD_SCALE, 0, -y * WORLD_SCALE)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started < SHOT_AFTER_MS:
		return false
	root.get_texture().get_image().save_png(out_path)
	print("SHOT ", out_path)
	quit(0)
	return true

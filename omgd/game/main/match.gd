# The 2.5D match view: everything shown comes from the presentation frame.
extends Node3D

const CORPSE_SECONDS := 1.5
## |sin(facing)| past which a walk reads as toward or away from the camera (about 50 degrees).
const VIEW_TURN_SIN := 0.77
## |sin(facing)| bounds of the diagonal walks: sin 22.5 and sin 67.5 degrees.
const DIAGONAL_SIN := Vector2(0.383, 0.924)
## |cos(facing)| below which a unit keeps the side it faces: walking straight up or down, the heading
## wobbles across vertical and the sprite would mirror every tick.
const FLIP_DEAD_COS := 0.2
## Frames land between backend ticks, so a walker would hold, then jump two ticks, and a camera
## following it judders the whole screen. Bodies chase their backend spot at this rate (per second);
## past SNAP_DISTANCE (a blink or a respawn) they jump there.
const SMOOTH_RATE := 18.0
const SNAP_DISTANCE := 2.0
## A prop hides what stands behind it up to this many times its height (camera pitch 19 over 15).
const COVER_DEPTH := 1.27
## Half the ground the default camera shows around its focus (x across, z toward the bottom edge).
const CAMERA_VIEW_INSET := Vector3(6.5, 0, 3.5)
const KIND_HERO := 1
# Two heroes' plates collide when their roots are this close (x, z); the upper one steps this much above.
const PLATE_CLEAR := Vector2(1.5, 0.9)
const PLATE_STEP := 0.55
## How each hero's attack reads at its hit frame; heroes not listed swing in melee.
const ATTACK_FX := {"saika_magoichi": "shot", "inahime": "arrow", "tamako": "arrow", "oichi": "bolt"}
# Health lost within this window shows as one number.
const DAMAGE_BATCH_MS := 250
const DAMAGE_SECONDS := 0.8
const COLOR_DAMAGE_DEALT := Color(1.0, 0.92, 0.55)
const COLOR_DAMAGE_TAKEN := Color(1.0, 0.4, 0.35)
const KIND_TOWER := 2
const KIND_CREEP := 3
const KIND_SUMMON := 4
const KIND_PROJECTILE := 5
const FLAG_CUE_ONLY := 1
const LOCOMOTION_WALK := 2
const RELATION_HOSTILE := 2
const WALL_HEIGHT := 1.0
const CAMERA_OFFSET := Vector3(0, 19.0, 15.0)
const CAMERA_PAN_SPEED := 30.0
const CAMERA_EDGE_PX := 12.0
## Ground units per screen pixel of a middle-button drag at zoom 1 (fov 30 at 24 units away, 720 px tall).
const CAMERA_DRAG_SCALE := 0.018
const CLICK_MARK_SECONDS := 0.35
const COLOR_CLICK_MOVE := Color(0.35, 1.0, 0.45)
const COLOR_CLICK_ATTACK := Color(1.0, 0.3, 0.25)
const ZOOM_RANGE := Vector2(0.5, 2.5)
const PICK_RADIUS := 1.0
const ABILITY_KEYS := {KEY_Q: 0, KEY_W: 1, KEY_E: 2, KEY_R: 3, KEY_D: 4, KEY_F: 5}
const ORDER_MOVE := 0
const ORDER_ATTACK_MOVE := 1
const ORDER_ATTACK := 2
const ORDER_STOP := 3
const ORDER_HOLD := 4
const ORDER_RECALL := 5
const COLOR_OWN := Color(0.3, 0.9, 0.35)
const COLOR_ALLY := Color(0.3, 0.6, 1.0)
const COLOR_ENEMY := Color(0.95, 0.28, 0.2)
const COLOR_NEUTRAL := Color(0.9, 0.78, 0.35)

var session := OmSession.new()
var player_id := 1
var team_id := 1
var map_id := ""
var units := {}
var world_built := false
var result_path := ""
var ended := false
var started_ms := 0
var finish_timeout_ms := 0
var last_state := -2
var stats := {"max_units": 0, "frames": 0, "last_log_ms": 0, "orders": 0, "rejected": 0, "casts": 0, "cast_shown": 0, "deaths": 0, "walks": {}, "attack_fx": {}}
var seen_content := {}
var camera_focus := Vector3(4, 0, -4)
var camera_follow := true
var camera_zoom := 1.0
var edge_pan := true
var focus_low := Vector3.ZERO
var focus_high := Vector3.ZERO
var camera_drag := false
# Holding Space looks at the hero; letting go returns to the view from before.
var space_view := Vector3.ZERO
var space_follow := false
var space_held := false
# Ctrl pressed and let go with nothing else in between toggles the cursor lock.
var ctrl_tap := false
var cursor_locked := false
var armed_attack_move := false
var armed_ability := -1
var unit_rows := PackedFloat32Array()
var unit_ids := PackedInt64Array()
var _shadow_mesh: PlaneMesh
var _projectile_texture: GradientTexture2D

@onready var camera := Camera3D.new()
@onready var hud := MatchHud.new()
@onready var fog := FogLayer.new()


func _ready() -> void:
	var address := ""
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		match pair[0]:
			"--om-presentation": address = pair[1]
			"--om-player": player_id = int(pair[1])
			"--om-team": team_id = int(pair[1])
			"--om-map": map_id = pair[1]
			"--om-result": result_path = pair[1]
			"--om-finish-timeout": finish_timeout_ms = int(pair[1]) * 1000
			"--om-focus":
				var at := pair[1].split(",")
				camera_focus = WorldXform.to_3d(float(at[0]), float(at[1]))
				camera_follow = false
				edge_pan = false
			"--om-input-smoke":
				var smoke: Node = load("res://tests/input_smoke.gd").new()
				smoke.view = self
				edge_pan = false
				add_child(smoke)
	if edge_pan:
		_set_cursor_locked(true)
	started_ms = Time.get_ticks_msec()
	_build_stage()
	if address.is_empty():
		hud.notice.text = "缺少 --om-presentation"
		return
	if not session.start(address, player_id, team_id):
		printerr("cannot start session: ", session.last_error())
		get_tree().quit(2)
		return
	print("om_godot abi=", OmSession.abi_version(), " address=", address, " player=", player_id, " team=", team_id, " map=", map_id)


func _build_stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.03, 0.04, 0.06)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.62, 0.68, 0.82)
	settings.ambient_light_energy = 0.5
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.ssao_enabled = true
	settings.ssao_intensity = 2.0
	var holder := WorldEnvironment.new()
	holder.environment = settings
	add_child(holder)
	camera.fov = 30.0
	camera.far = 500.0
	camera.rotation = Basis.looking_at(-CAMERA_OFFSET, Vector3.UP).get_euler()
	add_child(camera)
	camera.make_current()
	add_child(fog)
	add_child(hud)
	hud.minimap.team_id = team_id
	hud.minimap_clicked.connect(_on_minimap_clicked)


func _build_world() -> void:
	var terrain := session.terrain_rects()
	var routes := session.lane_routes()
	if terrain.is_empty() and routes.is_empty():
		return
	world_built = true
	var extent := Rect2()
	var seeded := false
	for route: PackedVector2Array in routes:
		for point in route:
			extent = extent.expand(point) if seeded else Rect2(point, Vector2.ZERO)
			seeded = true
	for i in range(0, terrain.size(), 4):
		var low := Vector2(terrain[i], terrain[i + 1])
		var high := Vector2(terrain[i + 2], terrain[i + 3])
		extent = extent.expand(low).expand(high) if seeded else Rect2(low, high - low)
		seeded = true
	var wall := _wall_material()
	for i in range(0, terrain.size(), 4):
		var low := Vector2(terrain[i], terrain[i + 1])
		var high := Vector2(terrain[i + 2], terrain[i + 3])
		var box := _add_box(WorldXform.to_3d((low.x + high.x) / 2.0, (low.y + high.y) / 2.0, WALL_HEIGHT / 2.0),
			Vector3((high.x - low.x) * WorldXform.SCALE, WALL_HEIGHT, (high.y - low.y) * WorldXform.SCALE))
		box.material_override = wall
	var center := extent.get_center()
	focus_low = WorldXform.to_3d(extent.position.x, extent.end.y)
	focus_high = WorldXform.to_3d(extent.end.x, extent.position.y)
	_add_ground(center, extent.size, routes)
	hud.minimap.set_map(extent, terrain, routes)
	print("world built: terrain=", terrain.size() / 4, " routes=", routes.size(), " extent=", extent)


func _wall_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	if ResourceLoader.exists("res://art/maps/stone.jpg"):
		material.albedo_texture = load("res://art/maps/stone.jpg")
		material.uv1_triplanar = true
		material.uv1_scale = Vector3(0.45, 0.45, 0.45)
	else:
		material.albedo_color = Color(0.47, 0.45, 0.41)
	return material


func _add_ground(center: Vector2, size: Vector2, routes: Array) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size * WorldXform.SCALE
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	var path := "res://art/maps/%s.jpg" % map_id
	var painted := ResourceLoader.exists(path)
	if painted:
		material.albedo_texture = load(path)
	else:
		material.albedo_color = Color(0.3, 0.42, 0.24)
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	ground.position = WorldXform.to_3d(center.x, center.y)
	add_child(ground)
	# Beyond the map the land just continues, so a corner base never shows empty space.
	var skirt := _add_box(WorldXform.to_3d(center.x, center.y, -0.2),
		Vector3(size.x * WorldXform.SCALE + 120.0, 0.2, size.y * WorldXform.SCALE + 120.0), Color(0.12, 0.2, 0.1))
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if painted:
		var mirrored := ShaderMaterial.new()
		mirrored.shader = load("res://world/skirt.gdshader")
		mirrored.set_shader_parameter("ground", material.albedo_texture)
		# PlaneMesh uv 0 is its -x, -z corner.
		var corner := ground.position - Vector3(mesh.size.x, 0, mesh.size.y) / 2.0
		mirrored.set_shader_parameter("map_rect", Vector4(corner.x, corner.z, mesh.size.x, mesh.size.y))
		skirt.material_override = mirrored
	if not painted:
		for route: PackedVector2Array in routes:
			for i in range(route.size() - 1):
				_add_road(route[i], route[i + 1])


func _add_box(at: Vector3, size: Vector3, color := Color.WHITE) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material = material
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.position = at
	add_child(box)
	return box


func _add_road(from: Vector2, to: Vector2) -> void:
	var a := WorldXform.to_3d(from.x, from.y, 0.01)
	var b := WorldXform.to_3d(to.x, to.y, 0.01)
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var road := _add_box((a + b) / 2.0, Vector3(2.4, 0.02, length), Color(0.55, 0.47, 0.33))
	road.look_at_from_position(road.position, b, Vector3.UP)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	var state := session.session_state()
	if state != last_state:
		print("session_state=", state)
		last_state = state
		if state == 3 or state == 4:
			_finish("session_state_%d" % state)
	if session.poll_frame():
		stats.frames += 1
		if not world_built:
			_build_world()
		_sync_units()
		fog.update_from(session.fog_cells(), session.fog_info())
		hud.minimap.set_fog(session.fog_cells(), session.fog_info())
	_smooth_units(delta)
	_update_camera(delta)
	_update_hud()
	var now := Time.get_ticks_msec()
	if now - stats.last_log_ms > 10000:
		stats.last_log_ms = now
		print("t=", snappedf(session.elapsed_seconds(), 0.1), " tick=", session.tick(), " phase=", session.match_phase(),
			" units=", units.size(), " frames=", stats.frames, " fps=", Engine.get_frames_per_second())
	if session.match_phase() == 2 and not result_path.is_empty():
		_finish("finished")
	if finish_timeout_ms > 0 and now - started_ms > finish_timeout_ms:
		_finish("timeout")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			ctrl_tap = false
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			camera_drag = event.pressed
		elif event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP: camera_zoom = clampf(camera_zoom * 0.9, ZOOM_RANGE.x, ZOOM_RANGE.y)
				MOUSE_BUTTON_WHEEL_DOWN: camera_zoom = clampf(camera_zoom * 1.1, ZOOM_RANGE.x, ZOOM_RANGE.y)
				MOUSE_BUTTON_RIGHT: _on_right_click(event.position, event.shift_pressed)
				MOUSE_BUTTON_LEFT: _on_left_click(event.position, event.shift_pressed)
	elif event is InputEventMouseMotion and camera_drag:
		camera_follow = false
		camera_focus -= Vector3(event.relative.x, 0, event.relative.y) * CAMERA_DRAG_SCALE * camera_zoom
	elif event is InputEventKey and not event.echo:
		if event.pressed:
			_on_key(event)
		else:
			_on_key_released(event)


func _on_key(event: InputEventKey) -> void:
	ctrl_tap = event.keycode == KEY_CTRL
	if ABILITY_KEYS.has(event.keycode):
		var slot: int = ABILITY_KEYS[event.keycode]
		if event.ctrl_pressed:
			_count_order(session.submit_upgrade(slot))
		else:
			_arm_ability(slot)
		return
	match event.keycode:
		KEY_A:
			armed_ability = -1
			if event.shift_pressed:
				# Shift+A goes at once, toward the cursor.
				armed_attack_move = false
				_attack_move_at(get_viewport().get_mouse_position(), false)
			else:
				armed_attack_move = true
		KEY_S: _count_order(session.submit_order(ORDER_STOP, 0, 0.0, 0.0, false))
		KEY_H: _count_order(session.submit_order(ORDER_HOLD, 0, 0.0, 0.0, false))
		KEY_B: _count_order(session.submit_order(ORDER_RECALL, 0, 0.0, 0.0, false))
		KEY_Y: camera_follow = not camera_follow
		KEY_F1: _focus_hero()
		KEY_F9: edge_pan = not edge_pan
		KEY_SPACE:
			space_held = true
			space_view = camera_focus
			space_follow = camera_follow
			camera_follow = true
		KEY_ESCAPE:
			armed_attack_move = false
			armed_ability = -1


func _on_key_released(event: InputEventKey) -> void:
	match event.keycode:
		KEY_SPACE:
			if space_held:
				space_held = false
				camera_follow = space_follow
				if not space_follow:
					camera_focus = space_view
		KEY_CTRL:
			if ctrl_tap:
				_set_cursor_locked(not cursor_locked)
			ctrl_tap = false


func _set_cursor_locked(locked: bool) -> void:
	cursor_locked = locked
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED if locked else Input.MOUSE_MODE_VISIBLE


func _focus_hero() -> void:
	var hero := session.owner_hero()
	if hero != 0 and units.has(hero):
		camera_focus = units[hero].root.position


func _arm_ability(slot: int) -> void:
	var rows := session.ability_rows()
	if slot >= rows.size() or int(rows[slot].catalog_id) == 0:
		return
	armed_attack_move = false
	if rows[slot].target_type == "none":
		_count_order(session.submit_cast(slot, "none", 0, 0.0, 0.0))
		armed_ability = -1
	else:
		armed_ability = slot


func _on_right_click(at: Vector2, queued: bool) -> void:
	armed_attack_move = false
	armed_ability = -1
	var ground := _ground_point(at)
	var target := _pick_unit(ground, true)
	if target != 0:
		_count_order(session.submit_order(ORDER_ATTACK, target, 0.0, 0.0, queued))
		_mark_click(units[target].root.position if units.has(target) else ground, COLOR_CLICK_ATTACK)
	else:
		var world := _to_backend(ground)
		_count_order(session.submit_order(ORDER_MOVE, 0, world.x, world.y, queued))
		_mark_click(ground, COLOR_CLICK_MOVE)


## Attack-move to a point, or straight at the enemy under the cursor.
func _attack_move_at(at: Vector2, queued: bool) -> void:
	var ground := _ground_point(at)
	var target := _pick_unit(ground, true)
	if target != 0:
		_count_order(session.submit_order(ORDER_ATTACK, target, 0.0, 0.0, queued))
		_mark_click(units[target].root.position if units.has(target) else ground, COLOR_CLICK_ATTACK)
	else:
		var world := _to_backend(ground)
		_count_order(session.submit_order(ORDER_ATTACK_MOVE, 0, world.x, world.y, queued))
		_mark_click(ground, COLOR_CLICK_ATTACK)


## A ring that shrinks into the clicked spot, so every order shows where it went.
func _mark_click(at: Vector3, color: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.42
	mesh.outer_radius = 0.5
	mesh.rings = 32
	mesh.ring_segments = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	mesh.material = material
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(at.x, 0.05, at.z)
	ring.scale = Vector3(1.0, 0.05, 1.0)
	add_child(ring)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(0.3, 0.05, 0.3), CLICK_MARK_SECONDS)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, CLICK_MARK_SECONDS).set_ease(Tween.EASE_IN)
	tween.tween_callback(ring.queue_free)


func _on_left_click(at: Vector2, queued: bool) -> void:
	var ground := _ground_point(at)
	var world := _to_backend(ground)
	if armed_attack_move:
		armed_attack_move = false
		_attack_move_at(at, queued)
	elif armed_ability >= 0:
		var rows := session.ability_rows()
		var slot := armed_ability
		armed_ability = -1
		var kind: String = rows[slot].target_type if slot < rows.size() else "point"
		if kind == "unit":
			var target := _pick_unit(ground, false)
			if target != 0:
				_count_order(session.submit_cast(slot, "unit", target, 0.0, 0.0))
		else:
			_count_order(session.submit_cast(slot, "point", 0, world.x, world.y))


func _on_minimap_clicked(world: Vector2) -> void:
	camera_follow = false
	camera_focus = WorldXform.to_3d(world.x, world.y)


func _count_order(accepted: bool) -> void:
	stats.orders += 1
	if not accepted:
		stats.rejected += 1
		print("order refused locally: ", session.last_error())


# Backend facts only: a remembered ghost is not in this list, so it can never be picked.
func _pick_unit(ground: Vector3, hostile_only: bool) -> int:
	var best := 0
	var best_distance := PICK_RADIUS
	var stride := OmSession.UNIT_STRIDE
	for i in unit_ids.size():
		var base := i * stride
		var kind := int(unit_rows[base + 5])
		if kind == KIND_PROJECTILE or int(unit_rows[base + 9]) & FLAG_CUE_ONLY:
			continue
		if hostile_only and not int(unit_rows[base + 7]) & RELATION_HOSTILE:
			continue
		var distance := WorldXform.to_3d(unit_rows[base], unit_rows[base + 1]).distance_to(ground)
		if distance < best_distance:
			best_distance = distance
			best = unit_ids[i]
	return best


func _ground_point(at: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(at)
	var direction := camera.project_ray_normal(at)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	return hit if hit != null else camera_focus


func _to_backend(point: Vector3) -> Vector2:
	return Vector2(point.x / WorldXform.SCALE, -point.z / WorldXform.SCALE)


func _sync_units() -> void:
	var ids := session.unit_ids()
	var rows := session.unit_rows()
	unit_ids = ids
	unit_rows = rows
	var stride := OmSession.UNIT_STRIDE
	var seen := {}
	var dots := PackedFloat32Array()
	var owner := session.owner_hero()
	for i in ids.size():
		var base := i * stride
		if int(rows[base + 9]) & FLAG_CUE_ONLY:
			continue
		var id: int = ids[i]
		seen[id] = true
		if not units.has(id):
			var content := String(session.content_id(int(rows[base + 13]), int(rows[base + 8])))
			seen_content[content] = int(rows[base + 5])
			units[id] = _spawn_unit(id, int(rows[base + 5]), int(rows[base + 6]), content, id == owner)
		_update_unit(units[id], rows, base)
		var kind := int(rows[base + 5])
		if kind != KIND_PROJECTILE:
			dots.append(rows[base])
			dots.append(rows[base + 1])
			dots.append(rows[base + 6])
			dots.append(3.5 if kind == KIND_HERO else (3.0 if kind == KIND_TOWER else 1.5))
	for id: int in units.keys():
		if not seen.has(id):
			var gone: Dictionary = units[id]
			units.erase(id)
			# A unit that died just before leaving the frame finishes falling; one out of sight just goes.
			if gone.get("dying", false):
				get_tree().create_timer(CORPSE_SECONDS).timeout.connect(gone.root.queue_free)
			else:
				gone.root.queue_free()
	for id: int in session.take_casts():
		stats.casts += 1
		if units.has(id) and units[id].sprite != null and not units[id].get("dying", false):
			stats.cast_shown += 1
			units[id].slot = "cast"
			units[id].sprite.play_slot("cast")
			if units[id].kind == KIND_HERO:
				AttackFx.cast_ring(self, units[id].root.position, Color(0.55, 0.8, 1.0))
	stats.max_units = maxi(stats.max_units, units.size())
	_stack_plates()
	_mark_occluded()
	hud.minimap.dots = dots
	hud.minimap.view_center = _to_backend(camera_focus)
	hud.minimap.queue_redraw()


## A number that rises and fades above a unit that just lost health.
func _pop_damage(unit: Dictionary, amount: int) -> void:
	var label := Label3D.new()
	label.text = str(amount)
	label.font_size = 44 if unit.kind == KIND_HERO else 32
	label.pixel_size = 0.006
	label.outline_size = 10
	label.modulate = COLOR_DAMAGE_TAKEN if unit.friendly else COLOR_DAMAGE_DEALT
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 114
	label.outline_render_priority = 113
	var top := 1.7 if unit.kind == KIND_HERO else 1.0
	label.position = unit.root.position + Vector3(randf_range(-0.3, 0.3), top, 0)
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y + 0.7, DAMAGE_SECONDS)
	tween.parallel().tween_property(label, "modulate:a", 0.0, DAMAGE_SECONDS).set_ease(Tween.EASE_IN)
	tween.tween_callback(label.queue_free)


## The attack's hit frame of a hero: see AttackFx.
func _on_impact(unit: Dictionary, style: String) -> void:
	if unit.slot != "attack":
		return
	stats.attack_fx[style] = stats.attack_fx.get(style, 0) + 1
	AttackFx.play(self, style, unit.root.position, unit.get("facing", 0.0))


## Lifts the name plates of heroes standing close together so the names stay readable.
func _stack_plates() -> void:
	var heroes: Array = []
	for unit: Dictionary in units.values():
		if unit.has("plate") and not unit.dying:
			heroes.append(unit)
	# Nearer the camera (larger z) keeps its plate low; the ones behind it step up.
	heroes.sort_custom(func(a, b): return a.root.position.z > b.root.position.z)
	var placed: Array = []
	for unit: Dictionary in heroes:
		var lift := 0.0
		for other: Dictionary in placed:
			var gap: Vector3 = unit.root.position - other.root.position
			if absf(gap.x) < PLATE_CLEAR.x and absf(gap.z) < PLATE_CLEAR.y:
				lift = maxf(lift, other.plate.position.y + gap.z * 0.5 + PLATE_STEP)
		unit.plate.position.y = lift
		placed.append(unit)


## Turns on the x-ray copy of each hero standing behind a tower or building.
func _mark_occluded() -> void:
	var props: Array = []
	for unit: Dictionary in units.values():
		if unit.has("cover"):
			props.append(unit)
	for unit: Dictionary in units.values():
		if not unit.get("xray", false):
			continue
		var at: Vector3 = unit.root.position
		var hidden := false
		for prop: Dictionary in props:
			var gap: Vector3 = prop.root.position - at
			var cover: Vector2 = prop.cover
			# Nearer the camera is larger z.
			if absf(gap.x) < cover.x and gap.z > 0.0 and gap.z < cover.y:
				hidden = true
				break
		if hidden != unit.get("occluded", false):
			unit.occluded = hidden
			unit.sprite.set_occluded(hidden)


func _relation_color(team: int, own: bool) -> Color:
	if own:
		return COLOR_OWN
	if team == team_id:
		return COLOR_ALLY
	return COLOR_ENEMY if team == 1 or team == 2 else COLOR_NEUTRAL


func _spawn_unit(_id: int, kind: int, team: int, content: String, own: bool) -> Dictionary:
	var color := _relation_color(team, own)
	var root := Node3D.new()
	add_child(root)
	var unit := {"root": root, "kind": kind, "sprite": null, "bar": null, "marker": null, "slot": "", "dying": false,
		"friendly": team == team_id}
	var sprite_id := UnitArt.unit_sprite(kind, content)
	if sprite_id != "":
		var sprite := UnitSprite3D.new()
		root.add_child(sprite)
		if sprite.setup(sprite_id, UnitArt.unit_height(kind, sprite_id)):
			sprite.animation_finished.connect(_on_action_finished.bind(unit))
			if kind == KIND_HERO:
				sprite.impact.connect(_on_impact.bind(unit, ATTACK_FX.get(sprite_id, "slash")))
			sprite.play_slot("idle")
			if kind == KIND_HERO:
				sprite.enable_xray()
				unit.xray = true
				if own:
					hud.set_portrait(sprite_id)
			unit.sprite = sprite
			_add_contact_shadow(root, 1.0 if kind == KIND_HERO else 0.6)
	match kind:
		KIND_HERO:
			unit.marker = _add_marker(root, 0.55, color)
			var plate := Node3D.new()
			root.add_child(plate)
			unit.plate = plate
			unit.bar = _add_bar(plate, color, 2.1, 1.4)
			var name := UnitArt.display_name(content)
			if name != "":
				_add_name(plate, name, color, 2.32)
		KIND_TOWER:
			var prop := UnitArt.prop_name(content)
			var height: float = UnitArt.PROP_HEIGHTS[prop]
			var texture := UnitArt.prop_texture(prop)
			if texture != null:
				_add_prop(root, texture, height)
				# The drawn subject is about 60% of the padded frame's width.
				var half_width := texture.get_width() * height / (texture.get_height() * 0.6) * 0.3
				unit.cover = Vector2(half_width, height * COVER_DEPTH)
			else:
				_add_part(root, Vector3(0.9, 2.3, 0.9), color.lerp(Color(0.5, 0.5, 0.5), 0.55))
			unit.marker = _add_marker(root, height * 0.2, color)
			unit.bar = _add_bar(root, color, height + 0.3, 1.6)
		KIND_PROJECTILE:
			_add_projectile(root)
		KIND_CREEP, KIND_SUMMON:
			if unit.sprite == null:
				_add_part(root, Vector3(0.4, 0.7, 0.4), color)
			unit.marker = _add_marker(root, 0.3, color)
			unit.bar = _add_bar(root, color, 1.25, 0.8)
		_:
			_add_part(root, Vector3(0.5, 0.5, 0.5), color)
	return unit


func _add_prop(root: Node3D, texture: Texture2D, height: float) -> void:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var image_size := texture.get_size()
	# Props are padded to the class framing: subject 614 of 1024 tall, bottom edge at 819.
	sprite.pixel_size = height / (image_size.y * 0.6)
	sprite.offset = Vector2(-image_size.x / 2.0, -image_size.y * (1.0 - 0.8))
	# The art shows the footprint from above: its centre sits above the lowest pixel.
	sprite.position = Vector3(0, 0, height * 0.16)
	root.add_child(sprite)


## A glowing mote for projectiles until they get their own art.
func _add_projectile(root: Node3D) -> void:
	if _projectile_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 0.9, 1), Color(1.0, 0.8, 0.35, 0.55), Color(1.0, 0.45, 0.1, 0)])
		_projectile_texture = GradientTexture2D.new()
		_projectile_texture.gradient = gradient
		_projectile_texture.fill = GradientTexture2D.FILL_RADIAL
		_projectile_texture.fill_from = Vector2(0.5, 0.5)
		_projectile_texture.fill_to = Vector2(1.0, 0.5)
	var mote := Sprite3D.new()
	mote.texture = _projectile_texture
	mote.pixel_size = 0.45 / 64.0
	mote.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mote.shaded = false
	mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mote.position.y = 1.0
	root.add_child(mote)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _projectile_texture
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote.material_override = mat


## A soft dark ellipse under a billboard so it reads as standing on the ground.
func _add_contact_shadow(root: Node3D, size: float) -> void:
	if _shadow_mesh == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0, 0, 0, 0.72))
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
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_shadow_mesh = PlaneMesh.new()
		_shadow_mesh.size = Vector2(1.3, 0.8)
		_shadow_mesh.material = material
	var blob := MeshInstance3D.new()
	blob.mesh = _shadow_mesh
	blob.position.y = 0.02
	blob.scale = Vector3(size, 1.0, size)
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(blob)


func _add_part(root: Node3D, size: Vector3, color: Color, lift := -1.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position.y = lift if lift >= 0.0 else size.y / 2.0
	root.add_child(part)


func _add_marker(root: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.05
	mesh.outer_radius = radius
	mesh.rings = 32
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.position.y = 0.03
	ring.scale.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	return ring


func _add_name(root: Node3D, text: String, color: Color, height: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 10
	label.modulate = color.lerp(Color.WHITE, 0.55)
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 112
	label.outline_render_priority = 111
	label.position = Vector3(0, height, 0)
	root.add_child(label)


func _add_bar(root: Node3D, color: Color, height: float, width: float) -> MeshInstance3D:
	_add_bar_quad(root, Color(0.03, 0.03, 0.03), height, width, 0.14, 0)
	return _add_bar_quad(root, color, height, width, 0.1, 1)


func _add_bar_quad(root: Node3D, color: Color, height: float, width: float, thickness: float, priority: int) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(width, thickness)
	mesh.center_offset = Vector3(width / 2.0, 0, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 110 + priority
	mesh.material = material
	var bar := MeshInstance3D.new()
	bar.mesh = mesh
	bar.position = Vector3(-width / 2.0, height, 0)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bar)
	return bar


func _update_unit(unit: Dictionary, rows: PackedFloat32Array, base: int) -> void:
	var spot := WorldXform.to_3d(rows[base], rows[base + 1])
	if not unit.has("spot") or unit.root.position.distance_to(spot) > SNAP_DISTANCE:
		unit.root.position = spot
	unit.spot = spot
	unit.facing = rows[base + 2]
	if unit.bar != null:
		var maximum := rows[base + 4]
		unit.bar.scale.x = clampf(rows[base + 3] / maximum, 0.001, 1.0) if maximum > 0.0 else 0.001
	if unit.sprite == null:
		return
	var sprite: UnitSprite3D = unit.sprite
	var dead := rows[base + 4] > 0.0 and rows[base + 3] <= 0.0
	if not dead and rows[base + 3] < unit.get("hp", rows[base + 3]):
		if unit.kind == KIND_HERO:
			sprite.flash_hit()
		unit.damage = unit.get("damage", 0.0) + unit.hp - rows[base + 3]
	unit.hp = rows[base + 3]
	var now := Time.get_ticks_msec()
	if unit.get("damage", 0.0) >= 1.0 and now - unit.get("damage_ms", 0) >= DAMAGE_BATCH_MS:
		_pop_damage(unit, roundi(unit.damage))
		unit.damage = 0.0
		unit.damage_ms = now
	if dead != unit.dying:
		unit.dying = dead
		if unit.bar != null:
			unit.bar.get_parent().get_child(unit.bar.get_index() - 1).visible = not dead
			unit.bar.visible = not dead
		if unit.marker != null:
			unit.marker.visible = not dead
		unit.slot = "death" if dead else ""
		if dead:
			stats.deaths += 1
			sprite.play_slot("death")
	if dead:
		return
	var turn := cos(rows[base + 2])
	if absf(turn) > FLIP_DEAD_COS:
		sprite.set_facing_right(turn > 0.0)
	var slot := "idle"
	if int(rows[base + 11]) != 0:
		slot = "attack"
	elif int(rows[base + 10]) == LOCOMOTION_WALK:
		# Eight headings: back, back diagonal, side, front diagonal, front (left ones mirrored).
		var heading := sin(rows[base + 2])
		if absf(heading) > DIAGONAL_SIN.y:
			slot = "move_back" if heading > 0.0 else "move_front"
		elif absf(heading) > DIAGONAL_SIN.x:
			slot = "move_back_side" if heading > 0.0 else "move_front_side"
		else:
			slot = "move"
		if not sprite.sprite_frames.has_animation(slot) and slot.ends_with("_side"):
			# Heroes without diagonal art keep the old four-way split.
			slot = "move_back" if heading > VIEW_TURN_SIN else ("move_front" if heading < -VIEW_TURN_SIN else "move")
		if not sprite.sprite_frames.has_animation(slot):
			slot = "move"
	if slot != unit.slot and not ((unit.slot == "attack" or unit.slot == "cast") and sprite.is_playing()):
		if slot.begins_with("move"):
			stats.walks[slot] = stats.walks.get(slot, 0) + 1
		unit.slot = slot
		sprite.play_slot(slot)


func _smooth_units(delta: float) -> void:
	var weight := 1.0 - exp(-SMOOTH_RATE * delta)
	for unit: Dictionary in units.values():
		if unit.has("spot"):
			unit.root.position = unit.root.position.lerp(unit.spot, weight)


func _on_action_finished(unit: Dictionary) -> void:
	unit.slot = ""


func _update_camera(delta: float) -> void:
	var pan := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	var viewport := get_viewport()
	var mouse := viewport.get_mouse_position()
	var size := viewport.get_visible_rect().size
	if edge_pan and DisplayServer.window_is_focused() and Rect2(Vector2.ZERO, size).has_point(mouse):
		if mouse.x < CAMERA_EDGE_PX: pan.x = -1.0
		elif mouse.x > size.x - CAMERA_EDGE_PX: pan.x = 1.0
		if mouse.y < CAMERA_EDGE_PX: pan.y = -1.0
		elif mouse.y > size.y - CAMERA_EDGE_PX: pan.y = 1.0
	if pan != Vector2.ZERO:
		camera_follow = false
		camera_focus += Vector3(pan.x, 0, pan.y) * CAMERA_PAN_SPEED * camera_zoom * delta
	var hero := session.owner_hero()
	if camera_follow and hero != 0 and units.has(hero):
		camera_focus = units[hero].root.position
	# Keep the view on the map: past its edge there is only fogged void.
	var inset := CAMERA_VIEW_INSET * camera_zoom
	var low := focus_low + inset
	var high := focus_high - inset
	camera_focus.x = clampf(camera_focus.x, low.x, high.x) if low.x < high.x else (focus_low.x + focus_high.x) / 2.0
	camera_focus.z = clampf(camera_focus.z, low.z, high.z) if low.z < high.z else (focus_low.z + focus_high.z) / 2.0
	camera.position = camera_focus + CAMERA_OFFSET * camera_zoom


func _update_hud() -> void:
	var armed := ""
	var aiming := armed_attack_move or armed_ability >= 0
	if aiming != (Input.get_current_cursor_shape() == Input.CURSOR_CROSS):
		Input.set_default_cursor_shape(Input.CURSOR_CROSS if aiming else Input.CURSOR_ARROW)
	if armed_attack_move:
		armed = "攻擊移動：左鍵選位置"
	elif armed_ability >= 0:
		var rows := session.ability_rows()
		var name: String = rows[armed_ability].name if armed_ability < rows.size() else ""
		armed = "施放 %s：左鍵選目標" % name
	var status := "tick %d   units %d   fps %d" % [session.tick(), units.size(), Engine.get_frames_per_second()]
	hud.refresh(session, armed, status, team_id)


func end_smoke(failures: int) -> void:
	_finish("finished" if failures == 0 else "smoke_failed")


func _finish(reason: String) -> void:
	if ended:
		return
	ended = true
	print("MATCH_END reason=", reason, " winner=", session.winner_team(), " elapsed=", session.elapsed_seconds(),
		" tick=", session.tick(), " max_units=", stats.max_units, " frames=", stats.frames,
		" casts=", stats.casts, " casts_shown=", stats.cast_shown, " deaths_shown=", stats.deaths)
	print("WALKS_SHOWN ", stats.walks)
	print("ATTACK_FX ", stats.attack_fx)
	print("CONTENT_SEEN ", seen_content)
	if not result_path.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(result_path)
	session.stop()
	get_tree().quit(0 if reason == "finished" else 3)

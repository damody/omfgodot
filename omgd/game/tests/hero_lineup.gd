# Every imported hero, one column per slot, under the match camera and light.
# godot --path omgd/game --script res://tests/hero_lineup.gd -- OUT.png [SECONDS] [HEIGHT]
extends SceneTree

const HEROES := ["murakami_yoshikiyo", "date_masamune", "honda_tadakatsu", "sanada_yukimura", "asai_nagamasa",
	"saika_magoichi", "inahime", "tamako", "oichi", "omatsu"]
const SLOTS := ["idle", "move", "move_front_side", "move_front", "move_back_side", "move_back", "attack", "cast", "death"]
const COLUMN := 2.3
const ROW := 2.4
const CAMERA_OFFSET := Vector3(0, 19, 15)

var out_path := ""
var shot_at := 3000
var started := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_path = args[0]
	if args.size() > 1:
		shot_at = int(float(args[1]) * 1000.0)
	var height := float(args[2]) if args.size() > 2 else 1.5
	started = Time.get_ticks_msec()
	root.size = Vector2i(1600, 1000)
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.5, 0.62, 0.72)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.62, 0.68, 0.82)
	settings.ambient_light_energy = 0.55
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var holder := WorldEnvironment.new()
	holder.environment = settings
	world.add_child(holder)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60, 60)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://art/maps/three_lane_training.jpg")
	material.uv1_scale = Vector3(0.6, 0.6, 0.6)
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	world.add_child(ground)

	var heroes := HEROES.filter(func(id: String) -> bool:
		return FileAccess.file_exists("res://art/units/%s/sprite.json" % id))
	for row in heroes.size():
		for column in SLOTS.size():
			var holder3d := Node3D.new()
			world.add_child(holder3d)
			var unit := UnitSprite3D.new()
			holder3d.add_child(unit)
			if not unit.setup(heroes[row], height):
				printerr("missing ", heroes[row])
				continue
			holder3d.position = Vector3((column - SLOTS.size() / 2.0 + 0.5) * COLUMN, 0, (row - heroes.size() / 2.0 + 0.5) * ROW)
			unit.play_slot(SLOTS[column])
			unit.animation_finished.connect(unit.play_slot.bind(SLOTS[column]))
	var camera := Camera3D.new()
	camera.fov = 30.0
	world.add_child(camera)
	var zoom := maxf(heroes.size() * ROW / 12.0, 0.8)
	camera.look_at_from_position(CAMERA_OFFSET * zoom, Vector3.ZERO, Vector3.UP)
	camera.make_current()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started < shot_at:
		return false
	root.get_texture().get_image().save_png(out_path)
	print("SHOT ", out_path)
	quit(0)
	return true

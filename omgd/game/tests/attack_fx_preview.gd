# One hero per attack style in its attack pose, each effect fired mid-shot, under the match camera and light.
# godot --path omgd/game --script res://tests/attack_fx_preview.gd -- OUT.png
extends SceneTree

const CASES := [["saika_magoichi", "shot"], ["inahime", "arrow"], ["oichi", "bolt"], ["murakami_yoshikiyo", "slash"]]
const FIRE_AT := 1500
## Frames between firing and the screenshot (a time delay can be swallowed by a shader compile).
const SHOT_FRAMES := 4

var out_path := ""
var started := 0
var world: Node3D
var fired := false
var frames_since := 0


func _initialize() -> void:
	out_path = OS.get_cmdline_user_args()[0]
	started = Time.get_ticks_msec()
	root.size = Vector2i(1200, 800)
	world = Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.5
	world.add_child(sun)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(40, 40)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://art/maps/three_lane_training.jpg")
	material.uv1_scale = Vector3(0.4, 0.4, 0.4)
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	world.add_child(ground)
	for row in CASES.size():
		var holder := Node3D.new()
		holder.position = Vector3(-3.5, 0, (row - 1.5) * 2.4)
		world.add_child(holder)
		var hero := UnitSprite3D.new()
		holder.add_child(hero)
		hero.setup(CASES[row][0], 1.8)
		hero.play_slot("attack")
	var camera := Camera3D.new()
	camera.fov = 30.0
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0, 19, 15) * 0.85, Vector3(-0.5, 0, 0), Vector3.UP)
	camera.make_current()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec() - started
	if not fired and now >= FIRE_AT:
		fired = true
		for row in CASES.size():
			AttackFx.play(world, CASES[row][1], Vector3(-3.5, 0, (row - 1.5) * 2.4), 0.0)
		AttackFx.cast_ring(world, Vector3(3.0, 0, 0), Color(0.55, 0.8, 1.0))
	if not fired:
		return false
	frames_since += 1
	if frames_since < SHOT_FRAMES:
		return false
	root.get_texture().get_image().save_png(out_path)
	print("SHOT ", out_path)
	quit(0)
	return true

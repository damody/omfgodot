# A hero with a few projectile motes beside it, under the match camera and light.
# godot --path omgd/game --script res://tests/projectile_preview.gd -- OUT.png
extends SceneTree

var out_path := ""
var started := 0


func _initialize() -> void:
	out_path = OS.get_cmdline_user_args()[0]
	started = Time.get_ticks_msec()
	root.size = Vector2i(800, 600)
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(30, 30)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://art/maps/three_lane_training.jpg")
	material.uv1_scale = Vector3(0.3, 0.3, 0.3)
	mesh.material = material
	var ground := MeshInstance3D.new()
	ground.mesh = mesh
	world.add_child(ground)
	var holder := Node3D.new()
	world.add_child(holder)
	var hero := UnitSprite3D.new()
	holder.add_child(hero)
	hero.setup("saika_magoichi", 1.8)
	hero.play_slot("idle")
	# match.gd only needs its own fields for this helper, so it runs without a session.
	var match_view: Node = load("res://main/match.gd").new()
	for step in 3:
		var mote := Node3D.new()
		mote.position = Vector3(1.2 + step * 1.1, 0, 0)
		world.add_child(mote)
		match_view._add_projectile(mote)
	match_view.free()
	var camera := Camera3D.new()
	camera.fov = 30.0
	world.add_child(camera)
	camera.look_at_from_position(Vector3(1.5, 9, 7), Vector3(1.5, 0.6, 0), Vector3.UP)
	camera.make_current()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started < 1600:
		return false
	root.get_texture().get_image().save_png(out_path)
	print("SHOT ", out_path)
	quit(0)
	return true

# Plays the owned hero through real input events and reports what the authority did with them.
# Enabled by --om-input-smoke; prints one INPUT_SMOKE line per check and a final INPUT_SMOKE_RESULT.
extends Node

var view: Node3D
var clock := 0.0
var step := 0
var start_position := Vector3.ZERO
var start_points := 0
var failures := 0
var focus_after_f1 := Vector3.ZERO


func _process(delta: float) -> void:
	clock += delta
	match step:
		0:
			var hud: Dictionary = view.session.hud_summary()
			if hud.get("has_hero", false) and view.units.has(view.session.owner_hero()) and clock > 3.0:
				start_position = _hero_position()
				start_points = int(hud.skill_points)
				var target := start_position + Vector3(4.0, 0.0, -4.0)
				_mouse(view.camera.unproject_position(target), MOUSE_BUTTON_RIGHT)
				_advance()
		1:
			if clock > 6.0:
				var moved := start_position.distance_to(_hero_position())
				_report("move", moved > 1.0, "moved %.2f units" % moved)
				_key(KEY_Q, true)
				_advance()
		2:
			if clock > 1.5:
				var points := int(view.session.hud_summary().skill_points)
				if start_points == 0:
					print("INPUT_SMOKE upgrade SKIP no skill point to spend, not verified")
				else:
					_report("upgrade", points < start_points, "skill points %d -> %d" % [start_points, points])
				_key(KEY_Q, false)
				_advance()
		3:
			if clock > 0.3:
				# Point and unit abilities wait for the left click; a no-target one has already gone.
				if view.armed_ability == 0:
					var row: Dictionary = view.session.ability_rows()[0]
					if row.target_type == "unit":
						_report("cast_skipped", true, "unit target ability needs a visible enemy")
					_mouse(view.camera.unproject_position(_hero_position() + Vector3(2.0, 0.0, -2.0)), MOUSE_BUTTON_LEFT)
				_advance()
		4:
			if clock > 2.0:
				var row: Dictionary = view.session.ability_rows()[0]
				_report("cast", float(row.cooldown) > 0.0 or row.target_type == "unit",
					"%s target=%s cooldown=%.1f" % [row.name, row.target_type, row.cooldown])
				_key(KEY_S, false)
				_advance()
		5:
			if clock > 1.0:
				# A then a left click on the ground: an attack-move there.
				_key(KEY_A, false)
				_advance()
		6:
			if clock > 0.2:
				_report("attack_move_arm", view.armed_attack_move, "A armed attack-move")
				start_position = _hero_position()
				_mouse(view.camera.unproject_position(start_position + Vector3(-4.0, 0.0, 4.0)), MOUSE_BUTTON_LEFT)
				_advance()
		7:
			if clock > 3.0:
				var moved := start_position.distance_to(_hero_position())
				_report("attack_move", moved > 1.0 and not view.armed_attack_move, "moved %.2f units" % moved)
				view.camera_follow = false
				view.camera_focus = _hero_position() + Vector3(8.0, 0.0, -6.0)
				_key(KEY_F1, false)
				_advance()
		8:
			if clock > 0.3:
				# F1 lands where following the hero would; near a map edge both stop at the same clamp.
				focus_after_f1 = view.camera_focus
				view.camera_follow = true
				_advance()
		9:
			if clock > 0.3:
				var gap: float = focus_after_f1.distance_to(view.camera_focus)
				_report("focus_hero", gap < 0.5, "F1 view %.2f units from the follow view" % gap)
				_advance()
		10:
			if clock > 0.5:
				print("INPUT_SMOKE_RESULT failures=", failures, " orders=", view.stats.orders, " refused=", view.stats.rejected)
				view.end_smoke(failures)
				set_process(false)


func _hero_position() -> Vector3:
	return view.units[view.session.owner_hero()].root.position


func _advance() -> void:
	step += 1
	clock = 0.0


func _report(check: String, passed: bool, detail: String) -> void:
	print("INPUT_SMOKE ", check, " ", "pass" if passed else "FAIL", " ", detail)
	if not passed:
		failures += 1


func _mouse(at: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)


func _key(code: Key, ctrl: bool) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		Input.parse_input_event(event)

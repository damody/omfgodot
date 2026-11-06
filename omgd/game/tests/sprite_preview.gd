# P0 S2: plays a generated unit on generated terrain and saves a screenshot.
# godot --path omgd/game --script res://tests/sprite_preview.gd -- OUT.png
extends SceneTree

const CONTENT_ID := "saika_magoichi"
const HEIGHT_SCALE := 0.5
const SHOT_AFTER_MS := 2500

var out_path := ""
var started := 0
var impacts := 0
var feet: Array[Vector2] = []


func _initialize() -> void:
	out_path = OS.get_cmdline_user_args()[0]
	started = Time.get_ticks_msec()
	root.size = Vector2i(1280, 720)
	var ground := Sprite2D.new()
	ground.texture = load("res://art/maps/three_lane_training.jpg")
	ground.centered = false
	ground.scale = Vector2(2.0, 2.0)
	ground.position = Vector2(-300, -500)
	root.add_child(ground)
	var cases := [["idle", true], ["move", true], ["attack", true], ["idle", false], ["move", false], ["attack", false]]
	for i in cases.size():
		var unit := UnitSprite.new()
		root.add_child(unit)
		if not unit.setup(CONTENT_ID, HEIGHT_SCALE):
			printerr("missing sprite")
			quit(2)
			return
		unit.position = Vector2(180 + (i % 3) * 400, 280 + (i / 3) * 280)
		unit.set_facing_right(cases[i][1])
		unit.play_slot(cases[i][0])
		unit.impact.connect(func() -> void: impacts += 1)
		unit.animation_finished.connect(unit.play_slot.bind(cases[i][0]))
		feet.append(unit.position)
		var mark := ColorRect.new()
		mark.color = Color.CYAN
		mark.size = Vector2(9, 3)
		mark.position = unit.position - Vector2(4, 1)
		root.add_child(mark)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started < SHOT_AFTER_MS:
		return false
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("SHOT ", out_path, " impacts=", impacts, " size=", image.get_size())
	quit(0 if impacts > 0 else 1)
	return true

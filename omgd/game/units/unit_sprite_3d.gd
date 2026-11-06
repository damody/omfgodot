# A unit body standing in the 3D world: the node origin is the stance midpoint on the ground.
class_name UnitSprite3D
extends AnimatedSprite3D

signal impact

const MOVE_BOB_RATE := 9.0
const MOVE_BOB_HEIGHT := 0.05
const LUNGE_SECONDS := 0.45
const LUNGE_DISTANCE := 0.3
const FALL_SECONDS := 0.7
const CROSSFADE_SECONDS := 0.15
const HIT_FLASH_SECONDS := 0.18
const HIT_TINT := 0.45

var _unit: Dictionary = {}
var _right := true
var _fired := false
var _xray: AnimatedSprite3D
var _procedural := ""
var _procedural_clock := 0.0
var _flash: Tween


## A faint copy drawn over everything, so a unit behind a building still reads.
func enable_xray() -> void:
	_xray = AnimatedSprite3D.new()
	_xray.sprite_frames = sprite_frames
	_xray.centered = false
	_xray.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_xray.pixel_size = pixel_size
	_xray.no_depth_test = true
	_xray.shaded = false
	_xray.modulate = Color(0.55, 0.75, 1.0, 0.28)
	_xray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_xray)


func setup(content_id: String, height_units: float) -> bool:
	_unit = SpriteLibrary.load_unit(content_id)
	if _unit.is_empty():
		return false
	sprite_frames = _unit.frames
	centered = false
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Soft cut-out edges with correct depth, and mipmaps: frames are drawn far below their source size.
	alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	shaded = true
	pixel_size = height_units / float(_unit.body_height_px)
	frame_changed.connect(_on_frame_changed)
	return true


func play_slot(slot: String) -> void:
	if _unit.is_empty():
		return
	if slot != "death" and animation != &"" and sprite_frames.has_animation(animation) 			and not sprite_frames.get_animation_loop(animation) and animation != StringName(slot):
		_fade_out_current()
	_fired = false
	_procedural = ""
	position = Vector3.ZERO
	modulate.a = 1.0
	if _xray != null:
		_xray.visible = slot != "death"
	if slot == "cast" and not sprite_frames.has_animation(slot):
		slot = "attack"
	# A walk toward or away from the camera falls back to the side walk.
	if slot.begins_with("move_") and not sprite_frames.has_animation(slot):
		slot = "move"
	if sprite_frames.has_animation(slot):
		play(slot)
	else:
		# No clip for this slot yet: move the idle body instead of freezing.
		_procedural = slot
		_procedural_clock = 0.0
		play(&"idle")
	_apply_offset()


## A short red tint when the backend reports lost health.
func flash_hit() -> void:
	if _flash != null and _flash.is_valid():
		_flash.kill()
	modulate = Color(1.0, HIT_TINT, HIT_TINT, modulate.a)
	_flash = create_tween()
	_flash.tween_property(self, "modulate:g", 1.0, HIT_FLASH_SECONDS)
	_flash.parallel().tween_property(self, "modulate:b", 1.0, HIT_FLASH_SECONDS)


## Leaves the last pose of a finished one-shot fading over the next clip, so the switch never pops.
func _fade_out_current() -> void:
	var ghost := Sprite3D.new()
	ghost.texture = sprite_frames.get_frame_texture(animation, frame)
	ghost.centered = false
	ghost.offset = offset
	ghost.flip_h = flip_h
	ghost.billboard = billboard
	ghost.pixel_size = pixel_size
	ghost.shaded = shaded
	ghost.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	ghost.texture_filter = texture_filter
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.position = position
	get_parent().add_child(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, CROSSFADE_SECONDS)
	tween.tween_callback(ghost.queue_free)


func _process(delta: float) -> void:
	if _procedural == "":
		return
	_procedural_clock += delta
	match _procedural:
		"move":
			position = Vector3(0, absf(sin(_procedural_clock * MOVE_BOB_RATE)) * MOVE_BOB_HEIGHT, 0)
		"attack":
			var progress := _procedural_clock / LUNGE_SECONDS
			if progress >= 1.0:
				position = Vector3.ZERO
				_procedural = ""
				animation_finished.emit()
				return
			if not _fired and progress >= 0.4:
				_fired = true
				impact.emit()
			position = Vector3((1.0 if _right else -1.0) * sin(progress * PI) * LUNGE_DISTANCE, 0, 0)
		"death":
			var progress := minf(_procedural_clock / FALL_SECONDS, 1.0)
			modulate.a = 1.0 - progress
			position = Vector3(0, -0.15 * progress, 0)


func set_facing_right(right: bool) -> void:
	_right = right
	flip_h = not right
	_apply_offset()


func _apply_offset() -> void:
	if animation == &"default" or not sprite_frames.has_animation(animation):
		return
	var size := sprite_frames.get_frame_texture(animation, 0).get_size()
	var anchor: Vector2 = _unit.anchors[animation]
	var x := anchor.x if _right else size.x - anchor.x
	offset = Vector2(-x, anchor.y - size.y)
	if _xray != null:
		_xray.offset = offset
		_xray.flip_h = flip_h
		_xray.animation = animation
		_xray.frame = frame


func _on_frame_changed() -> void:
	if _xray != null:
		_xray.animation = animation
		_xray.frame = frame
	if _fired:
		return
	for event: Dictionary in _unit.events.get(animation, []):
		if event.name == "hit" and frame >= int(event.frame):
			_fired = true
			impact.emit()
			return

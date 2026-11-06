# A unit body. The node origin is the feet anchor; facing mirrors around it with scale, because
# flip_h would mirror inside the frame and move the anchor.
class_name UnitSprite
extends AnimatedSprite2D

signal impact

var _unit: Dictionary = {}
var _fired := false
var display_scale := 1.0


func setup(content_id: String, height_scale := 1.0) -> bool:
	_unit = SpriteLibrary.load_unit(content_id)
	if _unit.is_empty():
		return false
	sprite_frames = _unit.frames
	centered = false
	display_scale = height_scale
	scale = Vector2(height_scale, height_scale)
	frame_changed.connect(_on_frame_changed)
	return true


func play_slot(slot: String) -> void:
	if _unit.is_empty() or not sprite_frames.has_animation(slot):
		return
	offset = -(_unit.anchors[slot] as Vector2)
	_fired = false
	play(slot)


func set_facing_right(right: bool) -> void:
	scale.x = display_scale if right else -display_scale


func _on_frame_changed() -> void:
	if _fired:
		return
	for event: Dictionary in _unit.events.get(animation, []):
		if event.name == "hit" and frame >= int(event.frame):
			_fired = true
			impact.emit()
			return

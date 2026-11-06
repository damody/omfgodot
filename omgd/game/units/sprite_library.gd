# Builds SpriteFrames from art/units/<content_id>/sprite.json, cached per content id.
class_name SpriteLibrary
extends RefCounted

const ROOT := "res://art/units/"

static var _cache: Dictionary = {}


## Returns {frames: SpriteFrames, anchors: {slot: Vector2}, events: {slot: Array}}, or {} if missing.
static func load_unit(content_id: String) -> Dictionary:
	if _cache.has(content_id):
		return _cache[content_id]
	var path := ROOT + content_id + "/sprite.json"
	if not FileAccess.file_exists(path):
		push_warning("no sprite for %s" % content_id)
		_cache[content_id] = {}
		return {}
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var anchors := {}
	var events := {}
	for slot: String in spec.animations:
		var anim: Dictionary = spec.animations[slot]
		frames.add_animation(slot)
		frames.set_animation_loop(slot, anim.loop)
		frames.set_animation_speed(slot, 1000.0)
		var cell := Vector2(anim.cell[0], anim.cell[1])
		anchors[slot] = Vector2(anim.anchor[0], anim.anchor[1])
		events[slot] = anim.events
		var durations: Array = anim.durations_ms
		for page: Dictionary in anim.pages:
			var atlas: Texture2D = load(ROOT + content_id + "/" + page.file)
			for i in int(page.count):
				var region := AtlasTexture.new()
				region.atlas = atlas
				region.filter_clip = true
				var column := i % int(page.columns)
				var row := i / int(page.columns)
				region.region = Rect2(Vector2(column, row) * cell, cell)
				frames.add_frame(slot, region, durations[int(page.first) + i])
	var unit := {"frames": frames, "anchors": anchors, "events": events,
		"body_height_px": spec.animations.idle.body_height_px}
	_cache[content_id] = unit
	return unit

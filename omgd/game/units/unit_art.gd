# Chooses the art of a unit from its catalog content id. Missing art falls back by kind, never to nothing.
class_name UnitArt
extends RefCounted

const KIND_HERO := 1
const KIND_TOWER := 2
const KIND_CREEP := 3
const KIND_SUMMON := 4
const PLACEHOLDER_HERO := "saika_magoichi"
const HEIGHTS := {"lane_melee": 1.0, "lane_caster": 1.0, "lane_siege": 1.0, "lane_cavalry": 1.5}
const PROP_HEIGHTS := {"tower": 2.5, "barracks": 1.5, "base": 3.0}


static func unit_sprite(kind: int, content_id: String) -> String:
	if FileAccess.file_exists("res://art/units/%s/sprite.json" % content_id):
		return content_id
	if kind == KIND_HERO:
		return PLACEHOLDER_HERO
	if kind != KIND_CREEP and kind != KIND_SUMMON:
		return ""
	var fallback := "lane_melee"
	for key: String in ["caster", "siege", "cavalry"]:
		if content_id.contains(key):
			fallback = "lane_" + key
	return fallback if FileAccess.file_exists("res://art/units/%s/sprite.json" % fallback) else ""


static func unit_height(kind: int, sprite_id: String) -> float:
	if kind == KIND_HERO:
		return 1.8
	return HEIGHTS.get(sprite_id, 1.0)


static var _names: Dictionary = {}


## The hero's display name from art/units/names.json, or "" when none is known.
static func display_name(content_id: String) -> String:
	if _names.is_empty() and FileAccess.file_exists("res://art/units/names.json"):
		_names = JSON.parse_string(FileAccess.get_file_as_string("res://art/units/names.json"))
	return _names.get(content_id, "")


static func prop_name(content_id: String) -> String:
	var id := content_id.to_lower()
	if id.contains("barrack") or id.contains("inhibitor"):
		return "barracks"
	if id.ends_with("_base") or id.contains("ancient") or id.contains("castle"):
		return "base"
	return "tower"


static func prop_texture(name: String) -> Texture2D:
	var path := "res://art/props/%s.png" % name
	return load(path) if ResourceLoader.exists(path) else null

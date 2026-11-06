## Hit-frame effects for hero attacks: a shot, arrow or bolt flies out along the facing, a melee swing flashes
## in front. The backend resolves ranged attacks without projectile entities, so these only suggest the hit.
class_name AttackFx

## How far a ranged attack's streak travels (about a hero's attack range).
const RANGED_REACH := 4.5
const CAST_RING_SECONDS := 0.6

static var _glow: GradientTexture2D


## Plays `style` ("shot", "arrow", "bolt" or "slash") for a unit standing at `origin` facing `facing` radians.
static func play(parent: Node3D, style: String, origin: Vector3, facing: float) -> void:
	var forward := Vector3(cos(facing), 0, -sin(facing))
	var start := origin + forward * 0.7 + Vector3(0, 1.1, 0)
	match style:
		"shot":
			_streak(parent, start, forward, Color(1.0, 0.92, 0.55), Vector3(1.4, 0.07, 0.07), 0.14)
			_flash(parent, start, Color(1.0, 0.75, 0.3), 1.0, 0.16)
		"arrow":
			_streak(parent, start, forward, Color(1.0, 0.95, 0.8), Vector3(1.0, 0.05, 0.05), 0.22)
		"bolt":
			_flash(parent, start, Color(1.0, 0.5, 0.85), 0.9, 0.28, forward * RANGED_REACH)
		_:
			_flash(parent, origin + forward * 0.8 + Vector3(0, 0.9, 0), Color(1.0, 0.95, 0.75), 1.5, 0.18)


## A ring of light that spreads out on the ground from a casting unit's feet.
static func cast_ring(parent: Node3D, origin: Vector3, color: Color) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.42
	mesh.outer_radius = 0.5
	mesh.rings = 32
	mesh.ring_segments = 4
	var material := _additive(color)
	mesh.material = material
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = origin + Vector3(0, 0.05, 0)
	ring.scale = Vector3(0.6, 0.05, 0.6)
	parent.add_child(ring)
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(2.4, 0.05, 2.4), CAST_RING_SECONDS).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, CAST_RING_SECONDS).set_ease(Tween.EASE_IN)
	tween.tween_callback(ring.queue_free)


## A thin glowing bar that travels RANGED_REACH along `forward` and fades.
static func _streak(parent: Node3D, start: Vector3, forward: Vector3, color: Color, size: Vector3, seconds: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := _additive(color)
	mesh.material = material
	var streak := MeshInstance3D.new()
	streak.mesh = mesh
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(streak)
	streak.look_at_from_position(start, start + forward, Vector3.UP)
	streak.rotate_object_local(Vector3.UP, PI / 2.0)
	var tween := streak.create_tween()
	tween.tween_property(streak, "position", start + forward * RANGED_REACH, seconds)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, seconds).set_ease(Tween.EASE_IN)
	tween.tween_callback(streak.queue_free)


## A quick bright burst that grows and fades, drifting by `travel` on the way.
static func _flash(parent: Node3D, at: Vector3, color: Color, size: float, seconds: float, travel := Vector3.ZERO) -> void:
	var material := _additive(color)
	material.albedo_texture = _glow_texture()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mote := Sprite3D.new()
	mote.texture = _glow_texture()
	mote.material_override = material
	mote.pixel_size = size / 64.0
	mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mote.position = at
	parent.add_child(mote)
	var tween := mote.create_tween()
	tween.tween_property(mote, "scale", Vector3.ONE * (1.0 if travel != Vector3.ZERO else 1.8), seconds)
	if travel != Vector3.ZERO:
		tween.parallel().tween_property(mote, "position", at + travel, seconds)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(mote.queue_free)


static func _additive(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return material


static func _glow_texture() -> GradientTexture2D:
	if _glow == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 0.9, 1), Color(1.0, 0.8, 0.35, 0.55), Color(1.0, 0.45, 0.1, 0)])
		_glow = GradientTexture2D.new()
		_glow.gradient = gradient
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
	return _glow

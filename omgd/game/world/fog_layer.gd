# Feeds the backend's team fog grid to the full-screen fog shader. No grid means fully dark, not open.
class_name FogLayer
extends MeshInstance3D

var _image: Image
var _texture: ImageTexture
var _material := ShaderMaterial.new()
var _sample_tick := -1


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	quad.flip_faces = true
	mesh = quad
	_material.shader = load("res://world/fog.gdshader")
	_material.render_priority = 100
	material_override = _material
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dark := Image.create(1, 1, false, Image.FORMAT_L8)
	_material.set_shader_parameter("fog_texture", ImageTexture.create_from_image(dark))


func update_from(cells: PackedByteArray, info: Dictionary) -> void:
	if info.is_empty():
		return
	var tick: int = info.sample_tick
	if tick == _sample_tick:
		return
	_sample_tick = tick
	var columns: int = info.columns
	var rows: int = info.rows
	if cells.size() != columns * rows or columns == 0:
		return
	var bytes := PackedByteArray()
	bytes.resize(cells.size())
	for i in cells.size():
		bytes[i] = cells[i] * 127
	var image := Image.create_from_data(columns, rows, false, Image.FORMAT_L8, bytes)
	if _texture == null or _image.get_size() != image.get_size():
		_texture = ImageTexture.create_from_image(image)
		_material.set_shader_parameter("fog_texture", _texture)
		var scale_units: float = WorldXform.SCALE
		_material.set_shader_parameter("fog_rect", Vector4(info.origin_x * scale_units, info.origin_y * scale_units,
			columns * info.cell_size * scale_units, rows * info.cell_size * scale_units))
	else:
		_texture.update(image)
	_image = image

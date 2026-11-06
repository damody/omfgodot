# Top-down map of public geometry, fog and disclosed units. Clicking reports a backend world point.
class_name MatchMinimap
extends Control

signal clicked(world: Vector2)

const BACK := Color(0.16, 0.24, 0.13)
const ROAD := Color(0.55, 0.47, 0.33)
const WALL := Color(0.42, 0.4, 0.37)
const VIEW := Color(1, 1, 1, 0.8)

var extent := Rect2()
var terrain := PackedFloat32Array()
var routes: Array[PackedVector2Array] = []
var dots := PackedFloat32Array()
var fog_texture: ImageTexture
var fog_rect := Rect2()
var view_center := Vector2.ZERO
var team_id := 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func set_map(map_extent: Rect2, map_terrain: PackedFloat32Array, map_routes: Array) -> void:
	extent = map_extent
	terrain = map_terrain
	routes.clear()
	for route: PackedVector2Array in map_routes:
		routes.append(route)
	queue_redraw()


func set_fog(cells: PackedByteArray, info: Dictionary) -> void:
	if info.is_empty() or int(info.columns) == 0 or cells.size() != int(info.columns) * int(info.rows):
		return
	var bytes := PackedByteArray()
	bytes.resize(cells.size() * 2)
	for i in cells.size():
		bytes[i * 2] = 0
		bytes[i * 2 + 1] = [230, 130, 0][cells[i]]
	var image := Image.create_from_data(info.columns, info.rows, false, Image.FORMAT_LA8, bytes)
	if fog_texture == null or fog_texture.get_size() != Vector2(image.get_size()):
		fog_texture = ImageTexture.create_from_image(image)
	else:
		fog_texture.update(image)
	fog_rect = Rect2(info.origin_x, info.origin_y, int(info.columns) * float(info.cell_size), int(info.rows) * float(info.cell_size))


func _to_panel(world: Vector2) -> Vector2:
	var scale_to := size / extent.size
	return Vector2((world.x - extent.position.x) * scale_to.x, size.y - (world.y - extent.position.y) * scale_to.y)


func _gui_input(event: InputEvent) -> void:
	var dragging: bool = event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT
	var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if (dragging or pressed) and extent.has_area():
		var at: Vector2 = event.position / size
		clicked.emit(Vector2(extent.position.x + at.x * extent.size.x, extent.position.y + (1.0 - at.y) * extent.size.y))
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	if not extent.has_area():
		return
	for route in routes:
		for i in range(route.size() - 1):
			draw_line(_to_panel(route[i]), _to_panel(route[i + 1]), ROAD, 5.0)
	for i in range(0, terrain.size(), 4):
		var a := _to_panel(Vector2(terrain[i], terrain[i + 1]))
		var b := _to_panel(Vector2(terrain[i + 2], terrain[i + 3]))
		draw_rect(Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs()), WALL)
	if fog_texture != null:
		var a := _to_panel(fog_rect.position)
		var b := _to_panel(fog_rect.end)
		# Grid row 0 is the lowest backend y, which is the bottom of this panel.
		draw_texture_rect(fog_texture, Rect2(a.x, a.y, b.x - a.x, b.y - a.y), false)
	for i in range(0, dots.size(), 4):
		var at := _to_panel(Vector2(dots[i], dots[i + 1]))
		var team := int(dots[i + 2])
		var radius := dots[i + 3]
		var color := Color(0.3, 0.65, 1.0) if team == team_id else Color(0.95, 0.3, 0.25)
		if team != 1 and team != 2:
			color = Color(0.85, 0.8, 0.4)
		draw_circle(at, radius, color)
	var center := _to_panel(view_center)
	var span := size / extent.size * 2500.0
	draw_rect(Rect2(center - span / 2.0, span), VIEW, false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.62, 0.5, 0.3), false, 2.0)

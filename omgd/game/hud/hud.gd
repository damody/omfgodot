# The match HUD: every number shown comes from the session; absent data shows as absent, never 0.
class_name MatchHud
extends CanvasLayer

signal minimap_clicked(world: Vector2)

const SLOT_KEYS := "QWERDF"
const SLOT_SIZE := 58
const ITEM_SIZE := 40
const MINIMAP_SIZE := 230
const PANEL := Color(0.09, 0.08, 0.07, 0.92)
const EDGE := Color(0.62, 0.5, 0.3)
const HP_COLOR := Color(0.28, 0.72, 0.3)
const MANA_COLOR := Color(0.25, 0.48, 0.95)

var ability_views: Array[Dictionary] = []
var item_views: Array[Dictionary] = []
var hp_bar: ProgressBar
var hp_text: Label
var mana_bar: ProgressBar
var mana_text: Label
var level_text: Label
var gold_text: Label
var clock_text: Label
var notice: Label
var hint: Label
var banner: Label
var minimap: MatchMinimap
var debug_text: Label
var top_panel: Control
var bottom_panel: Control
var portrait_panel: Control
var portrait: TextureRect


func _ready() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	top_panel = _panel(root, Vector2(150, 40))
	clock_text = _label(top_panel, 24, HORIZONTAL_ALIGNMENT_CENTER)
	clock_text.size = top_panel.size

	var bar := _panel(root, Vector2(SLOT_SIZE * 6 + 7 * 8 + 170, 128))
	bottom_panel = bar

	level_text = _label(bar, 20, HORIZONTAL_ALIGNMENT_LEFT)
	level_text.position = Vector2(12, 6)
	level_text.size = Vector2(160, 26)
	for slot in 6:
		ability_views.append(_ability_slot(bar, slot))
	hp_bar = _bar(bar, Vector2(10, 78), HP_COLOR)
	hp_text = _bar_label(hp_bar)
	mana_bar = _bar(bar, Vector2(10, 102), MANA_COLOR)
	mana_bar.size.y = 16
	mana_text = _bar_label(mana_bar)

	portrait_panel = _panel(root, Vector2(bar.size.y, bar.size.y))
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.position = Vector2(4, 4)
	portrait.size = portrait_panel.size - Vector2(8, 8)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_panel.add_child(portrait)
	portrait_panel.visible = false

	gold_text = _label(bar, 20, HORIZONTAL_ALIGNMENT_RIGHT)
	gold_text.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	gold_text.position = Vector2(bar.size.x - 138, 4)
	gold_text.size = Vector2(126, 26)
	for slot in 6:
		item_views.append(_item_slot(bar, slot))

	minimap = MatchMinimap.new()
	minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	minimap.clicked.connect(func(world: Vector2) -> void: minimap_clicked.emit(world))
	root.add_child(minimap)

	hint = _label(root, 18, HORIZONTAL_ALIGNMENT_CENTER)
	hint.size = Vector2(480, 26)
	notice = _label(root, 26, HORIZONTAL_ALIGNMENT_CENTER)
	notice.size = Vector2(520, 36)
	banner = _label(root, 54, HORIZONTAL_ALIGNMENT_CENTER)
	banner.size = Vector2(680, 90)
	debug_text = _label(root, 13, HORIZONTAL_ALIGNMENT_LEFT)
	debug_text.position = Vector2(8, 6)
	debug_text.size = Vector2(400, 20)
	debug_text.modulate = Color(1, 1, 1, 0.6)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	top_panel.position = Vector2((view.x - top_panel.size.x) / 2.0, 6)
	bottom_panel.position = Vector2((view.x - bottom_panel.size.x - MINIMAP_SIZE) / 2.0, view.y - bottom_panel.size.y - 8)
	minimap.position = view - minimap.size - Vector2(8, 8)
	portrait_panel.position = bottom_panel.position - Vector2(portrait_panel.size.x + 6, 0)
	hint.position = Vector2(bottom_panel.position.x + (bottom_panel.size.x - hint.size.x) / 2.0, bottom_panel.position.y - 32)
	notice.position = Vector2((view.x - notice.size.x) / 2.0, 58)
	banner.position = (view - banner.size) / 2.0


## The player's hero portrait; a hero without one keeps the panel hidden.
func set_portrait(sprite_id: String) -> void:
	var path := "res://art/units/%s/portrait.png" % sprite_id
	portrait_panel.visible = ResourceLoader.exists(path)
	if portrait_panel.visible:
		portrait.texture = load(path)


func refresh(session: OmSession, armed_text: String, status_text: String, team_id: int) -> void:
	var hud := session.hud_summary()
	debug_text.text = status_text
	var elapsed := int(session.elapsed_seconds())
	clock_text.text = "%02d:%02d" % [elapsed / 60, elapsed % 60]
	hint.text = armed_text
	var phase := session.match_phase()
	if phase == 2:
		var winner := session.winner_team()
		banner.text = "勝利" if winner == team_id else ("落敗" if winner != 0 else "平手")
	if hud.is_empty():
		return
	var has_hero: bool = hud.has_hero
	level_text.text = "Lv %d%s" % [hud.level, ("   技能點 %d" % hud.skill_points) if int(hud.skill_points) > 0 else ""]
	_set_bar(hp_bar, hp_text, hud.hp, hud.max_hp, has_hero)
	var mana_known: bool = hud.mana_supported and has_hero
	mana_bar.visible = hud.mana_supported
	_set_bar(mana_bar, mana_text, hud.mana, hud.max_mana, mana_known)
	gold_text.text = "%d 金" % hud.gold if hud.has("gold") else "—"
	if float(hud.respawn) > 0.0:
		notice.text = "%d 秒後復活" % ceili(hud.respawn)
	elif float(hud.recall) > 0.0:
		notice.text = "回城 %.1f" % hud.recall
	else:
		notice.text = ""
	var rows := session.ability_rows()
	for i in ability_views.size():
		_refresh_ability(ability_views[i], rows[i] if i < rows.size() else {}, int(hud.skill_points))
	var items := session.item_rows()
	for i in item_views.size():
		_refresh_item(item_views[i], items[i] if i < items.size() else {})


func _refresh_ability(view: Dictionary, row: Dictionary, skill_points: int) -> void:
	var known := int(row.get("catalog_id", 0)) != 0
	view.root.visible = known
	if not known:
		return
	var icon_path := "res://art/icons/%s.png" % row.get("ability_id", "")
	if view.icon_path != icon_path:
		view.icon_path = icon_path
		view.icon.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null
	view.name.text = "" if view.icon.texture != null else String(row.name).left(4)
	var level := int(row.level)
	view.level.text = "●".repeat(level) if level > 0 else "未學"
	var cooldown := float(row.cooldown)
	view.cooldown.visible = cooldown > 0.0
	view.cooldown.text = "%.1f" % cooldown if cooldown < 10.0 else "%d" % ceili(cooldown)
	var short := int(row.cost_state) == 2
	var base := Color(0.2, 0.17, 0.13)
	if level == 0:
		base = Color(0.12, 0.12, 0.12)
	elif cooldown > 0.0:
		base = Color(0.1, 0.09, 0.08)
	elif short:
		base = Color(0.1, 0.14, 0.3)
	view.face.color = base
	# Unlearned, cooling down or short of mana: the icon dims the same way the plain face does.
	view.icon.modulate = Color(0.35, 0.35, 0.35) if level == 0 else (Color(0.45, 0.45, 0.45) if cooldown > 0.0
		else (Color(0.5, 0.6, 1.0) if short else Color.WHITE))
	view.upgrade.visible = skill_points > 0


func _refresh_item(view: Dictionary, row: Dictionary) -> void:
	var filled := int(row.get("catalog_id", 0)) != 0
	view.name.text = String(row.get("name", "")).left(3) if filled else ""
	var cooldown := float(row.get("cooldown", 0.0))
	view.cooldown.visible = filled and cooldown > 0.0
	view.cooldown.text = "%d" % ceili(cooldown)
	view.face.color = Color(0.22, 0.18, 0.12) if filled else Color(0.11, 0.1, 0.09)


func _ability_slot(parent: Control, slot: int) -> Dictionary:
	var root := Control.new()
	root.position = Vector2(10 + slot * (SLOT_SIZE + 8), 28)
	root.size = Vector2(SLOT_SIZE, 46)
	parent.add_child(root)
	var edge := ColorRect.new()
	edge.color = EDGE
	edge.size = root.size
	root.add_child(edge)
	var face := ColorRect.new()
	face.position = Vector2(2, 2)
	face.size = root.size - Vector2(4, 4)
	root.add_child(face)
	var icon := TextureRect.new()
	icon.position = face.position
	icon.size = face.size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)
	var name_label := _label(root, 13, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.position = Vector2(0, 12)
	name_label.size = Vector2(SLOT_SIZE, 18)
	var key := _label(root, 12, HORIZONTAL_ALIGNMENT_LEFT)
	key.text = SLOT_KEYS[slot]
	key.position = Vector2(4, 0)
	key.size = Vector2(20, 14)
	key.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	var level := _label(root, 9, HORIZONTAL_ALIGNMENT_CENTER)
	level.position = Vector2(0, 31)
	level.size = Vector2(SLOT_SIZE, 13)
	var cooldown := _label(root, 22, HORIZONTAL_ALIGNMENT_CENTER)
	cooldown.position = Vector2(0, 8)
	cooldown.size = Vector2(SLOT_SIZE, 30)
	cooldown.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	var upgrade := _label(root, 14, HORIZONTAL_ALIGNMENT_RIGHT)
	upgrade.text = "+"
	upgrade.position = Vector2(0, -2)
	upgrade.size = Vector2(SLOT_SIZE - 4, 16)
	upgrade.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	return {"root": root, "face": face, "icon": icon, "icon_path": "", "name": name_label, "level": level,
		"cooldown": cooldown, "upgrade": upgrade}


func _item_slot(parent: Control, slot: int) -> Dictionary:
	var root := Control.new()
	var start := parent.size.x - 3 * (ITEM_SIZE + 4) - 8
	root.position = Vector2(start + (slot % 3) * (ITEM_SIZE + 4), 32 + (slot / 3) * (ITEM_SIZE + 4))
	root.size = Vector2(ITEM_SIZE, ITEM_SIZE)
	parent.add_child(root)
	var edge := ColorRect.new()
	edge.color = EDGE.darkened(0.3)
	edge.size = root.size
	root.add_child(edge)
	var face := ColorRect.new()
	face.position = Vector2(1, 1)
	face.size = root.size - Vector2(2, 2)
	root.add_child(face)
	var name_label := _label(root, 12, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.size = root.size
	name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	var cooldown := _label(root, 18, HORIZONTAL_ALIGNMENT_CENTER)
	cooldown.size = root.size
	return {"face": face, "name": name_label, "cooldown": cooldown}


func _panel(parent: Control, panel_size: Vector2) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = panel_size
	panel.size = panel_size
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)
	return panel


func _label(parent: Control, font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _bar(parent: Control, at: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = at
	bar.size = Vector2(SLOT_SIZE * 6 + 5 * 8, 22)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.04, 0.04, 0.04)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


func _bar_label(bar: ProgressBar) -> Label:
	var label := _label(bar, 13, HORIZONTAL_ALIGNMENT_CENTER)
	label.size = bar.size
	return label


func _set_bar(bar: ProgressBar, label: Label, value: float, maximum: float, known: bool) -> void:
	if not known or maximum <= 0.0:
		bar.value = 0.0
		label.text = "—"
		return
	bar.max_value = maximum
	bar.value = value
	label.text = "%d / %d" % [value, maximum]

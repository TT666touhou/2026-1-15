extends HBoxContainer
class_name EquipmentInfoPanel

const TagItemScene = preload("res://Scenes/UI/EquipmentTagItemUI.tscn")
const TAG_ALIGN_GAP := 0.0
const TAG_ALIGN_Y := -2.0

const RARITY_NAMES := ["Common", "Rare", "Legendary"]
const SLOT_NAMES := ["Weapon", "Armor", "Accessory"]

@onready var panel: PanelContainer = $Panel
@onready var icon_rect: TextureRect = $Panel/VBox/Margin/Header/Icon
@onready var name_label: Label = $Panel/VBox/Margin/Header/Info/NameLabel
@onready var level_label: Label = $Panel/VBox/Margin/Header/Info/LevelLabel
@onready var content_label: RichTextLabel = $Panel/VBox/ContentMargin/ContentLabel
@onready var tag_list_container: Control = $TagListContainer
@onready var tag_list: VBoxContainer = %TagList

@onready var debug_ui: CanvasLayer = %DebugUI
@onready var level_slider: HSlider = %LevelSlider
@onready var value_label: Label = %ValueLabel

var _debug_level: int = 1
var _current_data: Resource

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_IGNORE)
	if tag_list:
		_set_mouse_filter_recursive(tag_list, Control.MOUSE_FILTER_IGNORE)

	var is_debug := get_parent() == get_tree().root
	debug_ui.visible = is_debug
	if is_debug:
		level_slider.value_changed.connect(_on_level_slider_changed)
		_run_debug_mode()

func _on_level_slider_changed(value: float) -> void:
	_debug_level = int(value)
	value_label.text = str(_debug_level)
	if _current_data:
		_current_data.item_level = _debug_level
		_recalculate_modifiers_for_level(_current_data, _debug_level)
		display_equipment(_current_data)

func _recalculate_modifiers_for_level(data: Resource, ilvl: int) -> void:
	if not data.get("modifiers"):
		return
	var scaling := 1.0 + (0.2 * float(ilvl))
	for mod in data.modifiers:
		mod.value = mod.base_value * scaling * mod.variance
		if not _is_percent_stat(mod.type):
			mod.value = round(mod.value)

func _is_percent_stat(type: int) -> bool:
	return (type >= 5 and type <= 14) or type >= 15

func _input(event: InputEvent) -> void:
	if get_parent() == get_tree().root and event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_run_debug_mode()

func _run_debug_mode() -> void:
	var gen = get_node_or_null("/root/EquipmentGenerator")
	if gen:
		_current_data = gen.generate_random_item(_debug_level)
		display_equipment(_current_data)
	else:
		_build_tag_list(_get_mock_tags())
		visible = true
		if is_inside_tree():
			await get_tree().process_frame
			_sync_tag_list_height()
			_align_tag_items()
			_center_panel_for_debug()

func display_equipment(data: Resource) -> void:
	if data == null:
		visible = false
		return

	_update_header(data)
	_update_content(data)
	_update_tags(data)

	visible = true
	custom_minimum_size.y = 0
	size.y = 0

	if is_inside_tree():
		await get_tree().process_frame
		_reset_panel_size()
		_sync_tag_list_height()
		_align_tag_items()

		if get_parent() == get_tree().root:
			_center_panel_for_debug()

func _update_header(data: Resource) -> void:
	if data.get("icon"):
		icon_rect.texture = data.icon
	else:
		var atlas = AtlasTexture.new()
		atlas.atlas = load("res://Tilesheet/colored-transparent_packed.png")
		atlas.region = Rect2(480, 288, 16, 16)
		icon_rect.texture = atlas

	name_label.text = data.get("item_name")
	name_label.add_theme_color_override("font_color", _rarity_color(data.get("rarity")))

	var rarity_str := _rarity_display_name(data.get("rarity"))
	var slot_str := _slot_display_name(data.get("slot"))
	level_label.text = "Lv.%d | %s | %s" % [data.get("item_level"), slot_str, rarity_str]

func _rarity_color(rarity: Variant) -> Color:
	if rarity == null:
		return Color.WHITE
	match int(rarity):
		1: return Color.CYAN
		2: return Color.ORANGE
		_: return Color.WHITE

func _rarity_display_name(rarity: Variant) -> String:
	var idx = int(rarity) if rarity != null else 0
	if idx >= 0 and idx < RARITY_NAMES.size():
		return RARITY_NAMES[idx]
	return "Unknown"

func _slot_display_name(slot: Variant) -> String:
	if slot == null:
		return "Item"
	var idx = int(slot)
	if idx >= 0 and idx < SLOT_NAMES.size():
		return SLOT_NAMES[idx]
	return "Item"

func _update_content(data: Resource) -> void:
	if data.has_method("get_modifiers_text"):
		content_label.text = data.get_modifiers_text()
	elif data.has_method("get_equipment_text"):
		content_label.text = data.get_equipment_text()
	else:
		content_label.text = ""

func _update_tags(data: Resource) -> void:
	var tags: Array = []
	if data.get("traits") is Array:
		tags.assign(data.get("traits"))
	if tags.is_empty():
		tags = _get_mock_tags()
	_build_tag_list(tags)

func _build_tag_list(tags: Array) -> void:
	if not tag_list:
		return
	for child in tag_list.get_children():
		child.queue_free()
	for tag_data in tags:
		var item = TagItemScene.instantiate()
		tag_list.add_child(item)
		if item.has_method("setup"):
			item.setup(tag_data)

func _get_mock_tags() -> Array:
	return [
		{"name": "Immortal", "color": Color(0.75, 0.75, 0.75), "icon": load("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/offhand_shield.png") as Texture2D},
		{"name": "Crimson", "color": Color(0.8, 0.1, 0.1), "icon": load("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/weapon_sword1.png") as Texture2D},
		{"name": "Swift Wind", "color": Color(0.0, 1.0, 0.5), "icon": load("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/weapon_bow1.png") as Texture2D},
	]

func _reset_panel_size() -> void:
	if panel:
		panel.custom_minimum_size.y = 0

func _sync_tag_list_height() -> void:
	if tag_list_container and panel:
		tag_list_container.custom_minimum_size.y = panel.size.y

func _align_tag_items() -> void:
	if not panel or not tag_list:
		return
	var panel_right := panel.global_position.x + panel.size.x
	for item in tag_list.get_children():
		if not (item is Control):
			continue
		var anchor = item.get_node_or_null("RightAnchor")
		if anchor and anchor is Control:
			var target_x := panel_right + TAG_ALIGN_GAP
			var delta_x: float = target_x - anchor.global_position.x
			item.global_position.x += delta_x
			item.global_position.y += TAG_ALIGN_Y

func _center_panel_for_debug() -> void:
	var viewport_size := get_viewport_rect().size
	global_position.x = (viewport_size.x - size.x) / 2
	global_position.y = (viewport_size.y * 0.4) - (size.y / 2)

func _set_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)

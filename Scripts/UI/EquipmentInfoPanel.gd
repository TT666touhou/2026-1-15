extends PanelContainer
class_name EquipmentInfoPanel

@onready var icon_rect: TextureRect = $VBox/Margin/Header/Icon
@onready var name_label: Label = $VBox/Margin/Header/Info/NameLabel
@onready var level_label: Label = $VBox/Margin/Header/Info/LevelLabel
@onready var content_label: RichTextLabel = $VBox/ContentMargin/ContentLabel

# Debug Controls
@onready var debug_ui: CanvasLayer = %DebugUI
@onready var level_slider: HSlider = %LevelSlider
@onready var value_label: Label = %ValueLabel

var _debug_level: int = 1
var _current_data: Resource 

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 確保所有子節點都不會攔截滑鼠，避免擋住底下的槽位
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_IGNORE)
	
	if get_parent() == get_tree().root:
		debug_ui.visible = true
		level_slider.value_changed.connect(_on_level_slider_changed)
		_run_debug_mode()
	else:
		debug_ui.visible = false

func _on_level_slider_changed(value: float) -> void:
	_debug_level = int(value)
	value_label.text = str(_debug_level)
	if _current_data:
		_current_data.item_level = _debug_level
		# Recalculate stats based on level
		for mod in _current_data.modifiers:
			var scaling = 1.0 + (0.2 * float(_debug_level))
			mod.value = mod.base_value * scaling * mod.variance
			if not _is_percent_stat(mod.type):
				mod.value = round(mod.value)
		display_equipment(_current_data)

func _is_percent_stat(type: int) -> bool:
	return (type >= 5 and type <= 14) or type >= 15

func _input(event: InputEvent) -> void:
	if get_parent() == get_tree().root:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_R:
				_run_debug_mode()

func _run_debug_mode() -> void:
	var gen = get_node_or_null("/root/EquipmentGenerator")
	if gen:
		_current_data = gen.generate_random_item(_debug_level)
		display_equipment(_current_data)
		visible = true
		var viewport_size = get_viewport_rect().size
		if global_position == Vector2.ZERO or get_parent() == get_tree().root:
			global_position = (viewport_size - size) / 2
	else:
		push_error("EquipmentGenerator not found!")

func display_equipment(data: Resource) -> void:
	if data == null:
		visible = false
		return
	if data.get("icon"):
		icon_rect.texture = data.icon
	else:
		var atlas = AtlasTexture.new()
		atlas.atlas = load("res://Tilesheet/colored-transparent_packed.png")
		atlas.region = Rect2(480, 288, 16, 16)
		icon_rect.texture = atlas
	name_label.text = data.get("item_name")
	var rarity = data.get("rarity")
	match rarity:
		0: name_label.add_theme_color_override("font_color", Color.WHITE)
		1: name_label.add_theme_color_override("font_color", Color.CYAN)
		2: name_label.add_theme_color_override("font_color", Color.ORANGE)
	
	var rarity_names = ["Common", "Rare", "Legendary"]
	var rarity_str = rarity_names[rarity] if rarity < rarity_names.size() else "Unknown"
	
	var slot = data.get("slot")
	var slot_names = ["Weapon", "Armor", "Accessory"]
	var slot_str = slot_names[slot] if slot != null and slot < slot_names.size() else "Item"
	
	level_label.text = "Lv.%d | %s | %s" % [data.get("item_level"), slot_str, rarity_str]
	
	if data.has_method("get_modifiers_text"):
		content_label.text = data.get_modifiers_text()
	elif data.has_method("get_equipment_text"):
		content_label.text = data.get_equipment_text()
	
	visible = true
	
	# Force size reset
	custom_minimum_size.y = 0
	size.y = 0
	if is_inside_tree():
		await get_tree().process_frame
		reset_size()
		if get_parent() == get_tree().root:
			var viewport_size = get_viewport_rect().size
			global_position.x = (viewport_size.x - size.x) / 2
			global_position.y = (viewport_size.y * 0.4) - (size.y / 2)

func _set_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)

extends HBoxContainer
class_name EquipmentInfoPanel

## 裝備資訊面版：整合了標籤生成邏輯，無需外部場景。

const RARITY_NAMES := ["Common", "Rare", "Legendary"]
const SLOT_NAMES := ["Weapon", "Armor", "Accessory"]

@onready var panel: PanelContainer = $Panel
@onready var icon_rect: TextureRect = $Panel/VBox/Margin/Header/Icon
@onready var name_label: RichTextLabel = $Panel/VBox/Margin/Header/Info/NameLabel
@onready var level_label: Label = $Panel/VBox/Margin/Header/Info/LevelLabel
@onready var content_label: RichTextLabel = $Panel/VBox/ContentMargin/ContentLabel
@onready var tag_list: VBoxContainer = %TagList

var _current_data: Resource
var _fade_tween: Tween

# 預先定義 Pill Badge 的樣式資源
var _pill_style: StyleBoxFlat

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_IGNORE)
	
	if tag_list:
		tag_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_mouse_filter_recursive(tag_list, Control.MOUSE_FILTER_IGNORE)
		
	# 初始化標籤樣式
	_pill_style = StyleBoxFlat.new()
	_pill_style.bg_color = Color(0, 0, 0, 0.6)
	_pill_style.set_corner_radius_all(12)
	_pill_style.set_border_width_all(1)
	_pill_style.border_color = Color(0.5, 0.5, 0.5, 0.4)
	_pill_style.anti_aliasing = false
	
	# F6 獨立執行時進入預覽模式
	if get_parent() == get_tree().root:
		_run_standalone_preview()

func _run_standalone_preview() -> void:
	var mock_data = {
		"item_name": "[Preview] 龍鱗重甲",
		"item_level": 45,
		"rarity": 3, # Legendary
		"slot": 1, # Armor
		"traits": _get_mock_tags(),
		"modifiers": []
	}
	# 模擬一點內容文字
	mock_data["get_modifiers_text"] = func(): return "[b]基礎防禦: +250[/b]\n[color=yellow]火抗性: +20%[/color]\n[color=cyan]格擋率: +5%[/color]"
	
	display_equipment(mock_data)
	modulate.a = 1.0 # 強制顯示，不受淡入影響
	visible = true

func display_equipment(data: Variant) -> void:
	if data == null:
		if _fade_tween: _fade_tween.kill()
		visible = false
		return

	print("[EquipmentInfoPanel] Displaying: ", data.get("item_name"))
	
	_update_header(data)
	_update_content(data)
	_update_tags(data)

	# 執行面板整體的淡入動畫
	if _fade_tween:
		_fade_tween.kill()
	
	_fade_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	modulate.a = 0.0
	visible = true
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.2)

	custom_minimum_size.y = 0
	size.y = 0

	if is_inside_tree():
		await get_tree().process_frame
		_reset_panel_size()

		if get_parent() == get_tree().root:
			_center_panel_for_debug()

func _update_header(data: Variant) -> void:
	var icon = data.get("icon")
	if icon:
		icon_rect.texture = icon
	else:
		var atlas = AtlasTexture.new()
		atlas.atlas = load("res://Tilesheet/colored-transparent_packed.png")
		atlas.region = Rect2(480, 288, 16, 16)
		icon_rect.texture = atlas

	name_label.text = str(data.get("item_name")) if data.get("item_name") != null else "Unknown"
	name_label.add_theme_color_override("default_color", _rarity_color(data.get("rarity")))

	var rarity_str := _rarity_display_name(data.get("rarity"))
	var slot_str := _slot_display_name(data.get("slot"))
	var val_lv = data.get("item_level")
	level_label.text = "Lv.%d | %s | %s" % [int(val_lv) if val_lv != null else 1, slot_str, rarity_str]

func _rarity_color(rarity: Variant) -> Color:
	if rarity == null:
		return Color.WHITE
	match int(rarity):
		1: return Color.CYAN       # Rare
		2: return Color.MEDIUM_PURPLE # Epic
		3: return Color.ORANGE     # Legendary
		4: return Color.CRIMSON    # Relic
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

func _update_content(data: Variant) -> void:
	if data is Object and data.has_method("get_modifiers_text"):
		content_label.text = data.get_modifiers_text()
	elif data is Object and data.has_method("get_equipment_text"):
		content_label.text = data.get_equipment_text()
	elif data is Dictionary and data.has("get_modifiers_text"):
		# 支援 Mock 資料中的 Callable
		var callable = data["get_modifiers_text"]
		if callable is Callable:
			content_label.text = callable.call()
	else:
		content_label.text = ""

func _update_tags(data: Variant) -> void:
	var traits = data.get("traits")
	var tags: Array = []
	if traits is Array:
		tags.assign(traits)
	
	if tags.is_empty() and get_parent() == get_tree().root:
		tags = _get_mock_tags()
		
	_build_tag_list(tags)

func _build_tag_list(tags: Array) -> void:
	if not tag_list:
		return
	for child in tag_list.get_children():
		child.queue_free()

	for tag_data in tags:
		var badge = _create_tag_badge(tag_data)
		tag_list.add_child(badge)
	
	# 強制容器重新計算大小
	if is_inside_tree():
		await get_tree().process_frame
		_reset_panel_size()

## 核心整合：直接透過程式碼構建標籤徽章 (Pill Badge)
func _create_tag_badge(tag: Variant) -> Control:
	var t_name := ""
	var t_icon: Texture2D = null
	var t_color := Color.WHITE
	
	if tag is Dictionary:
		t_name = tag.get("trait_name", tag.get("name", ""))
		t_icon = tag.get("icon", null)
		t_color = tag.get("color", Color.WHITE)
	elif tag is Resource:
		t_name = tag.get("trait_name") if tag.get("trait_name") else tag.get("name")
		t_icon = tag.get("icon") if tag.get("icon") else null
		t_color = tag.get("color") if tag.get("color") else Color.WHITE

	# 1. 建立外層容器 (MarginContainer)
	var margin = MarginContainer.new()
	margin.custom_minimum_size = Vector2(0, 18)
	margin.size_flags_horizontal = Control.SIZE_SHRINK_END
	margin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 2. 建立背景 (PanelContainer)
	var base = PanelContainer.new()
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var custom_style = _pill_style.duplicate()
	var border_color = t_color
	border_color.a = 0.5
	custom_style.border_color = border_color
	base.add_theme_stylebox_override("panel", custom_style)
	margin.add_child(base)

	# 3. 建立內部邊距 (MarginContainer)
	var innermargin = MarginContainer.new()
	innermargin.add_theme_constant_override("margin_left", 8)
	innermargin.add_theme_constant_override("margin_right", 8)
	innermargin.add_theme_constant_override("margin_top", 1)
	innermargin.add_theme_constant_override("margin_bottom", 1)
	innermargin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(innermargin)

	# 4. 建立布局 (HBoxContainer)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	innermargin.add_child(hbox)

	# 5. 建立圖示 (直接置入 HBox，確保對齊穩定)
	if t_icon:
		var icon_rect_node = TextureRect.new()
		icon_rect_node.texture = t_icon
		icon_rect_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect_node.custom_minimum_size = Vector2(13, 13)
		icon_rect_node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(icon_rect_node)

	# 6. 建立名稱標籤
	var lbl = Label.new()
	lbl.text = t_name
	lbl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = t_color
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER # 確保與圖示中線對齊
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	return margin

func _get_mock_tags() -> Array:
	return [
		{"name": "Immortal", "color": Color(0.75, 0.75, 0.75), "icon": load("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/offhand_shield.png") as Texture2D},
		{"name": "Crimson", "color": Color(0.8, 0.1, 0.1), "icon": load("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/weapon_sword1.png") as Texture2D},
		{"name": "Swift Wind", "color": Color(0.0, 1.0, 0.5), "icon": load("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/weapon_bow1.png") as Texture2D},
	]

func _reset_panel_size() -> void:
	if panel:
		panel.custom_minimum_size.y = 0

func _center_panel_for_debug() -> void:
	force_update_transform()
	var viewport_size := get_viewport_rect().size
	var target_pos = Vector2((viewport_size.x - size.x) / 2, (viewport_size.y * 0.4) - (size.y / 2))
	global_position = target_pos

func _set_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)

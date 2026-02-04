extends MarginContainer

## 裝備標籤書籤：外觀與 SynergyItem 相同，僅顯示詞條名稱＋圖示，無 count/milestone

@onready var accent_strip: ColorRect = %AccentStrip
@onready var badge_icon: TextureRect = %BadgeIcon
@onready var name_label: Label = %NameLabel
@onready var base_panel: PanelContainer = %Base
@onready var stitch_layer: ColorRect = %StitchLayer
@onready var icon_bg: NinePatchRect = %IconBG

const STITCH_SHADER = preload("res://Shaders/StitchEffect.gdshader")

func _ready() -> void:
	var mat = ShaderMaterial.new()
	mat.shader = STITCH_SHADER
	stitch_layer.material = mat
	base_panel.resized.connect(_on_base_resized)
	
	# 打印內部物件狀態以確認 ignore
	_print_mouse_filter_status(self)
	
	if get_parent() == get_tree().root:
		_run_standalone_preview()

func _print_mouse_filter_status(node: Node) -> void:
	if node is Control:
		var filter_str = "STOP"
		if node.mouse_filter == Control.MOUSE_FILTER_PASS: filter_str = "PASS"
		elif node.mouse_filter == Control.MOUSE_FILTER_IGNORE: filter_str = "IGNORE"
		print("[EquipmentTagItemUI] Node: %s, MouseFilter: %s" % [node.name, filter_str])
	for child in node.get_children():
		_print_mouse_filter_status(child)

func _on_base_resized() -> void:
	if stitch_layer.material:
		stitch_layer.material.set_shader_parameter("rect_size", base_panel.size)

## tag: Dictionary 或 Resource，需有 name/trait_name、icon、color
func setup(tag: Variant) -> void:
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
	name_label.text = t_name
	if t_icon:
		badge_icon.texture = t_icon
		badge_icon.self_modulate = Color.WHITE
	accent_strip.color = t_color
	_update_visuals(t_color)

func _update_visuals(trait_color: Color) -> void:
	if stitch_layer.material:
		var gold_color = Color("#b59c90")
		gold_color.a = 1.0
		stitch_layer.material.set_shader_parameter("stitch_color", gold_color)
		stitch_layer.material.set_shader_parameter("rect_size", base_panel.size)
	name_label.modulate = trait_color
	accent_strip.visible = true
	icon_bg.modulate = Color.WHITE

func _run_standalone_preview() -> void:
	var mock_tags = [
		{"name": "Immortal", "color": Color(0.75, 0.75, 0.75), "icon": preload("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/offhand_shield.png")},
		{"name": "Crimson", "color": Color(0.8, 0.1, 0.1), "icon": preload("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/weapon_sword1.png")},
		{"name": "Swift Wind", "color": Color(0.0, 1.0, 0.5), "icon": preload("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/weapon_bow1.png")},
	]
	var container = VBoxContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	container.add_theme_constant_override("separation", 10)
	get_tree().root.add_child.call_deferred(container)
	(func():
		for tag_data in mock_tags:
			var item = duplicate()
			container.add_child(item)
			if not item.is_node_ready():
				await item.ready
			item.setup(tag_data)
		visible = false
	).call_deferred()

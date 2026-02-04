extends MarginContainer

@onready var accent_strip: ColorRect = %AccentStrip
@onready var badge_icon: TextureRect = %BadgeIcon
@onready var name_label: Label = %NameLabel
@onready var count_label: Label = %CountLabel
@onready var milestone_container: HBoxContainer = %MilestoneContainer
@onready var base_panel: PanelContainer = %Base
@onready var stitch_layer: ColorRect = %StitchLayer
@onready var icon_bg: NinePatchRect = %IconBG

var trait_def: Variant
var trait_id: String = ""
var current_count: int = 0

const STITCH_SHADER = preload("res://Shaders/StitchEffect.gdshader")
# 與 SynergyTooltipUI 一致：已觸發白色、未觸發灰色
const COLOR_ACTIVE := Color(1.0, 1.0, 1.0)
const COLOR_INACTIVE := Color(0.298, 0.329, 0.427)

func _ready() -> void:
	if get_parent() == get_tree().root:
		_run_test_mode()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# 初始化縫線材質
	var mat = ShaderMaterial.new()
	mat.shader = STITCH_SHADER
	stitch_layer.material = mat
	# 監聽尺寸變化以更新 Shader 的 rect_size
	base_panel.resized.connect(_on_base_resized)
	
	# 打印內部物件狀態以確認 ignore
	_print_mouse_filter_status(self)

func _print_mouse_filter_status(node: Node) -> void:
	if node is Control:
		var filter_str = "STOP"
		if node.mouse_filter == Control.MOUSE_FILTER_PASS: filter_str = "PASS"
		elif node.mouse_filter == Control.MOUSE_FILTER_IGNORE: filter_str = "IGNORE"
		print("[SynergyItemUI] Node: %s, MouseFilter: %s" % [node.name, filter_str])
	for child in node.get_children():
		_print_mouse_filter_status(child)

func _on_mouse_entered() -> void:
	print("[SynergyItemUI] _on_mouse_entered trait_id=%s" % trait_id)
	if trait_id.is_empty():
		print("[SynergyItemUI] SKIP: trait_id is empty")
		return
	var hc = get_tree().get_first_node_in_group("hover_info_controller")
	if hc == null:
		print("[SynergyItemUI] SKIP: HoverInfoController not in tree (run from World.tscn to get tooltips)")
		return
	if not hc.has_method("show_synergy_info"):
		print("[SynergyItemUI] SKIP: HoverInfoController has no show_synergy_info")
		return
	print("[SynergyItemUI] Calling show_synergy_info for trait_id=%s" % trait_id)
	hc.show_synergy_info(trait_id, true)

func _on_mouse_exited() -> void:
	var hc = get_tree().get_first_node_in_group("hover_info_controller")
	if hc and hc.has_method("_hide_all"):
		hc._hide_all()

func _on_base_resized() -> void:
	if stitch_layer.material:
		stitch_layer.material.set_shader_parameter("rect_size", base_panel.size)

func _run_test_mode() -> void:
	# 模擬四種不同風格的詞條數據，僅使用英文名稱
	var mock_traits = [
		{
			"trait_id": "immortal",
			"trait_name": "Immortal",
			"color": Color(0.75, 0.75, 0.75),
			"thresholds": [1, 4, 7],
			"effect_descriptions": ["每件減傷 20%", "減傷 25%", "減傷 30%，開始戰鬥時獲得 50% 最大生命值不可疊加的護盾"],
			"icon": preload("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/offhand_shield.png")
		},
		{
			"trait_id": "crimson",
			"trait_name": "Crimson",
			"color": Color(0.8, 0.1, 0.1),
			"thresholds": [1, 3, 9],
			"effect_descriptions": ["超過 60 combo 時接下來造成的傷害都會有 1% 吸血，每件提供 1%", "門檻降低成 10 combo，吸血量不變", "追加攻擊力提高 5 倍，血量 10 倍"],
			"icon": preload("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/weapon_sword1.png")
		},
		{
			"trait_id": "swift",
			"trait_name": "Swift Wind",
			"color": Color(0.0, 1.0, 0.5),
			"thresholds": [2, 4, 6],
			"effect_descriptions": ["提高速度 0.5 倍", "提高的倍率改成 1.5 倍", "獲得 500% 攻擊力的追擊效果"],
			"icon": preload("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/weapon_bow1.png")
		},
		{
			"trait_id": "arcane",
			"trait_name": "Arcane",
			"color": Color(0.58, 0.0, 0.83),
			"thresholds": [1, 3, 5, 7],
			"effect_descriptions": ["技能傷害提高 30%", "技能傷害的提升上升到 60%", "技能傷害提高 90%", "技能傷害提高 300%"],
			"icon": preload("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/weapon_magicwand1.png")
		}
	]
	
	var container = VBoxContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	container.add_theme_constant_override("separation", 10)
	get_tree().root.add_child.call_deferred(container)
	
	(func():
		# 單獨跑書籤場景時沒有 HoverInfoController，動態加入以便 tooltip 能顯示
		var hc = get_tree().get_first_node_in_group("hover_info_controller")
		if hc == null:
			var HoverScript = load("res://Scripts/UI/HoverInfoController.gd")
			if HoverScript:
				hc = Control.new()
				hc.set_script(HoverScript)
				hc.set_anchors_preset(Control.PRESET_FULL_RECT)
				hc.mouse_filter = Control.MOUSE_FILTER_IGNORE
				get_tree().root.add_child(hc)
				# 移到最前，讓書籤列表在「上層」先接收滑鼠，判定與視覺一致
				get_tree().root.move_child(hc, 0)
		if SynergyManager:
			for trait_data in mock_traits:
				SynergyManager.register_trait(trait_data)
				SynergyManager.set_debug_count(trait_data.trait_id, trait_data.thresholds[0])
		for trait_data in mock_traits:
			var item = duplicate()
			container.add_child(item)
			if not item.is_node_ready():
				await item.ready
			item.setup(trait_data, trait_data.thresholds[0])
		visible = false
	).call_deferred()

func setup(definition: Variant, count: int) -> void:
	trait_def = definition
	current_count = count
	trait_id = ""
	if trait_def is Dictionary:
		trait_id = trait_def.get("trait_id", "")
	elif trait_def is Resource:
		var tid = trait_def.get("trait_id")
		trait_id = tid if tid != null else ""
	
	var t_name = ""
	var t_thresholds = []
	var t_icon = null
	var t_color = Color.WHITE
	
	if trait_def is Dictionary:
		t_name = trait_def.get("trait_name", "")
		t_thresholds = trait_def.get("thresholds", [])
		t_icon = trait_def.get("icon", null)
		t_color = trait_def.get("color", Color.WHITE)
	elif trait_def is Resource:
		var tn = trait_def.get("trait_name")
		t_name = tn if tn != null else ""
		var th = trait_def.get("thresholds")
		t_thresholds = th if th != null else []
		t_icon = trait_def.get("icon")
		var tc = trait_def.get("color")
		t_color = tc if tc != null else Color.WHITE
	
	# 基礎資訊
	name_label.text = t_name
	if t_icon:
		badge_icon.texture = t_icon
		badge_icon.self_modulate = Color.WHITE # 圖示保持原色
	
	# 側邊條顏色
	accent_strip.color = t_color
	
	# 計算當前階級
	var level = 0
	for i in range(t_thresholds.size()):
		if count >= t_thresholds[i]:
			level = i + 1
		else:
			break

	# 目前標籤數量
	count_label.text = str(count)
	count_label.modulate = COLOR_ACTIVE if level > 0 else COLOR_INACTIVE
			
	_update_visuals(level, t_color)
	_update_milestones(level, t_thresholds, t_color)

func _update_visuals(level: int, trait_color: Color) -> void:
	var is_active = level > 0
	
	# 更新縫線顏色 - 統一使用 UI 的新金色 (b59c90)
	if stitch_layer.material:
		var gold_color = Color("#b59c90")
		gold_color.a = 1.0 # 改為完全不透明
		stitch_layer.material.set_shader_parameter("stitch_color", gold_color)
		stitch_layer.material.set_shader_parameter("rect_size", base_panel.size)
	
	# 只有達成時名稱才變色
	if is_active:
		name_label.modulate = trait_color
		accent_strip.visible = true
		icon_bg.modulate = Color.WHITE # 激活時正常顯示
	else:
		name_label.modulate = COLOR_INACTIVE
		accent_strip.visible = false # 未達成不顯示側條
		icon_bg.modulate = Color(0.4, 0.4, 0.4) # 未達成時背景也變暗

func _update_milestones(level: int, thresholds: Array, _trait_color: Color) -> void:
	for child in milestone_container.get_children():
		child.queue_free()

	for i in range(thresholds.size()):
		var label = Label.new()
		label.text = str(thresholds[i])
		label.add_theme_font_size_override("font_size", 9)
		label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 與 tooltip 一致：僅已觸發階級為白色，其餘灰色
		label.modulate = COLOR_ACTIVE if level >= i + 1 else COLOR_INACTIVE
		milestone_container.add_child(label)

		if i < thresholds.size() - 1:
			var arrow = Label.new()
			arrow.text = ">"
			arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			arrow.modulate = COLOR_INACTIVE
			arrow.add_theme_font_size_override("font_size", 8)
			milestone_container.add_child(arrow)

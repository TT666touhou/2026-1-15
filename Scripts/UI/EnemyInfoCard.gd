extends PanelContainer

@onready var icon_rect: TextureRect = $HBox/Icon
@onready var name_label: Label = $HBox/InfoBox/NameLabel
@onready var hp_label: RichTextLabel = $HBox/InfoBox/StatsBox/HPBarContainer/HPLabel
@onready var hp_bar: ProgressBar = $HBox/InfoBox/StatsBox/HPBarContainer/HPBar
@onready var barrier_container: HBoxContainer = $HBox/InfoBox/StatsBox/BarrierContainer
@onready var str_label: Label = $HBox/InfoBox/StatsGrid/StrLabel
@onready var dex_label: Label = $HBox/InfoBox/StatsGrid/DexLabel
@onready var int_label: Label = $HBox/InfoBox/StatsGrid/IntLabel
@onready var pie_label: Label = $HBox/InfoBox/StatsGrid/PieLabel
@onready var combo_label: Label = $HBox/InfoBox/ComboLabel

var current_entity: GridEntity = null

func _ready() -> void:
	# 列表項目默認顯示
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_IGNORE)

func _set_mouse_filter_recursive(node: Node, filter: int) -> void:
	if node is Control:
		node.mouse_filter = filter
	for child in node.get_children():
		_set_mouse_filter_recursive(child, filter)

func update_info(entity: GridEntity) -> void:
	current_entity = entity
	
	if entity == null:
		# 如果實體無效，通常應該移除此卡片，這裡先隱藏
		visible = false
		return
	
	visible = true
		
	# 1. Update Icon
	var sprite = entity.get_node_or_null("Sprite2D")
	if sprite:
		# Create AtlasTexture from sprite properties to display correctly
		var atlas_tex = AtlasTexture.new()
		atlas_tex.atlas = sprite.texture
		if sprite.region_enabled:
			atlas_tex.region = sprite.region_rect
		else:
			atlas_tex.region = Rect2(0, 0, sprite.texture.get_width(), sprite.texture.get_height())
		icon_rect.texture = atlas_tex
	
	# 2. Update Character Data
	var char_data = entity.character_data
	
	if char_data:
		# Connect to signals for real-time updates
		if not char_data.health_changed.is_connected(_on_stats_changed):
			char_data.health_changed.connect(_on_stats_changed.unbind(2))
		if not char_data.stats_changed.is_connected(_on_stats_changed):
			char_data.stats_changed.connect(_on_stats_changed)
			
		_refresh_ui_from_data(char_data)
	else:
		name_label.text = entity.name
		hp_label.text = "HP: ?"
		hp_bar.value = 0
		str_label.text = ""
		dex_label.text = ""
		int_label.text = ""
		pie_label.text = ""
		combo_label.text = ""

func _process(_delta: float) -> void:
	# Removed polling logic in favor of signals
	pass

func _on_stats_changed() -> void:
	if current_entity and current_entity.character_data:
		_refresh_ui_from_data(current_entity.character_data)

func _refresh_ui_from_data(char_data: CharacterData) -> void:
	# Display Name
	var display_name = current_entity.name # Default
	if char_data.unit_def and "display_name" in char_data.unit_def:
		display_name = char_data.unit_def.display_name
	name_label.text = display_name
	
	# HP & Shield Display (Buriedbornes style: "HP + Shield*")
	var max_hp = char_data.max_health
	if char_data.has_method("get_effective_max_health"):
		max_hp = char_data.get_effective_max_health()
	
	var current_hp = char_data.current_health
	var shield = char_data.shield
	var barriers = char_data.barriers
	
	var hp_text = "[center]%d" % current_hp
	if shield > 0:
		hp_text += "[color=cyan]+%d*[/color]" % shield
	hp_text += "[/center]"
	hp_label.text = hp_text
	
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	
	# Update Barriers
	_update_barriers(barriers)
	
	# Primary Stats
	var eff_str = char_data.get_effective_str()
	var eff_dex = char_data.get_effective_dex()
	var eff_int = char_data.get_effective_int()
	var eff_pie = char_data.get_effective_pie()
	var eff_combo = char_data.get_effective_combo()
	
	str_label.text = "STR: %d" % eff_str
	dex_label.text = "DEX: %d" % eff_dex
	int_label.text = "INT: %d" % eff_int
	pie_label.text = "PIE: %d" % eff_pie
	
	# Combo
	var floor_combo = int(floor(eff_combo))
	combo_label.text = "Combo: %d (%.1f)" % [floor_combo, eff_combo]
	
	# Highlight STR if boosted
	if eff_str > char_data.base_str:
		str_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4)) # Green
	elif eff_str < char_data.base_str:
		str_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4)) # Red

func _update_barriers(count: int) -> void:
	if not barrier_container: return
	
	# 清除舊圖示
	for child in barrier_container.get_children():
		child.queue_free()
		
	# 建立新圖示 (小紫色三角形)
	for i in range(count):
		var triangle = Control.new()
		triangle.custom_minimum_size = Vector2(8, 8)
		triangle.script = GDScript.new()
		triangle.set_script(load("res://Scripts/UI/BarrierIcon.gd") if FileAccess.file_exists("res://Scripts/UI/BarrierIcon.gd") else null)
		
		# 如果沒腳本，就用一個簡單的 ColorRect
		if triangle.get_script() == null:
			var rect = ColorRect.new()
			rect.color = Color(0.6, 0.2, 1.0) # Purple
			rect.custom_minimum_size = Vector2(6, 6)
			triangle.add_child(rect)
			
		barrier_container.add_child(triangle)

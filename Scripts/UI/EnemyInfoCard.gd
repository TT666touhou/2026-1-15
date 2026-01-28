extends PanelContainer

@onready var icon_rect: TextureRect = $Margin/MainVBox/TopHBox/Icon
@onready var name_label: Label = $Margin/MainVBox/TopHBox/InfoBox/NameLabel
@onready var hp_label: RichTextLabel = $Margin/MainVBox/TopHBox/InfoBox/StatsBox/HPBarContainer/HPLabel
@onready var hp_bar: ProgressBar = $Margin/MainVBox/TopHBox/InfoBox/StatsBox/HPBarContainer/HPBar
@onready var barrier_container: HBoxContainer = $Margin/MainVBox/TopHBox/InfoBox/StatsBox/BarrierContainer
@onready var atk_label: Label = $Margin/MainVBox/TopHBox/InfoBox/StatsGrid/AtkLabel
@onready var skills_container: VBoxContainer = $Margin/MainVBox/SkillsContainer
@onready var skill_label: RichTextLabel = $Margin/MainVBox/SkillsContainer/SkillLabel

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
	
	# 確保節點已準備就緒
	if icon_rect == null:
		# 嘗試手動獲取，以防 @onready 失敗
		icon_rect = get_node_or_null("Margin/MainVBox/TopHBox/Icon")
		name_label = get_node_or_null("Margin/MainVBox/TopHBox/InfoBox/NameLabel")
		hp_label = get_node_or_null("Margin/MainVBox/TopHBox/InfoBox/StatsBox/HPBarContainer/HPLabel")
		hp_bar = get_node_or_null("Margin/MainVBox/TopHBox/InfoBox/StatsBox/HPBarContainer/HPBar")
		barrier_container = get_node_or_null("Margin/MainVBox/TopHBox/InfoBox/StatsBox/BarrierContainer")
		atk_label = get_node_or_null("Margin/MainVBox/TopHBox/InfoBox/StatsGrid/AtkLabel")
		skills_container = get_node_or_null("Margin/MainVBox/SkillsContainer")
		skill_label = get_node_or_null("Margin/MainVBox/SkillsContainer/SkillLabel")

	if icon_rect == null:
		push_error("[EnemyInfoCard] Failed to find UI nodes! Check paths.")
		return
		
	# 1. Update Icon
	var sprite = entity.get_node_or_null("Sprite2D")
	if sprite and sprite is Sprite2D:
		var atlas_tex = AtlasTexture.new()
		atlas_tex.atlas = sprite.texture
		
		if sprite.region_enabled:
			atlas_tex.region = sprite.region_rect
		elif sprite.hframes > 1 or sprite.vframes > 1:
			# Calculate region for the first frame (frame 0)
			var w = sprite.texture.get_width() / sprite.hframes
			var h = sprite.texture.get_height() / sprite.vframes
			atlas_tex.region = Rect2(0, 0, w, h)
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
		hp_bar.visible = true
		hp_bar.value = 0
		atk_label.text = ""

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
	var eff_atk = char_data.get_effective_attack()
	
	atk_label.text = "ATK: %d" % eff_atk
	
	# Update Skills
	_update_skills_info()
	
	# Highlight ATK if boosted
	if eff_atk > char_data.attack_damage:
		atk_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4)) # Green
	elif eff_atk < char_data.attack_damage:
		atk_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4)) # Red
	
	# Force container to shrink to fit new content
	reset_size()

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

func _update_skills_info() -> void:
	# 已移除敵人AI，不再顯示敵人技能信息
	if skills_container:
		skills_container.visible = false

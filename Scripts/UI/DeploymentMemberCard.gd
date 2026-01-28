extends PanelContainer
class_name DeploymentMemberCard

@onready var icon_rect: TextureRect = $HBox/Icon
@onready var info_box: VBoxContainer = $HBox/InfoBox
@onready var name_label: Label = $HBox/InfoBox/NameLabel
@onready var hp_label: RichTextLabel = $HBox/InfoBox/StatsBox/HPBarContainer/HPLabel
@onready var hp_bar: ProgressBar = $HBox/InfoBox/StatsBox/HPBarContainer/HPBar
@onready var barrier_container: HBoxContainer = $HBox/InfoBox/StatsBox/BarrierContainer
@onready var atk_label: Label = $HBox/InfoBox/StatsGrid/AtkLabel
@onready var spd_label: Label = $HBox/InfoBox/StatsGrid/SpdLabel
@onready var avd_label: Label = $HBox/InfoBox/StatsGrid/AvdLabel
@onready var acc_label: Label = $HBox/InfoBox/StatsGrid/AccLabel
@onready var dr_label: Label = $HBox/InfoBox/StatsGrid/DRLabel
@onready var res_label: Label = $HBox/InfoBox/StatsGrid/ResLabel
@onready var ref_label: Label = $HBox/InfoBox/StatsGrid/RefLabel
@onready var pur_label: Label = $HBox/InfoBox/StatsGrid/PurLabel
@onready var parry_label: Label = $HBox/InfoBox/StatsGrid/ParryLabel
@onready var drain_label: Label = $HBox/InfoBox/StatsGrid/DrainLabel
@onready var crit_dmg_label: Label = $HBox/InfoBox/StatsGrid/CritDmgLabel
@onready var pen_label: Label = $HBox/InfoBox/StatsGrid/PenLabel
@onready var combo_label: Label = $HBox/InfoBox/ComboLabel
@onready var skill_slot: SkillChargeSlot = $HBox/InfoBox/SkillSlot

# Leader Skill UI
@onready var leader_skill_box: VBoxContainer = $HBox/LeaderSkillBox
@onready var skill_name_label: Label = $HBox/LeaderSkillBox/SkillNameLabel
@onready var skill_desc_label: Label = $HBox/LeaderSkillBox/SkillDescLabel

# Equipment UI
@onready var equipment_box: VBoxContainer = $HBox/EquipmentBox
@onready var weapon_slot: EquipmentSlotUI = $HBox/EquipmentBox/Slots/WeaponSlot
@onready var armor_slot: EquipmentSlotUI = $HBox/EquipmentBox/Slots/ArmorSlot
@onready var accessory_slot: EquipmentSlotUI = $HBox/EquipmentBox/Slots/AccessorySlot

# Border for Leader
@onready var border: NinePatchRect = $Border

enum DisplayState { STATS, TRAITS, EQUIPMENT }

var character_data: CharacterData
var _current_state: DisplayState = DisplayState.STATS
var _pre_drag_state: DisplayState = DisplayState.STATS
var _is_right_pressed: bool = false
var _is_dragging_right: bool = false
const DRAG_THRESHOLD = 10.0

func _ready() -> void:
	add_to_group("deployment_member_cards")
	# Debug logs for height issue
	call_deferred("_log_heights")
	
	# F6 Debug Logic
	if get_parent() == get_tree().root:
		_run_debug_mode()

func _log_heights() -> void:
	pass
#	print("[DeploymentMemberCard] DEBUG HEIGHT REPORT")
#	print("  Self min_size: ", custom_minimum_size, " | Size: ", size)
#	if info_box: print("  InfoBox min_size: ", info_box.custom_minimum_size, " | Size: ", info_box.size)
#	if leader_skill_box: print("  LeaderSkillBox min_size: ", leader_skill_box.custom_minimum_size, " | Size: ", leader_skill_box.size)
#	if equipment_box: print("  EquipmentBox min_size: ", equipment_box.custom_minimum_size, " | Size: ", equipment_box.size)
#	if GlobalSettings.has_method("get_use_simplified_stats_ui"):
#		print("  Simplified Mode: ", GlobalSettings.get_use_simplified_stats_ui())
#	else:
#		print("  Simplified Mode: API MISSING")


func _run_debug_mode() -> void:
	# 建立虛擬數據
	var mock_def = UnitCard.new()
	mock_def.display_name = "Debug Unit"
	mock_def.max_health = 158
	mock_def.attack_damage = 10
	
	var data = CharacterData.create(mock_def)
	data.shield = randi_range(0, 300)
	data.barriers = randi_range(0, 5)
	data.base_avoid = 0.15
	data.base_accuracy = 1.0
	
	# 注入測試用的新屬性數據 (使用新增的 API)
	data.modify_dr_additive(randf_range(0.0, 0.5))
	data.modify_resistance_additive(randf_range(0.0, 0.8))
	data.modify_reflect_additive(randf_range(0.0, 1.0))
	data.modify_pursuit_additive(randi_range(0, 50))
	
	# 注入測試用的新屬性數據
	data.modify_parry_additive(randf_range(0.0, 0.5))
	data.modify_drain_additive(randf_range(0.0, 0.3))
	data.modify_crit_dmg_additive(randf_range(0.0, 2.0))
	data.modify_penetration_additive(randf_range(0.0, 1.0))
	
	# Debug mode: Generate a random item to test equipment slots
	var gen = get_node_or_null("/root/EquipmentGenerator")
	if gen:
		var item = gen.generate_random_item(5)
		data.equip(item)
	
	setup(data)
	print("[DeploymentMemberCard] Debug mode active. HP: %d, Shield: %d, Barrier: %d" % [data.current_health, data.shield, data.barriers])

func setup(data: CharacterData) -> void:
	character_data = data
	
	if character_data == null:
		return
		
	var def = character_data.unit_def
	if def:
		name_label.text = def.display_name
		if def.icon:
			# 如果是 AtlasTexture 則直接使用
			if def.icon is AtlasTexture:
				icon_rect.texture = def.icon
			else:
				# 如果是原始 Texture 且尺寸較大，則嘗試擷取第一格 (16x16)
				if def.icon.get_width() > 16 or def.icon.get_height() > 16:
					var atlas_tex = AtlasTexture.new()
					atlas_tex.atlas = def.icon
					atlas_tex.region = Rect2(0, 0, 16, 16)
					icon_rect.texture = atlas_tex
					print("[DeploymentMemberCard] Auto-atlased raw icon for: ", def.display_name)
				else:
					icon_rect.texture = def.icon
			
		# Setup Leader Skill info
		if def.character_trait:
			skill_name_label.text = def.character_trait.trait_name
			skill_desc_label.text = def.character_trait.description
		else:
			skill_name_label.text = "No Leader Skill"
			skill_desc_label.text = "-"
	
	_update_stats()
	_update_info_display()
	_update_skill_ui()
	
	# Connect signals for dynamic updates
	if not character_data.health_changed.is_connected(_on_health_changed):
		character_data.health_changed.connect(_on_health_changed)
	# CharacterData 無 combo_count_changed 信號；combo 顯示由 stats_changed 觸發 _update_stats 更新
	
	# Listen for stat recalculation updates
	if not character_data.stats_changed.is_connected(_on_stats_changed):
		character_data.stats_changed.connect(_on_stats_changed)
		
	if GlobalSettings.has_signal("settings_changed"):
		if not GlobalSettings.settings_changed.is_connected(_update_stats):
			GlobalSettings.settings_changed.connect(_update_stats)

func set_highlight(enabled: bool) -> void:
	if border:
		# Keep border visible for all, but maybe brighten it for the leader
		border.visible = true
		if enabled:
			border.modulate = Color(1.5, 1.5, 1.5, 1.0) # Brighten
		else:
			border.modulate = Color.WHITE

func _update_stats(_unused = null) -> void:
	if character_data == null: return
	
	# Use Effective Stats
	var current_hp = character_data.current_health
	var max_hp = character_data.get_effective_max_health()
	var eff_atk = character_data.get_effective_attack()
	var eff_combo = character_data.get_effective_combo()
	
	# New Stats
	var shield = character_data.shield
	var barriers = character_data.barriers
	var avd = character_data.get_effective_avoid()
	var acc = character_data.get_effective_accuracy()
	
	# 擴充屬性：使用正確的 Getter 獲取有效值
	var dr = character_data.get_effective_dr()
	var res = character_data.get_effective_resistance()
	var ref = character_data.get_effective_reflect()
	var pur = character_data.get_effective_pursuit()
	
	# 新增屬性
	var pry = character_data.get_effective_parry()
	var drn = character_data.get_effective_drain()
	var cdm = character_data.get_effective_crit_dmg()
	var pen = character_data.get_effective_penetration()
	
	# HP & Shield Display (Buriedbornes style: "HP / MAX + Shield*")
	var hp_text = "[center]%d / %d" % [current_hp, max_hp]
	if shield > 0:
		hp_text += " [color=cyan]+%d*[/color]" % shield
	hp_text += "[/center]"
	hp_label.text = hp_text
	
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	
	# Update Barriers
	_update_barriers(barriers)
	
	# Primary Stats
	var crt = character_data.get_effective_crit_rate()
	atk_label.text = "ATK: %d (CRT: %d%%)" % [eff_atk, int(crt * 100)]
	spd_label.text = "SPD: %.1f" % character_data.get_effective_speed()
	
	# 處理精簡模式
	var is_simplified = false
	if GlobalSettings.has_method("get_use_simplified_stats_ui"):
		is_simplified = GlobalSettings.get_use_simplified_stats_ui()
	
	avd_label.visible = !is_simplified
	acc_label.visible = !is_simplified
	dr_label.visible = !is_simplified
	res_label.visible = !is_simplified
	ref_label.visible = !is_simplified
	pur_label.visible = !is_simplified
	parry_label.visible = !is_simplified
	drain_label.visible = !is_simplified
	crit_dmg_label.visible = !is_simplified
	pen_label.visible = !is_simplified
	combo_label.visible = !is_simplified
	barrier_container.visible = !is_simplified
	
	avd_label.text = "AVD: %d%%" % int(avd * 100)
	acc_label.text = "ACC: %d%%" % int(acc * 100)
	
	# New Stats Labels
	dr_label.text = "DR: %d%%" % int(dr * 100)
	res_label.text = "RES: %d%%" % int(res * 100)
	ref_label.text = "REF: %d%%" % int(ref * 100)
	pur_label.text = "PUR: %d" % int(pur)
	
	parry_label.text = "PRY: %d%%" % int(pry * 100)
	drain_label.text = "DRN: %d%%" % int(drn * 100)
	crit_dmg_label.text = "CDM: %d%%" % int(200 + cdm * 100) # 基礎 200%
	pen_label.text = "PEN: %d%%" % int(pen * 100)
	
	# Combo
	var floor_combo = int(floor(eff_combo))
	combo_label.text = "Combo: %d (%.1f)" % [floor_combo, eff_combo]

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

func _update_info_display() -> void:
	info_box.visible = (_current_state == DisplayState.STATS)
	leader_skill_box.visible = (_current_state == DisplayState.TRAITS)
	equipment_box.visible = (_current_state == DisplayState.EQUIPMENT)
	
	# 技能槽位在 STATS 狀態下始終顯示
	_update_skill_ui()
	
	if _current_state == DisplayState.EQUIPMENT:
		_update_equipment_icons()

func _update_skill_ui() -> void:
	if not skill_slot: return
	
	if character_data and character_data.runtime_skill:
		skill_slot.visible = (_current_state == DisplayState.STATS) # 僅在 STATS 狀態顯示，或依需求決定
		skill_slot.setup(character_data.runtime_skill, character_data)
	else:
		skill_slot.visible = false

func _update_equipment_icons() -> void:
	if character_data == null: 
		print("[DeploymentMemberCard] Cannot update icons: character_data is NULL")
		return
	
	print("[DeploymentMemberCard] Updating icons for: %s. W:%s, A:%s, Acc:%s" % [
		character_data.unit_def.display_name if character_data.unit_def else "Unknown",
		"YES" if character_data.weapon else "NO",
		"YES" if character_data.armor else "NO",
		"YES" if character_data.accessory else "NO"
	])
	weapon_slot.set_equipment(character_data.weapon)
	armor_slot.set_equipment(character_data.armor)
	accessory_slot.set_equipment(character_data.accessory)

func _on_health_changed(_current: int, _max: int) -> void:
	_update_stats()

func _on_stats_changed() -> void:
	_update_stats()
	if _current_state == DisplayState.EQUIPMENT:
		_update_equipment_icons()

## 新增：由 GridSelector 呼叫的裝備介面
func equip_item(item_data: Resource) -> bool:
	if not character_data or not item_data: return false
	
	print("[DeploymentMemberCard] Equipping from GridSelector: ", item_data.get("item_name"))
	character_data.equip(item_data)
	# CharacterData.equip 會觸發 recalculate_stats 並發送 stats_changed
	# 這裡手動呼叫一次 _update_stats 確保 UI 即時更新 (雖然信號也會做，但這樣更保險)
	_update_stats()
	if _current_state == DisplayState.EQUIPMENT:
		_update_equipment_icons()
	return true

func force_display_state(new_state: int) -> void:
	_pre_drag_state = _current_state
	_current_state = new_state as DisplayState
	_update_info_display()

func restore_pre_drag_state() -> void:
	_current_state = _pre_drag_state
	_update_info_display()

func _gui_input(event: InputEvent) -> void:
	# Right-Click Logic
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# Disable right-drag reordering
			_is_right_pressed = false
			_is_dragging_right = false
				
		# Left-Click Logic (Toggle Info)
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_current_state = ((_current_state + 1) % 3) as DisplayState
			_update_info_display()
			
	if event is InputEventMouseMotion:
		pass

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("type") == "equipment"

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var item_data = data.get("data") as Resource
	var entity = data.get("entity") as Node2D
	
	if item_data and character_data:
		var i_name = item_data.get("item_name")
		print("[DeploymentMemberCard] DROP RECEIVED. Equipping: ", i_name)
		character_data.equip(item_data)
		
		# 從地圖上移除實體
		if entity:
			entity.queue_free()

func _get_drag_data(_at_position: Vector2) -> Variant:
	# Disable drag-and-drop deployment
	return null

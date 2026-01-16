extends Control
class_name SkillManagerUI

@onready var member_list: VBoxContainer = $HBox/LeftPanel/Scroll/MemberList
@onready var name_label: Label = $HBox/RightPanel/VBox/InfoPanel/VBox/NameLabel
@onready var desc_label: RichTextLabel = $HBox/RightPanel/VBox/InfoPanel/VBox/DescLabel
@onready var targeting_type_label: Label = %TargetingTypeLabel
@onready var execution_mode_label: Label = %ExecutionModeLabel
@onready var range_grid: GridContainer = %RangeGrid
@onready var effect_grid: GridContainer = %EffectGrid
@onready var selection_container: Control = %SelectionContainer
@onready var effect_container: Control = %EffectContainer
@onready var slot_container: HBoxContainer = $HBox/RightPanel/VBox/SlotContainer

var all_skills: Array[UnitSkillData] = []
var selected_skill: UnitSkillData = null
var current_target_unit: GridEntity = null

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_all_skills()
	_populate_skill_list()
	
	var selector = get_tree().get_first_node_in_group("grid_selector")
	if selector:
		selector.entity_selected.connect(_on_entity_selected)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		visible = !visible
		print("[SkillManagerUI] Toggle visibility: ", visible)
		
		# 核心修正：如果父節點是 DebugLayer 且隱藏中，則自動將其顯示
		var parent = get_parent()
		if visible and parent and (parent.name == "DebugLayer" or parent.name == "UI"):
			parent.visible = true
			
		if visible:
			_update_slots()

func _on_entity_selected(entity: GridEntity) -> void:
	current_target_unit = entity
	if visible:
		_update_slots()

func _load_all_skills() -> void:
	all_skills.clear()
	_scan_dir_recursive("res://Resources/Skills/")

func _scan_dir_recursive(path: String) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_dir_recursive(path + file_name + "/")
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var res = load(path + file_name)
			if res is UnitSkillData:
				all_skills.append(res)
		file_name = dir.get_next()

func _populate_skill_list() -> void:
	for child in member_list.get_children():
		child.queue_free()
		
	for skill in all_skills:
		var btn = Button.new()
		btn.text = skill.skill_name
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_skill_list_pressed.bind(skill))
		member_list.add_child(btn)
	
	# 修改：預設選取第一個技能
	if all_skills.size() > 0:
		_on_skill_list_pressed(all_skills[0])

func _on_skill_list_pressed(skill: UnitSkillData) -> void:
	selected_skill = skill
	name_label.text = skill.skill_name
	
	desc_label.text = skill.get_dynamic_description()
	
	# 更新標籤 (中文)
	var target_type_str = "相對位置 (以單位為中心)" if skill.targeting_type == UnitSkillData.TargetingType.RELATIVE else "絕對位置 (地圖固定位置)"
	targeting_type_label.text = "瞄準：" + target_type_str
	
	var mode_str = "立刻發動"
	match skill.execution_mode:
		UnitSkillData.ExecutionMode.DIRECT: mode_str = "立刻發動"
		UnitSkillData.ExecutionMode.MOVE_TRIGGER: mode_str = "移動後自動觸發"
		UnitSkillData.ExecutionMode.MOVEMENT: mode_str = "移動技能 (不結束回合)"
	execution_mode_label.text = "模式：" + mode_str
	
	_update_range_display(skill)
	_update_slots()

func _update_range_display(skill: UnitSkillData) -> void:
	# 核心修正：只有當標註為「移動技能」(is_move_skill) 且有後續效果時，才顯示兩段式 (如影襲)
	var is_two_stage = skill.is_move_skill and skill.post_move_targeting != null
	var selection_label = selection_container.get_node("Label")
	
	if is_two_stage:
		selection_container.visible = true
		effect_container.visible = true
		selection_label.text = "Selection"
		SkillTooltipUI.render_skill_grid(range_grid, skill.targeting, Color(1, 0.9, 0.2), true, Vector2(15, 15)) # 中心點
		SkillTooltipUI.render_skill_grid(effect_grid, skill.post_move_targeting, Color(1.0, 0.4, 0.1), false, Vector2(15, 15)) # 橘色
	else:
		selection_container.visible = true
		effect_container.visible = false
		
		# 強制展示 post_move_targeting
		var target_to_show = skill.post_move_targeting if skill.post_move_targeting != null else skill.targeting
		
		# 根據模式決定標題與顏色
		if skill.execution_mode == UnitSkillData.ExecutionMode.MOVEMENT:
			selection_label.text = "Selection"
			SkillTooltipUI.render_skill_grid(range_grid, target_to_show, Color(1, 0.9, 0.2), true, Vector2(15, 15))
		else:
			selection_label.text = "Effect"
			SkillTooltipUI.render_skill_grid(range_grid, target_to_show, Color(1.0, 0.4, 0.1), false, Vector2(15, 15))

# 移除原本的 _render_grid 函數，因為已經統一使用 SkillTooltipUI.render_skill_grid

func _update_slots() -> void:
	for child in slot_container.get_children():
		child.queue_free()
	
	# 如果沒有目標單位，嘗試從全域獲取
	if not is_instance_valid(current_target_unit):
		var search_groups = ["units", "grid_entities"]
		for group_name in search_groups:
			var units = get_tree().get_nodes_in_group(group_name)
			for u in units:
				if u is GridEntity:
					current_target_unit = u
					break
			if current_target_unit: break
	
	if not is_instance_valid(current_target_unit) or not current_target_unit.character_data:
		return
		
	var data = current_target_unit.character_data
	
	# 強制固定 4 個槽位
	for i in range(4):
		var btn = Button.new()
		var current_skill = data.runtime_skills[i] if i < data.runtime_skills.size() else null
		
		btn.text = "Slot %d\n%s" % [i+1, current_skill.skill_name if current_skill else "---"]
		btn.custom_minimum_size = Vector2(100, 60)
		
		# 樣式調整：如果選中了某個技能，提示這是一個替換目標
		if selected_skill:
			btn.tooltip_text = "點擊以替換為：" + selected_skill.skill_name
		
		btn.pressed.connect(_on_slot_pressed.bind(i))
		slot_container.add_child(btn)

func _on_slot_pressed(index: int) -> void:
	if not selected_skill or not is_instance_valid(current_target_unit): 
		print("[SkillManagerUI] Cannot swap: No skill selected or no unit found.")
		return
	
	var data = current_target_unit.character_data
	
	# 確保 runtime_skills 有足夠長度
	while data.runtime_skills.size() < 4:
		data.runtime_skills.append(null)
		
	data.runtime_skills[index] = selected_skill
	
	print("[SkillManagerUI] Swapped Slot %d to %s" % [index + 1, selected_skill.skill_name])
	_update_slots()
	
	# 立即更新主畫面的技能欄
	var skill_bar = get_tree().get_first_node_in_group("unit_skill_bar")
	if skill_bar and skill_bar.has_method("_populate_skills_internal"):
		skill_bar._populate_skills_internal(data, current_target_unit)

func _on_back_pressed() -> void:
	visible = false

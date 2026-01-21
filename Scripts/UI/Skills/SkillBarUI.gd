extends VBoxContainer
class_name SkillBarUI

@export var button_scene: PackedScene
@export var tooltip_scene: PackedScene

@onready var fixed_tooltip_slot: PanelContainer = %FixedTooltipSlot
@onready var button_container: HBoxContainer = %ButtonContainer

var current_unit: GridEntity = null
var current_character: CharacterData = null
var _tooltip: SkillTooltipUI = null
var _hover_timer: Timer = null
var _hovered_skill: UnitSkillData = null

## 當前正在「確認中」或「武裝中」的技能按鈕
var active_button: SkillButtonUI = null

func _ready() -> void:
	add_to_group("unit_skill_bar")
	
	if PartyManager:
		PartyManager.party_updated.connect(_refresh_from_party_manager)
	
	if TurnManager:
		TurnManager.turn_started.connect(_on_turn_started)
	
	var selector = get_tree().get_first_node_in_group("grid_selector")
	if selector:
		selector.entity_selected.connect(_on_entity_selected)
	
	_hover_timer = Timer.new()
	_hover_timer.wait_time = 0.5
	_hover_timer.one_shot = true
	_hover_timer.timeout.connect(_show_tooltip)
	add_child(_hover_timer)
	
	# 初始化固定 Tooltip
	if tooltip_scene:
		_tooltip = tooltip_scene.instantiate()
		fixed_tooltip_slot.add_child(_tooltip)
		_tooltip.visible = false
		fixed_tooltip_slot.visible = false
	
	call_deferred("_refresh_from_party_manager")

func _on_turn_started(_faction) -> void:
	# 回合開始時強制更新所有按鈕狀態
	# (參數 faction 為 FactionDefinition，但我們這裡不需要用到)
	get_tree().call_group("skill_buttons", "_update_unit_status")

func _on_entity_selected(entity: GridEntity) -> void:
	if entity == null: return
	
	var current_unit_name = str(current_unit.name) if current_unit != null else "None"
	print("[SkillBarUI] Entity selected: ", entity.name, " Current Unit: ", current_unit_name)
	
	# 更加嚴格的檢查：如果當前單位已經選中，或者技能正在武裝中，不要重刷 UI，避免狀態丟失
	if current_unit == entity or (active_button and is_instance_valid(active_button.source_unit) and active_button.source_unit == entity):
		print("[SkillBarUI] Skipping repopulation to preserve active skill state.")
		return
		
	_populate_skills_internal(entity.character_data, entity)

func _refresh_from_party_manager() -> void:
	if PartyManager and PartyManager.party_members.size() > 0:
		var lead = PartyManager.party_members[0]
		var units = get_tree().get_nodes_in_group("units")
		var found_unit = null
		for u in units:
			if u is GridEntity and u.character_data == lead:
				found_unit = u
				break
		_populate_skills_internal(lead, found_unit)

func _populate_skills_internal(char_data: CharacterData, unit: GridEntity = null) -> void:
	# 清理舊按鈕
	for child in button_container.get_children():
		if child is SkillButtonUI: child.queue_free()
	
	current_character = char_data
	current_unit = unit
	active_button = null
	
	if not char_data: return
	
	for skill in char_data.runtime_skills:
		var btn = button_scene.instantiate() as SkillButtonUI
		button_container.add_child(btn)
		btn.setup(skill, char_data, unit)
		btn.state_changed.connect(_on_button_state_changed)
		btn.confirmed.connect(_execute_direct_skill) # 改用 confirmed 信號
		btn.mouse_entered.connect(_on_mouse_entered.bind(skill))
		btn.mouse_exited.connect(_on_mouse_exited)

func _on_button_state_changed(new_state: int, button: SkillButtonUI) -> void:
	print("[SkillBarUI] Button state changed: ", button.skill_data.skill_name, " -> ", new_state)
	
	# 如果有新按鈕進入激活狀態，取消舊的 active_button (如果不同)
	if new_state == SkillButtonUI.SkillState.CONFIRM_DIRECT or new_state == SkillButtonUI.SkillState.ARMED:
		if active_button and active_button != button:
			active_button.reset_to_idle()
			
		active_button = button
		
		# 自動選取單位以確保 GridSelector 有正確的參考對象
		var selector = get_tree().get_first_node_in_group("grid_selector")
		if selector and current_unit:
			print("[SkillBarUI] Auto-selecting unit for skill: ", current_unit.name)
			selector.select_entity(current_unit)
			
		_update_world_preview()
		
	elif active_button == button and new_state == SkillButtonUI.SkillState.IDLE:
		active_button = null
		_clear_world_preview()

## 外部接口：取消當前技能
func cancel_active_skill() -> void:
	if active_button:
		active_button.handle_cancel()

func _execute_direct_skill(button: SkillButtonUI) -> void:
	var skill = button.skill_data
	var unit = button.source_unit
	if not is_instance_valid(unit): return
	
	print("[SkillBarUI] Confirming Direct Skill: ", skill.skill_name)
	# execute_skill 現在是非同步的 (coroutine)
	if await SkillManager.execute_skill(unit, skill, unit.grid_position):
		button.reset_to_idle()
		# 重新加載技能狀態（冷卻等）
		_populate_skills_internal(button.character_data, unit)

## 被 GridSelector 在移動完成後調用
func trigger_armed_skill(unit: GridEntity, final_pos: Vector2i) -> void:
	if active_button and active_button.current_state == SkillButtonUI.SkillState.ARMED:
		var btn = active_button
		var skill = btn.skill_data
		var char_data = btn.character_data
		
		print("[SkillBarUI] Triggering Armed Skill: ", skill.skill_name)
		# execute_skill 現在是非同步的 (coroutine)
		await SkillManager.execute_skill(unit, skill, final_pos)
		
		# 根據類型決定是否結束回合
		if skill.execution_mode == UnitSkillData.ExecutionMode.MOVE_TRIGGER:
			if TurnManager: await TurnManager.advance_turn()
		
		if is_instance_valid(btn):
			btn.reset_to_idle()
		
		_populate_skills_internal(char_data, unit)

func _update_world_preview() -> void:
	var selector = get_tree().get_first_node_in_group("grid_selector")
	if selector and active_button:
		selector.sync_skill_preview(active_button.skill_data)

func _clear_world_preview() -> void:
	var selector = get_tree().get_first_node_in_group("grid_selector")
	if selector:
		selector.sync_skill_preview(null)

# --- Tooltip 邏輯 ---
func _on_mouse_entered(skill: UnitSkillData) -> void:
	_hovered_skill = skill
	_hover_timer.start()

func _on_mouse_exited() -> void:
	_hovered_skill = null
	_hover_timer.stop()
	if _tooltip:
		_tooltip.hide_tooltip()
		fixed_tooltip_slot.visible = false

func _show_tooltip() -> void:
	if not _hovered_skill or not _tooltip: return
	
	_tooltip.setup(_hovered_skill)
	fixed_tooltip_slot.visible = true
	_tooltip.show_at(Vector2.ZERO) # 座標不再重要，因為在容器內

extends Button
class_name SkillButtonUI

## 技能按鈕狀態
enum SkillState { 
	IDLE,            # 閒置
	CONFIRM_DIRECT,  # 直接施放類：等待再次點擊確認
	ARMED,           # 移動類：已準備好，等待移動觸發
	COOLDOWN         # 冷卻中
}

var current_state: SkillState = SkillState.IDLE
var skill_data: UnitSkillData = null
var source_unit: GridEntity = null
var character_data: CharacterData = null

@onready var label: Label = $Margin/VBox/Label
@onready var mini_range_grid: GridContainer = %MiniRangeGrid
@onready var cd_overlay: ColorRect = $CDOverlay
@onready var cd_label: Label = $CDOverlay/CDLabel

signal state_changed(new_state: int, button: SkillButtonUI)
signal confirmed(button: SkillButtonUI) # 新增：確認施放信號

func setup(data: UnitSkillData, char_data: CharacterData, unit: GridEntity = null) -> void:
	skill_data = data
	character_data = char_data
	source_unit = unit
	text = "" 
	label.text = data.skill_name
	icon = data.icon
	
	add_to_group("skill_buttons")
	_render_mini_grid()
	
	# 初始化時立即更新一次狀態與視覺
	_update_unit_status()
	_update_visuals()
	
	# 確保縮放比例始終為 1，防止懸停改變大小
	scale = Vector2.ONE
	pivot_offset = size / 2.0

func _ready() -> void:
	# 確保進入場景時再次檢查
	_update_unit_status()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		handle_cancel()
		accept_event()

func _process(_delta: float) -> void:
	# 確保縮放比例始終為 1，防止懸停改變大小
	scale = Vector2.ONE
	
	_update_cooldown()
	_update_unit_status()

func _update_unit_status() -> void:
	if not character_data: return
	
	# 如果單位無效，嘗試尋找
	if not is_instance_valid(source_unit):
		_find_source_unit()
		if not is_instance_valid(source_unit):
			disabled = true # 單位真的不存在才禁用
			modulate = Color(0.5, 0.5, 0.5, 0.4)
			return

	var is_player_turn = TurnManager.is_player_turn() if TurnManager else false
	var is_on_cd = character_data.skill_cooldowns.get(skill_data.skill_name, 0) > 0
	var has_used = character_data.has_used_skill_this_turn
	var is_roaming = TurnManager.is_free_roam_mode if TurnManager else false
	
	# 安全性檢查：如果已經不是玩家回合、或該單位已用過技能，但按鈕還停留在預覽狀態，則強制重置
	if (not is_player_turn or has_used or is_roaming) and current_state in [SkillState.CONFIRM_DIRECT, SkillState.ARMED]:
		reset_to_idle()
	
	# 寬鬆判定：只要不是 CD 中，按鈕原則上都可點擊（讓 _on_pressed 處理邏輯檢查）
	# 這樣避免因 TurnManager 狀態短暫不同步而導致無法點擊
	
	if current_state == SkillState.COOLDOWN:
		disabled = true
		modulate.a = 0.6
	elif is_roaming:
		# 漫遊模式下禁用技能
		disabled = true
		modulate = Color(0.5, 0.5, 0.5, 0.6)
	else:
		# 即使不是玩家回合或已行動，也不禁用按鈕，只做視覺區分
		disabled = false 
		
		# 視覺反饋：如果條件不滿足，稍微變暗，但依然可點
		var logic_valid = is_player_turn and not is_on_cd and not has_used
		if not logic_valid:
			modulate = Color(0.7, 0.7, 0.7, 0.8) # 視覺上稍微暗一點
		else:
			modulate = Color.WHITE
		
	# 保護：如果處於 ARMED 或 CONFIRM 狀態，不要讓 IDLE 的文字邏輯覆蓋它
	# 文字與顏色的更新應由 set_state / _update_visuals 統一處理
	if current_state != SkillState.IDLE and current_state != SkillState.COOLDOWN:
		modulate = Color.WHITE 
		_update_visuals() # 再次確保顏色正確

func _find_source_unit() -> void:
	var search_groups = ["units", "grid_entities"]
	for group_name in search_groups:
		var candidates = get_tree().get_nodes_in_group(group_name)
		for u in candidates:
			if u is GridEntity and u.character_data == character_data:
				source_unit = u
				return

func _update_cooldown() -> void:
	if not character_data or not skill_data: return
	var cd = character_data.skill_cooldowns.get(skill_data.skill_name, 0)
	
	if cd > 0:
		if current_state != SkillState.COOLDOWN:
			set_state(SkillState.COOLDOWN)
		cd_label.text = str(cd)
	elif current_state == SkillState.COOLDOWN:
		set_state(SkillState.IDLE)

func set_state(new_state: SkillState) -> void:
	if current_state == new_state: return
	print("[SkillButtonUI] State changed: ", skill_data.skill_name, " -> ", new_state)
	current_state = new_state
	_update_visuals()
	state_changed.emit(current_state, self)

func _update_visuals() -> void:
	modulate = Color.WHITE
	cd_overlay.visible = false
	label.remove_theme_color_override("font_color")
	
	match current_state:
		SkillState.IDLE:
			label.text = skill_data.skill_name
		SkillState.CONFIRM_DIRECT:
			modulate = Color(1.5, 1.5, 0.5) # 明亮的黃色
			label.text = "確認施放?"
			label.add_theme_color_override("font_color", Color.YELLOW)
		SkillState.ARMED:
			modulate = Color(0.5, 1.0, 1.5) # 明亮的藍色 (武裝中)
			label.text = "已準備"
			label.add_theme_color_override("font_color", Color.CYAN)
		SkillState.COOLDOWN:
			modulate = Color(0.4, 0.4, 0.4, 1.0)
			cd_overlay.visible = true
			label.text = skill_data.skill_name

func _render_mini_grid() -> void:
	if not mini_range_grid or not skill_data: return
	var target_to_show = skill_data.post_move_targeting if skill_data.post_move_targeting != null else skill_data.targeting
	
	# 尋找移動效果方向
	var move_dir = Vector2i.ZERO
	for effect in skill_data.effects:
		if effect.effect_type == EffectDefinition.EffectType.MOVE:
			move_dir = effect.move_direction
			break
			
	var is_pure_move = skill_data.execution_mode == UnitSkillData.ExecutionMode.MOVEMENT or skill_data.is_move_skill
	var color = Color(1, 0.9, 0.2) if is_pure_move else Color(1.0, 0.4, 0.1)
	SkillTooltipUI.render_skill_grid(mini_range_grid, target_to_show, color, is_pure_move, Vector2(4, 4), move_dir)

func _on_pressed() -> void:
	if disabled: return
	
	# Lazy Validation: 按下時才檢查邏輯條件
	if not character_data or not source_unit: return
	
	var is_player_turn = TurnManager.is_player_turn() if TurnManager else false
	var has_used = character_data.has_used_skill_this_turn
	var is_roaming = TurnManager.is_free_roam_mode if TurnManager else false
	
	if not is_player_turn or is_roaming:
		print("[SkillButtonUI] Click ignored: Not player turn or in roaming mode.")
		# 可選：播放一個錯誤音效或顯示提示
		return
		
	if has_used:
		print("[SkillButtonUI] Click ignored: Unit has already used a skill.")
		return
	
	match current_state:
		SkillState.IDLE:
			# 根據類型進入對應狀態
			if skill_data.execution_mode == UnitSkillData.ExecutionMode.DIRECT:
				# 取消其他所有按鈕的狀態
				get_tree().call_group("skill_buttons", "reset_to_idle_except", self)
				set_state(SkillState.CONFIRM_DIRECT)
			else:
				# 移動類技能進入武裝模式
				get_tree().call_group("skill_buttons", "reset_to_idle_except", self)
				set_state(SkillState.ARMED)
				
		SkillState.CONFIRM_DIRECT:
			# 再次點擊確認施放
			confirmed.emit(self)
			
		SkillState.ARMED:
			# 再次點擊取消武裝
			reset_to_idle()

func reset_to_idle() -> void:
	if current_state != SkillState.COOLDOWN:
		set_state(SkillState.IDLE)

func reset_to_idle_except(exception: SkillButtonUI) -> void:
	if self != exception:
		reset_to_idle()

## 外部接口：供右鍵取消使用
func handle_cancel() -> void:
	if current_state in [SkillState.CONFIRM_DIRECT, SkillState.ARMED]:
		reset_to_idle()

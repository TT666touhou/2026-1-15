extends Node
class_name GridSelector

signal entity_selected(entity: GridEntity)
signal selection_cleared()

@export var selection_layer_path: NodePath
@export var enable_debug_log: bool = false
@export var allow_click_move: bool = false

var grid: Node
var selected_entity: GridEntity = null
var selection_highlight: Node2D = null
var _movement_range_indicator: Node = null
var _reachable_cells: Array[Vector2i] = []
var _skill_preview_controller: SkillPreviewController = null

# 當前要預覽的技能（純視覺參考）
var _previewing_skill: UnitSkillData = null

enum InputState { IDLE, PRESSED, DRAGGING }
var _input_state: InputState = InputState.IDLE
var _press_start_pos: Vector2
const DRAG_THRESHOLD: float = 10.0

# 視覺效果
var _drag_actor: Sprite2D = null
var _ghost_actor: Sprite2D = null
var _original_sprite: Sprite2D = null
var _oscillator_velocity: float = 0.0
var _oscillator_displacement: float = 0.0
var _last_drag_pos: Vector2 = Vector2.ZERO
var _active_combo_targets: Dictionary = {} # { TargetEntity: count }
var _drag_layer: CanvasLayer = null # 新增：用於確保拖拽視覺在所有 UI 之上
const ROTATION_SPRING: float = 150.0
const ROTATION_DAMP: float = 10.0
const VELOCITY_MULTIPLIER: float = 1.0

func _ready() -> void:
	grid = get_tree().get_first_node_in_group("grid")
	
	# 使用 deferred 來確保其他 Node 都已經 ready 並加入 group
	call_deferred("_find_preview_controller")
	call_deferred("_find_movement_indicator")
	
	if selection_layer_path != NodePath():
		selection_highlight = get_node_or_null(selection_layer_path)
	
	add_to_group("grid_selector")

func _find_preview_controller() -> void:
	_skill_preview_controller = get_tree().get_first_node_in_group("skill_preview_controller")
	if not _skill_preview_controller and enable_debug_log:
		print("[GridSelector] Warning: SkillPreviewController not found in group.")

func _find_movement_indicator() -> void:
	_movement_range_indicator = get_tree().get_first_node_in_group("movement_range_indicator")
	if not _movement_range_indicator and enable_debug_log:
		print("[GridSelector] Warning: MovementRangeIndicator not found in group.")

func _input(event: InputEvent) -> void:
	# 核心：當忙碌或輸入鎖定時，攔截所有滑鼠事件
	if TurnManager and TurnManager.is_busy():
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return

	# 核心優化：當處於按下或拖拽狀態時，使用 _input 攔截全域事件 (即使滑鼠在 UI 上)
	if _input_state == InputState.IDLE: return
	
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _input_state == InputState.DRAGGING:
				_handle_drag_release(mb.position)
			elif _input_state == InputState.PRESSED:
				_handle_left_click()
			_input_state = InputState.IDLE
			get_viewport().set_input_as_handled()
			
	elif event is InputEventMouseMotion:
		if _input_state == InputState.PRESSED:
			if _press_start_pos.distance_to(event.position) > DRAG_THRESHOLD:
				# --- 修改：停用玩家單位的拖動移動 ---
				if selected_entity and selected_entity.faction and selected_entity.faction.is_controllable:
					if not selected_entity is EquipmentEntity: # 假設裝備還是可以拖動
						return
				
				_input_state = InputState.DRAGGING
				_start_drag_visuals(event.position)
				get_viewport().set_input_as_handled()
		elif _input_state == InputState.DRAGGING:
			# 無論何時，只要有技能預覽，就更新它
			if _previewing_skill != null:
				_update_skill_world_preview()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_input_state = InputState.PRESSED
				_press_start_pos = mb.position
				# 修改：直接檢查選取
				var world_pos = get_viewport().get_camera_2d().get_global_mouse_position()
				var cell = grid.world_to_grid(world_pos)
				var entity = grid.get_occupant(cell)
				if entity == null: entity = _try_rebind_occupant(cell)
				
				if entity is GridEntity:
					select_entity(entity)
				else:
					# 點擊空白處或非實體，清空選取
					clear_selection()
			# Release 由 _input 處理
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# 右鍵邏輯不變
			var skill_bar = get_tree().get_first_node_in_group("unit_skill_bar")
			if skill_bar and skill_bar.active_button:
				print("[GridSelector] Right click detected, canceling active skill.")
				skill_bar.cancel_active_skill()
			else:
				print("[GridSelector] Right click detected, clearing selection.")
				clear_selection()
				
	elif event is InputEventMouseMotion:
		# 當 IDLE 時，如果正在預覽技能 (例如點選了技能但還沒拖拽)，仍要更新預覽
		if _input_state == InputState.IDLE and _previewing_skill != null:
			_update_skill_world_preview()

func _update_skill_world_preview() -> void:
	if not _skill_preview_controller or not _previewing_skill: return
	
	# 預設中心點為當前選取的單位位置 (完全不使用滑鼠位置)
	var center_cell = Vector2i(-1, -1)
	
	if selected_entity:
		center_cell = selected_entity.grid_position
	else:
		# Fallback: 如果 selected_entity 丟失，嘗試從 SkillBarUI 找回正在施法的單位
		var skill_bar = get_tree().get_first_node_in_group("unit_skill_bar")
		if skill_bar and skill_bar.active_button and is_instance_valid(skill_bar.active_button.source_unit):
			center_cell = skill_bar.active_button.source_unit.grid_position

	if _previewing_skill.execution_mode == UnitSkillData.ExecutionMode.DIRECT:
		# 直接施放：預覽鎖定在單位當前位置
		# (center_cell 已設定)
		pass
	else:
		# 移動類：
		# 1. 拖動中 -> 鬼影位置 (預計落點)
		# 2. 未拖動 -> 單位當前位置
		if _input_state == InputState.DRAGGING and _ghost_actor and _ghost_actor.visible:
			center_cell = grid.world_to_grid(_ghost_actor.global_position)
		elif selected_entity != null:
			center_cell = selected_entity.grid_position
	
	# 如果完全沒有有效中心點，則清空預覽
	if center_cell == Vector2i(-1, -1):
		# 不要太快清除，除非確定沒有 active skill
		var skill_bar = get_tree().get_first_node_in_group("unit_skill_bar")
		if not skill_bar or not skill_bar.active_button:
			_skill_preview_controller.clear_preview()
		return
		
	_skill_preview_controller.update_preview(selected_entity, _previewing_skill, center_cell)

func sync_skill_preview(skill: UnitSkillData) -> void:
	if enable_debug_log:
		var skill_name = str(skill.skill_name) if skill != null else "None"
		print("[GridSelector] Sync skill preview: ", skill_name)
	
	# 如果 controller 尚未找到，再次嘗試尋找
	if not _skill_preview_controller:
		_find_preview_controller()
		
	_previewing_skill = skill
	if skill == null and _skill_preview_controller:
		_skill_preview_controller.clear_preview()
	else:
		_update_skill_world_preview()

# --- 基礎選取與移動 ---

func _handle_left_click() -> void:
	var camera = get_viewport().get_camera_2d()
	if camera == null: return
	var world_pos = camera.get_global_mouse_position()
	var cell = grid.world_to_grid(world_pos)
	var entity = grid.get_occupant(cell)
	if entity == null: entity = _try_rebind_occupant(cell)
	
	if entity is GridEntity:
		select_entity(entity)
	elif allow_click_move and selected_entity and cell in _reachable_cells:
		_execute_move(cell)
	else:
		# 點擊非選取目標也非可移動格，則清空選取
		clear_selection()

func _try_rebind_occupant(cell: Vector2i) -> GridEntity:
	var entities = get_tree().get_nodes_in_group("grid_entities")
	for e in entities:
		var ge = e as GridEntity
		if ge and ge.grid_position == cell:
			if grid.has_method("set_cell_occupied"):
				grid.set_cell_occupied(cell, ge)
			return ge
	return null

func _handle_drag_release(_screen_pos: Vector2) -> void:
	if selected_entity == null: return
	
	# 優先檢查是否釋放在 UI 卡片上
	var target_card = _get_card_at_pos(_screen_pos)
	if target_card and selected_entity is EquipmentEntity:
		if target_card.has_method("equip_item"):
			if target_card.equip_item(selected_entity.equipment_data):
				print("[GridSelector] Success: Equipped via UI to ", target_card.name)
				selected_entity.queue_free()
				_end_drag_visuals()
				clear_selection()
				return

	# 原有的網格釋放邏輯
	var world_pos = get_viewport().get_camera_2d().get_global_mouse_position()
	var cell = grid.world_to_grid(world_pos)
	
	if selected_entity is EquipmentEntity:
		var target = grid.get_occupant(cell)
		if target is GridEntity and target.has_method("equip_item"):
			if target.equip_item(selected_entity.equipment_data):
				print("[GridSelector] Success: Equipped via Grid to ", target.name)
				selected_entity.queue_free()
				_end_drag_visuals()
				clear_selection()
				return
		
		# 如果沒裝備成功，回到原位
		_end_drag_visuals()
		return

	if cell in _reachable_cells:
		_execute_move(cell)
	else:
		_end_drag_visuals()
		# 不清除選取，讓玩家可以重新拖動

func _get_card_at_pos(screen_pos: Vector2) -> DeploymentMemberCard:
	var cards = get_tree().get_nodes_in_group("deployment_member_cards")
	for card in cards:
		if card is DeploymentMemberCard and card.is_visible_in_tree():
			if card.get_global_rect().has_point(screen_pos):
				return card
	return null

func _execute_move(target_cell: Vector2i) -> void:
	var mover = selected_entity.get_node_or_null("GridMover")
	if not mover: return
	
	if TurnManager: TurnManager.lock_input()
	
	if mover.has_signal("movement_completed"):
		mover.movement_completed.connect(_on_move_finished, CONNECT_ONE_SHOT)
	
	_end_drag_visuals()
	
	# 記錄目前格子，用於判斷是否真的有啟動移動
	var start_cell = selected_entity.grid_position
	mover.move_to(target_cell, false)
	
	# 安全檢查：如果 mover 因為路徑不通或其他原因根本沒啟動移動，則立即解鎖
	if selected_entity.grid_position == start_cell and not mover.is_moving():
		print("[GridSelector] Movement failed to start, unlocking input.")
		if mover.movement_completed.is_connected(_on_move_finished):
			mover.movement_completed.disconnect(_on_move_finished)
		if TurnManager: TurnManager.unlock_input()

func _on_move_finished(entity: GridEntity, final_pos: Vector2i) -> void:
	print("[GridSelector] Move finished for ", entity.name, " to ", final_pos)
	
	var skill_bar = get_tree().get_first_node_in_group("unit_skill_bar")
	var handled_by_skill = false
	var is_type_3_movement_skill = false
	
	# 核心：移動完成後，檢查是否有 ARMED 技能需要觸發 (移動後觸發類 或 移動技能)
	if skill_bar and skill_bar.active_button and skill_bar.active_button.current_state == SkillButtonUI.SkillState.ARMED:
		var skill = skill_bar.active_button.skill_data
		if skill and skill.execution_mode == UnitSkillData.ExecutionMode.MOVEMENT:
			is_type_3_movement_skill = true
			
		handled_by_skill = true
		skill_bar.trigger_armed_skill(entity, final_pos)
	
	# 標記該單位這回合已經移動過 (排除移動技能)
	if entity.character_data and not is_type_3_movement_skill:
		# 修改：在漫遊模式下不標記「已移動」，讓單位可以連續移動
		if not TurnManager or not TurnManager.is_free_roam_mode:
			entity.character_data.has_moved_this_turn = true
		if enable_debug_log:
			print("[GridSelector] Unit marked as moved: ", entity.name, " has_moved: ", entity.character_data.has_moved_this_turn)
	elif is_type_3_movement_skill and enable_debug_log:
		print("[GridSelector] Movement skill used, not marking as moved for: ", entity.name)
	
	# 如果不是技能觸發（即：一般移動、或是放完 DIRECT 技能後的移動），則結束回合
	# 規則 6：結束回合的信號只會在移動後發動 (除非剛才觸發的是「移動技能」)
	if not handled_by_skill:
		if TurnManager:
			# 修改：在漫遊模式下不推進回合
			if TurnManager.is_free_roam_mode:
				print("[GridSelector] Free roam mode, skipping turn advancement.")
			else:
				print("[GridSelector] Normal movement finished, advancing turn.")
				await TurnManager.advance_turn()
	
	# 固定流程：移動後一律清空選取，確保視覺指示器正確關閉
	print("[GridSelector] Movement lifecycle finished, forcing clear_selection.")
	clear_selection()
	
	if TurnManager: TurnManager.unlock_input() # 最後才解鎖

# --- 視覺輔助 ---

func select_entity(entity: GridEntity) -> void:
	if selected_entity: selected_entity.on_deselected()
	selected_entity = entity
	selected_entity.on_selected()
	_update_reachable_cells(entity)
	_update_highlight()
	entity_selected.emit(entity)

func clear_selection() -> void:
	if selected_entity:
		selected_entity.on_deselected()
		selected_entity = null
	_reachable_cells.clear()
	_update_highlight()
	selection_cleared.emit()
	
	# 確保指示器也被清除
	if _movement_range_indicator:
		_movement_range_indicator.clear_indicator()

func get_current_reachable_cells() -> Array[Vector2i]:
	return _reachable_cells

func _update_reachable_cells(entity: GridEntity) -> void:
	_reachable_cells.clear()
	
	var should_calculate = true
	var reason = ""
	if not entity:
		should_calculate = false
		reason = "No entity"
	elif TurnManager and entity.faction != TurnManager.current_faction:
		should_calculate = false
		reason = "Not unit faction turn"
	elif entity.character_data and entity.character_data.has_moved_this_turn:
		# 如果這回合已經移動過，且不在部署階段，則不顯示移動範圍
		if not TurnManager or TurnManager.current_state != TurnManager.State.DEPLOYMENT:
			# 修改：漫遊模式下忽略已移動限制
			if not TurnManager or not TurnManager.is_free_roam_mode:
				should_calculate = false
				reason = "Unit already moved"
	
	if enable_debug_log:
		var entity_name = str(entity.name) if entity != null else "None"
		print("[GridSelector] _update_reachable_cells for ", entity_name, " should_calculate: ", should_calculate, " reason: ", reason)
	
	if should_calculate and entity.has_method("get_reachable_cells"):
		_reachable_cells = entity.get_reachable_cells()
		
	if not _movement_range_indicator:
		_find_movement_indicator()

	if _movement_range_indicator:
		var entity_name = "null"
		if entity != null:
			entity_name = entity.name
		print("[GridSelector] Calling _show_range_indicator with ", _reachable_cells.size(), " cells for ", entity_name)
		_movement_range_indicator._show_range_indicator(_reachable_cells, entity)
	else:
		print("[GridSelector] ERROR: _movement_range_indicator node NOT FOUND in group 'movement_range_indicator'")

func _update_highlight() -> void:
	if selection_highlight and selected_entity:
		selection_highlight.global_position = grid.grid_to_world_center(selected_entity.grid_position)
		selection_highlight.visible = true
	elif selection_highlight:
		selection_highlight.visible = false

func _start_drag_visuals(_pos: Vector2) -> void:
	if not selected_entity: return
	
	if selected_entity is EquipmentEntity:
		# 切換到裝備分頁 (DisplayState.EQUIPMENT = 2)
		get_tree().call_group("deployment_member_cards", "force_display_state", 2)
		
	_original_sprite = selected_entity.get_node_or_null("Sprite2D")
	if not _original_sprite: return
	
	# 建立 CanvasLayer 確保在所有 UI 之上
	_drag_layer = CanvasLayer.new()
	_drag_layer.layer = 100
	add_child(_drag_layer)
	
	_drag_actor = _original_sprite.duplicate()
	_drag_actor.z_index = 100
	_drag_actor.modulate.a = 0.8
	_drag_actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_actor.scale = Vector2(4, 4) # 縮放以對應 Camera 縮放
	_drag_layer.add_child(_drag_actor)
	
	_ghost_actor = _original_sprite.duplicate()
	_ghost_actor.z_index = 50
	_ghost_actor.modulate.a = 0.4
	_ghost_actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost_actor.visible = false
	add_child(_ghost_actor) # Ghost 留在世界空間
	
	_original_sprite.visible = false
	_oscillator_velocity = 0.0
	_oscillator_displacement = 0.0
	_last_drag_pos = _pos

func _end_drag_visuals() -> void:
	if selected_entity is EquipmentEntity:
		# 恢復原本的分頁
		get_tree().call_group("deployment_member_cards", "restore_pre_drag_state")

	if _drag_layer:
		_drag_layer.queue_free()
		_drag_layer = null
		
	if _drag_actor: _drag_actor = null # 已隨層級清理
	if _ghost_actor: _ghost_actor.queue_free()
	if _original_sprite: _original_sprite.visible = true
	_ghost_actor = null
	
	# 清理 Combo 預覽
	_clear_active_combo_previews()

func _clear_active_combo_previews() -> void:
	for target in _active_combo_targets:
		if is_instance_valid(target) and target.has_method("update_combo_display"):
			target.update_combo_display(0)
	_active_combo_targets.clear()

func _process(delta: float) -> void:
	if _input_state == InputState.DRAGGING and _drag_actor:
		var mouse_pos = get_viewport().get_mouse_position() # 取得螢幕/UI 空間座標
		var world_mouse_pos = get_viewport().get_camera_2d().get_global_mouse_position()
		
		# 更新 CanvasLayer 中的 Sprite 位置 (使用螢幕座標)
		_drag_actor.position = mouse_pos
		
		# Oscillator physics (使用螢幕座標計算抖動)
		var velocity = (mouse_pos - _last_drag_pos) / delta
		_last_drag_pos = mouse_pos
		
		if velocity.length() > 0.0:
			_oscillator_velocity += velocity.normalized().x * VELOCITY_MULTIPLIER
			
		var force = -ROTATION_SPRING * _oscillator_displacement - ROTATION_DAMP * _oscillator_velocity
		_oscillator_velocity += force * delta
		_oscillator_displacement += _oscillator_velocity * delta
		
		if is_instance_valid(_original_sprite):
			_drag_actor.rotation = _original_sprite.rotation + _oscillator_displacement
		else:
			_drag_actor.rotation = _oscillator_displacement
		
		var cell = grid.world_to_grid(world_mouse_pos)
		if cell in _reachable_cells:
			if not _ghost_actor.visible or grid.world_to_grid(_ghost_actor.global_position) != cell:
				# 位置改變，更新 Combo 預覽
				_update_combo_preview(cell)
				
			_ghost_actor.visible = true
			if selected_entity.get("footprint_data"):
				_ghost_actor.global_position = grid.grid_to_world_center_footprint(cell, selected_entity.footprint_data)
			else:
				_ghost_actor.global_position = grid.grid_to_world_center(cell)
		else:
			if _ghost_actor.visible:
				_clear_active_combo_previews()
			_ghost_actor.visible = false

func _update_combo_preview(target_cell: Vector2i) -> void:
	if not AttackManager: return
	
	# 判斷是否會結束回合
	var will_end_turn = true
	if _previewing_skill and _previewing_skill.execution_mode == UnitSkillData.ExecutionMode.MOVEMENT:
		will_end_turn = false
		
	if not will_end_turn:
		_clear_active_combo_previews()
		return
		
	var combo_results = AttackManager.calculate_preview_combos(selected_entity, target_cell)
	
	# 核心優化：不再暴力清除所有預覽，而是進行差異更新
	# 1. 隱藏不再被攻擊的目標
	var targets_to_remove = []
	for old_target in _active_combo_targets:
		if not is_instance_valid(old_target) or not old_target in combo_results:
			if is_instance_valid(old_target) and old_target.has_method("update_combo_display"):
				old_target.update_combo_display(0)
			targets_to_remove.append(old_target)
	
	for t in targets_to_remove:
		_active_combo_targets.erase(t)
	
	# 2. 更新或顯示新目標
	for target in combo_results:
		if is_instance_valid(target) and target.has_method("update_combo_display"):
			target.update_combo_display(combo_results[target])
			_active_combo_targets[target] = combo_results[target]

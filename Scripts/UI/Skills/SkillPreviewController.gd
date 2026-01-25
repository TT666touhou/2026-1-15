extends Node2D
class_name SkillPreviewController

@export var preview_color: Color = Color(1, 0.6, 0.2, 0.4) # 橘色預覽
@export var border_color: Color = Color(1, 0.6, 0.2, 0.8)

var affected_cells: Array[Vector2i] = []
var grid: Node = null

func _ready() -> void:
	add_to_group("skill_preview_controller")
	grid = get_tree().get_first_node_in_group("grid")
	z_index = 50 

## 根據技能與目標點更新預覽
func update_preview(unit: GridEntity, skill: Resource, _target_cell: Vector2i) -> void:
	affected_cells.clear()
	if not skill:
		queue_redraw()
		return
		
	# 根據單位陣營切換顏色
	if unit and unit.faction and not unit.faction.is_controllable:
		preview_color = Color(1, 0.2, 0.2, 0.4) # 紅色預覽 (敵人)
		border_color = Color(1, 0.2, 0.2, 0.8)
	else:
		preview_color = Color(1, 0.6, 0.2, 0.4) # 橘色預覽 (玩家)
		border_color = Color(1, 0.6, 0.2, 0.8)

	var targeting = skill.get("targeting")
	var post_targeting = skill.get("post_move_targeting")
	var targeting_type = skill.get("targeting_type")
	
	# 核心規則：預覽必須與執行引擎同步，強制使用 post_move_targeting 作為效果預覽
	var effective_target = post_targeting if post_targeting != null else targeting
	
	if effective_target == null:
		queue_redraw()
		return

	# 核心修正：在預覽時計算連擊 (Combo)
	_update_combo_previews(unit, skill, effective_target)
	
	if targeting_type == UnitSkillData.TargetingType.ABSOLUTE:
		# 絕對位置：固定在地圖中央
		var origin = SkillManager._get_grid_center()
		affected_cells = SkillManager.get_cells_in_scope(effective_target, origin)
	else:
		# RELATIVE 模式：以單位為中心
		var units_to_preview = []
		if unit:
			units_to_preview.append(unit)
		else:
			# 如果沒傳入單位（例如從手牌拖出時），預覽所有玩家單位的影響範圍
			units_to_preview = get_tree().get_nodes_in_group("player")
			
		for u in units_to_preview:
			if u is GridEntity:
				var origin = u.grid_position
				var cells = SkillManager.get_cells_in_scope(effective_target, origin)
				for c in cells:
					if not affected_cells.has(c):
						affected_cells.append(c)
	
	queue_redraw()

func clear_preview() -> void:
	affected_cells.clear()
	# 清除連擊預覽，恢復顯示當前實際連擊
	if AttackManager:
		AttackManager.global_combo_changed.emit(AttackManager.global_combo_count)
	queue_redraw()

func _update_combo_previews(unit: GridEntity, skill: Resource, _targeting: Resource) -> void:
	if not AttackManager:
		return
		
	# 核心修正：如果 unit 為空（從手牌拖拽卡片時），自動尋找所有玩家單位
	var units_to_check: Array[GridEntity] = []
	if unit:
		units_to_check.append(unit)
	else:
		# 從手牌拖拽時，預覽所有玩家單位的移動後連擊
		var player_units = get_tree().get_nodes_in_group("player")
		for u in player_units:
			if u is GridEntity:
				units_to_check.append(u)
	
	# 檢查是否包含移動效果
	var effects = skill.get("effects")
	var has_move_effect = false
	var move_dir = Vector2i.ZERO
	var move_dist = 0
	
	if effects:
		for effect in effects:
			if effect.effect_type == EffectDefinition.EffectType.MOVE:
				has_move_effect = true
				move_dir = effect.get("move_direction")
				move_dist = int(effect.get("base_value"))
				break
	
	# 計算預覽總連擊數 (當前全局連擊 + 所有單位預覽新增連擊)
	var total_preview_hits = AttackManager.global_combo_count
	
	for u in units_to_check:
		var preview_cell = u.grid_position
		if has_move_effect:
			preview_cell += move_dir * move_dist
		
		var combo_results = AttackManager.calculate_preview_combos(u, preview_cell)
		for target in combo_results:
			total_preview_hits += combo_results[target]
	
	# 更新全局 Combo UI
	AttackManager.global_combo_changed.emit(total_preview_hits)

func _draw() -> void:
	if affected_cells.is_empty() or not grid or not grid.has_method("grid_to_world"):
		return
		
	var cs = Vector2(16, 16)
	if "cell_size" in grid:
		cs = Vector2(grid.cell_size)
		
	for cell in affected_cells:
		var world_pos = grid.grid_to_world(cell)
		var local_pos = to_local(world_pos)
		# print("[SkillPreviewController] Drawing cell %s at world %s -> local %s" % [cell, world_pos, local_pos])
		draw_rect(Rect2(local_pos, cs), preview_color, true)
		draw_rect(Rect2(local_pos, cs), border_color, false, 1.0)

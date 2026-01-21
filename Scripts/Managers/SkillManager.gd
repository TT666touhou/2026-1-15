extends Node

# SkillManager (Autoload)
# 負責處理技能的施放、目標篩選與效果執行

signal skill_cast_started(skill: Resource, source_entity: GridEntity)
signal skill_cast_completed(skill: Resource)
signal skill_cast_failed(reason: String)

func _ready() -> void:
	pass

func _get_grid_center() -> Vector2i:
	var grid = get_tree().get_first_node_in_group("grid")
	if grid:
		return Vector2i(grid.map_width / 2, grid.map_height / 2)
	return Vector2i(0, 0)

## 主要入口：執行技能核心邏輯
func execute_skill(source_entity: GridEntity, skill: Resource, origin_pos: Vector2i) -> bool:
	if skill == null or source_entity == null:
		return false
	
	var skill_name = skill.get("skill_name")
	print("[SkillManager] Executing skill: ", skill_name, " by ", source_entity.name, " at ", origin_pos)
		
	var targeting = skill.get("post_move_targeting")
	var effects = skill.get("effects")
	var post_effects = skill.get("post_move_effects")
	var targeting_type = skill.get("targeting_type")
	
	# 合併所有效果
	var all_effects = []
	if effects: all_effects.append_array(effects)
	if post_effects: all_effects.append_array(post_effects)
	
	# 強制使用 post_move_targeting 作為效果範圍
	if targeting == null:
		print("[SkillManager] Warning: Skill '%s' has no post_move_targeting. Falling back to base targeting." % skill_name)
		targeting = skill.get("targeting")
	
	if targeting == null:
		targeting = TargetingDefinition.new()
		targeting.scope_type = TargetingDefinition.ScopeType.SINGLE
		targeting.origin_is_self = false
		targeting.target_filter = TargetingDefinition.TargetFilter.ENEMY
	
	# 如果是絕對位置技能，中心點改為地圖中央
	var actual_origin = origin_pos
	if targeting_type == UnitSkillData.TargetingType.ABSOLUTE:
		actual_origin = _get_grid_center()
		print("[SkillManager] Absolute skill detected, origin centered to: ", actual_origin)
	
	# 1. 獲取並驗證目標
	var valid_targets = get_valid_targets(targeting, actual_origin, source_entity)
	
	# 2. 計算縮放係數
	var total_stat_value = 0.0
	var scaling_multiplier = skill.get("scaling_multiplier")
	if scaling_multiplier == null: scaling_multiplier = 1.0
	
	var scaling_configs = skill.get("scaling_configs")
	if scaling_configs == null or scaling_configs.is_empty():
		total_stat_value = 1.0
	else:
		total_stat_value = _get_weighted_stat_sum(source_entity, scaling_configs)
			
	var final_multiplier = scaling_multiplier * total_stat_value
	
	# 3. 執行效果
	skill_cast_started.emit(skill, source_entity)
	if valid_targets.is_empty() and not targeting.get("can_target_empty"):
		skill_cast_failed.emit("No valid targets")
		# 這裡仍然回傳 true，因為技能已經嘗試執行並進入 CD
	
	for target in valid_targets:
		# 命中判定 (除非技能標記為必中 is_accurate)
		var is_accurate = bool(skill.get("is_accurate")) if "is_accurate" in skill else false
		if not is_accurate and AttackManager.has_method("check_hit"):
			if not AttackManager.check_hit(source_entity, target):
				if target.has_method("show_avoid_text"):
					target.show_avoid_text()
				continue # 沒打中，跳過此目標的所有效果
		
		# 暴擊判定 (技能現在也可以暴擊)
		var current_target_multiplier = final_multiplier
		if source_entity.character_data:
			var crit_rate = source_entity.character_data.crit_rate
			if randf() < crit_rate:
				var extra_crit = source_entity.character_data.get_effective_crit_dmg()
				var crit_bonus = 2.0 + extra_crit
				current_target_multiplier *= crit_bonus
				print("[SkillManager] CRITICAL HIT on %s! Bonus: %.2f" % [target.name, crit_bonus])
		
		for effect in all_effects:
			_apply_single_effect(effect, target, source_entity, current_target_multiplier)
			
	# 4. 設置冷卻與標記
	if source_entity.character_data:
		var cd = skill.get("cooldown_turns")
		if cd != null and cd > 0:
			source_entity.character_data.set_skill_cooldown(skill.get("skill_name"), cd)
		source_entity.character_data.has_used_skill_this_turn = true
		
	skill_cast_completed.emit(skill)
	return true

func _get_weighted_stat_sum(source_entity: GridEntity, configs: Array) -> float:
	var total = 0.0
	if not source_entity.character_data:
		return 1.0 # Fallback
		
	for config in configs:
		var stat_name = config.get("stat", "attack")
		var weight = config.get("weight", 1.0)
		var val = 0.0
		match stat_name:
			"attack", "str", "dex", "int", "pie": val = source_entity.character_data.get_effective_attack()
			"hp": val = source_entity.character_data.get_effective_max_health()
			"luck": val = source_entity.character_data.luck
			_: val = 1.0
		total += val * weight
	return total

## 獲取有效目標列表
func get_valid_targets(targeting_data: Resource, center_cell: Vector2i, source: GridEntity) -> Array[GridEntity]:
	var targets: Array[GridEntity] = []
	var grid = get_tree().get_first_node_in_group("grid")
	if not grid: return targets
	
	var actual_center = center_cell
	if targeting_data.get("origin_is_self") and source:
		actual_center = source.grid_position
	
	var cells_in_scope = get_cells_in_scope(targeting_data, actual_center)
	
	for cell in cells_in_scope:
		var occupant = grid.get_occupant(cell) as GridEntity
		if occupant:
			if is_target_valid(occupant, targeting_data.get("target_filter"), source):
				targets.append(occupant)
				
	return targets

## 獲取受影響的格子 (預覽用)
func get_cells_in_scope(targeting_data: Resource, center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var grid = get_tree().get_first_node_in_group("grid")
	if not grid or not targeting_data:
		return cells
		
	var scope_type = targeting_data.get("scope_type")
	var radius = targeting_data.get("aoe_radius")
	if radius == null: radius = 0
	
	match scope_type:
		TargetingDefinition.ScopeType.SINGLE:
			cells.append(center)
		TargetingDefinition.ScopeType.AREA_CIRCLE:
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					if abs(x) + abs(y) <= radius:
						cells.append(center + Vector2i(x, y))
		TargetingDefinition.ScopeType.AREA_SQUARE:
			for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
					cells.append(center + Vector2i(x, y))
		TargetingDefinition.ScopeType.AREA_CROSS:
			cells.append(center)
			for i in range(1, radius + 1):
				cells.append(center + Vector2i(i, 0))
				cells.append(center + Vector2i(-i, 0))
				cells.append(center + Vector2i(0, i))
				cells.append(center + Vector2i(0, -i))
		TargetingDefinition.ScopeType.AREA_X:
			cells.append(center)
			for i in range(1, radius + 1):
				cells.append(center + Vector2i(i, i))
				cells.append(center + Vector2i(-i, -i))
				cells.append(center + Vector2i(i, -i))
				cells.append(center + Vector2i(-i, i))
		TargetingDefinition.ScopeType.AREA_QUEEN:
			cells.append(center)
			for i in range(1, radius + 1):
				cells.append(center + Vector2i(i, 0))
				cells.append(center + Vector2i(-i, 0))
				cells.append(center + Vector2i(0, i))
				cells.append(center + Vector2i(0, -i))
				cells.append(center + Vector2i(i, i))
				cells.append(center + Vector2i(-i, -i))
				cells.append(center + Vector2i(i, -i))
				cells.append(center + Vector2i(-i, i))
		TargetingDefinition.ScopeType.AREA_PATTERN:
			var p11x9 = targeting_data.get("pattern_11x9")
			if p11x9 and p11x9.size() == 99:
				for i in range(99):
					if p11x9[i]:
						var dx = (i % 11) - 5
						var dy: int = int(floor(i / 11.0)) - 4
						cells.append(center + Vector2i(dx, dy))
			else:
				var pattern = targeting_data.get("pattern_7x7")
				if pattern and pattern.size() == 49:
					for i in range(49):
						if pattern[i]:
							var dx = (i % 7) - 3
							var dy: int = int(floor(i / 7.0)) - 3
							cells.append(center + Vector2i(dx, dy))
		TargetingDefinition.ScopeType.GLOBAL:
			for x in range(grid.map_width):
				for y in range(grid.map_height):
					cells.append(Vector2i(x, y))
		TargetingDefinition.ScopeType.GLOBAL_CHECKER_A:
			for x in range(grid.map_width):
				for y in range(grid.map_height):
					if (x + y) % 2 == 0:
						cells.append(Vector2i(x, y))
		TargetingDefinition.ScopeType.GLOBAL_CHECKER_B:
			for x in range(grid.map_width):
				for y in range(grid.map_height):
					if (x + y) % 2 != 0:
						cells.append(Vector2i(x, y))
						
	# 過濾掉不在地圖範圍內的格子
	var valid_cells: Array[Vector2i] = []
	for c in cells:
		if grid.is_in_bounds(c):
			valid_cells.append(c)
			
	return valid_cells

## 內部：驗證目標是否符合 Filter
func is_target_valid(target: GridEntity, filter: int, source: GridEntity) -> bool:
	var source_faction = source.faction if source != null else null
	if not target.faction or not source_faction: 
		return true
	
	match filter:
		TargetingDefinition.TargetFilter.ALLY:
			return target.faction == source_faction
		TargetingDefinition.TargetFilter.ENEMY:
			return target.faction != source_faction
		TargetingDefinition.TargetFilter.ALL:
			return true
		TargetingDefinition.TargetFilter.SELF:
			return target == source
			
	return false

## 內部：執行單一效果
func _apply_single_effect(effect: EffectDefinition, target: GridEntity, source: GridEntity, final_multiplier: float) -> void:
	if not target.character_data: return
	
	var base_val = effect.get("base_value")
	if base_val == null: base_val = 1.0
	
	# 處理 ValueCalculation (數值來源)
	var calculation_mode = effect.get("value_calculation")
	var calculated_base = base_val
	
	match calculation_mode:
		EffectDefinition.ValueCalculation.PERCENT_TARGET_ATK:
			calculated_base = base_val * target.character_data.get_effective_attack()
		EffectDefinition.ValueCalculation.PERCENT_TARGET_HP:
			calculated_base = base_val * target.character_data.get_effective_max_health()
		EffectDefinition.ValueCalculation.PERCENT_TARGET_LOST_HP:
			var lost_hp = target.character_data.get_effective_max_health() - target.character_data.current_health
			calculated_base = base_val * lost_hp
		EffectDefinition.ValueCalculation.PERCENT_CASTER_ATK:
			if source and source.character_data:
				calculated_base = base_val * source.character_data.get_effective_attack()
		EffectDefinition.ValueCalculation.POKER_POINTS:
			# 暫位符：目前假設 POKER_POINTS 由外部 final_multiplier 處理
			pass
		_:
			# FIXED 模式
			calculated_base = base_val
			
	var value = calculated_base * final_multiplier
	
	match effect.effect_type:
		EffectDefinition.EffectType.DAMAGE:
			var ignore_b = bool(effect.get("ignore_barrier")) if "ignore_barrier" in effect else false
			var ignore_s = bool(effect.get("ignore_shield")) if "ignore_shield" in effect else false
			
			# 傳入 source (發動者) 以套用貫穿 (Penetration) 效果
			var actual_damage = target.apply_damage(int(value), ignore_b, ignore_s, source)
			
			# 觸發吸血 (Drain)
			if actual_damage > 0 and source and source.character_data:
				var drain_rate = source.character_data.get_effective_drain()
				if drain_rate > 0:
					var heal_amount = int(actual_damage * drain_rate)
					if heal_amount > 0:
						source.character_data.heal(heal_amount)
						if source.has_method("show_heal_number"):
							source.show_heal_number(heal_amount)
							
		EffectDefinition.EffectType.HEAL:
			target.heal(int(value))
		EffectDefinition.EffectType.ADD_STATUS:
			var status_mgr = target.get_node_or_null("StatusManager")
			if status_mgr:
				status_mgr.apply_status(effect.status_to_apply)

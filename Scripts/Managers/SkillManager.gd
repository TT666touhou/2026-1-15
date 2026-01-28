# FIXED VERSION - ENSURE AWAIT IS USED
extends Node

# SkillManager (Autoload)
# 負責處理技能的施放、目標篩選與效果執行

signal skill_cast_started(skill: Resource, source_entity: GridEntity)
signal skill_cast_completed(skill: Resource)

func _ready() -> void:
	pass

func _get_grid_center() -> Vector2i:
	var grid = get_tree().get_first_node_in_group("grid")
	if grid:
		return Vector2i(grid.map_width / 2, grid.map_height / 2)
	return Vector2i(0, 0)

## 已移除：cast_skill 方法（grid-based 卡片技能系統已刪除）
## 現在只使用 execute_skill 進行距離觸發技能

## 主要入口：執行技能核心邏輯
func execute_skill(source_entity: GridEntity, skill: Resource, origin_pos: Vector2i) -> bool:
	if skill == null or source_entity == null:
		return false
	
	var skill_name = skill.get("skill_name")
	if skill_name == null: skill_name = "Unknown"
	
	print("[SkillManager] execute_skill: ", skill_name, " | Source: ", source_entity.name)
	
	# 特殊技能處理：十字箭矢 (Cross Arrow)
	# 使用更健壯的匹配方式
	if skill_name.contains("十字箭矢") or skill_name.to_lower().contains("cross arrow"):
		_fire_cross_arrows(source_entity)
		skill_cast_completed.emit(skill)
		return true
	
	# 特殊技能處理：迴旋飛斧 (Whirlwind Axe)
	if skill_name.contains("迴旋飛斧") or skill_name.to_lower().contains("whirlwind axe"):
		call_deferred("_fire_whirlwind_axes", source_entity)
		skill_cast_completed.emit(skill)
		return true
		
	# 特殊技能處理：連鎖閃電 (Lightning Chain)
	if skill_name.contains("連鎖閃電") or skill_name.to_lower().contains("lightning chain"):
		# 連鎖閃電通常由 GridEntity 碰撞觸發，這裡僅作為佔位
		skill_cast_completed.emit(skill)
		return true
		
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
	
	if valid_targets.is_empty():
		return false

	# 2. 計算縮放係數與連擊加成 (Snapshot)
	var total_stat_value = 0.0
	var scaling_multiplier = skill.get("scaling_multiplier")
	if scaling_multiplier == null: scaling_multiplier = 1.0
	
	var scaling_configs = skill.get("scaling_configs")
	if scaling_configs == null or scaling_configs.is_empty():
		total_stat_value = 1.0
	else:
		total_stat_value = _get_weighted_stat_sum(source_entity, scaling_configs)
			
	# 核心修正：在技能開始時快照連擊倍率，確保整個技能執行期間數值一致
	var combo_mult = 1.0
	if AttackManager:
		var scaling = 0.1
		if source_entity.character_data:
			scaling = source_entity.character_data.combo_damage_scaling
		combo_mult = AttackManager.get_combo_damage_multiplier(scaling)
	
	var final_multiplier = scaling_multiplier * total_stat_value * combo_mult
	
	# 3. 執行效果
	skill_cast_started.emit(skill, source_entity)
	
	# 新增：如果是敵人施放，對所有受影響的格子（不含中心）播放爆炸特效
	var is_enemy_cast = false
	if source_entity.faction:
		is_enemy_cast = source_entity.faction.resource_path.to_lower().contains("enemy")
	else:
		is_enemy_cast = source_entity.is_in_group("enemy")
		
	if is_enemy_cast:
		var cells_in_scope = get_cells_in_scope(targeting, actual_origin)
		var fx_cells = cells_in_scope.filter(func(c): return c != actual_origin)
		_play_skill_explosion_fx(fx_cells)
		
		# 新增：施法者自身的壓縮放大動畫
		var visuals = source_entity.get_node_or_null("UnitVisuals")
		if visuals and visuals.has_method("play_skill_cast_visual"):
			visuals.play_skill_cast_visual()
	
	# 核心修正：將效果分為「針對發動者」與「針對目標」
	var self_effects = []
	var target_effects = []
	for effect in all_effects:
		if effect.effect_type == EffectDefinition.EffectType.MOVE:
			self_effects.append(effect)
		else:
			target_effects.append(effect)
	
	# A. 執行發動者效果 (僅執行一次)
	# 這裡傳入快照後的 final_multiplier (已包含 combo_mult)
	for effect in self_effects:
		_apply_single_effect(effect, source_entity, source_entity, final_multiplier)
	
	# B. 執行目標效果 (遍歷所有有效目標)
	if valid_targets.is_empty() and not targeting.get("can_target_empty"):
		# 如果沒有目標且不允許空放，則不執行後續
		pass
	else:
		for target in valid_targets:
			# 命中判定 (除非技能標記為必中 is_accurate)
			var is_accurate = bool(skill.get("is_accurate")) if "is_accurate" in skill else false
			if not is_accurate and AttackManager.has_method("check_hit"):
				if not AttackManager.check_hit(source_entity, target):
					if target.has_method("show_avoid_text"):
						target.show_avoid_text()
					continue # 沒打中，跳過此目標的所有效果
			
			# 暴擊判定 (技能現在也可以暴擊)
			# 核心修正：技能傷害現在統一透過 AttackManager.resolve_combat 結算
			# 這裡只需調用 target.apply_damage，它內部會調用 AttackManager
			for effect in target_effects:
				_apply_single_effect(effect, target, source_entity, final_multiplier)
			
	# 4. 設置冷卻與標記
	if source_entity.character_data:
		var cd = skill.get("cooldown_turns")
		if cd != null and cd > 0:
			source_entity.character_data.set_skill_cooldown(skill.get("skill_name"), cd)
		source_entity.character_data.has_used_skill_this_turn = true
		
	# 增加演出等待時間 (例如等待爆炸特效播放完畢)
	await get_tree().create_timer(0.5).timeout
		
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
			"luck": val = float(source_entity.character_data.get_effective_luck())
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
		# print("[SkillManager] get_cells_in_scope failed: grid or targeting_data is null")
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
			# 不包含中心格 (敵人自身)
			for i in range(1, radius + 1):
				cells.append(center + Vector2i(i, 0))
				cells.append(center + Vector2i(-i, 0))
				cells.append(center + Vector2i(0, i))
				cells.append(center + Vector2i(0, -i))
		9, 14: # 兼容 AREA_X 的不同索引 (可能因 Godot 緩存或版本差異)
			# 不包含中心格 (敵人自身)
			for i in range(1, radius + 1):
				cells.append(center + Vector2i(i, i))
				cells.append(center + Vector2i(-i, -i))
				cells.append(center + Vector2i(i, -i))
				cells.append(center + Vector2i(-i, i))
		TargetingDefinition.ScopeType.AREA_QUEEN:
			# 不包含中心格 (敵人自身)
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
		_:
			print("[SkillManager] Warning: Unknown scope type: ", scope_type)
						
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
			# 核心修正：技能傷害現在統一透過 AttackManager 結算
			# 傳入 is_skill = true 以便 AttackManager 識別
			var base_dmg = int(round(value))
			target.apply_damage(base_dmg, false, false, source, false)
			
		EffectDefinition.EffectType.HEAL:
			target.heal(int(value))
		EffectDefinition.EffectType.ADD_STATUS:
			var status_mgr = target.get_node_or_null("StatusManager")
			if status_mgr:
				status_mgr.apply_status(effect.status_to_apply)
		EffectDefinition.EffectType.MOVE:
			var mover = target.get_node_or_null("GridMover")
			if mover:
				var move_dir = effect.get("move_direction")
				var dist = int(value)
				if dist > 0:
					var final_target = target.grid_position
					
					var grid = get_tree().get_first_node_in_group("grid")
					if grid:
						# 逐步偵測碰撞
						for i in range(1, dist + 1):
							var next_cell = target.grid_position + (move_dir * i)
							
							# 1. 邊界檢查
							if not grid.is_in_bounds(next_cell):
								break
								
							# 2. 實體佔用檢查（簡化：遇到障礙物直接停止）
							var occupant = grid.get_occupant(next_cell)
							if occupant and occupant != target:
								# 遇到障礙物，停止移動
								break
							
							# 格子可通行，更新落點
							final_target = next_cell
					
					# 執行最終位移 (此時路徑已確保無障礙)
					await mover.move_to(final_target)

func _play_skill_explosion_fx(cells: Array[Vector2i]) -> void:
	var grid = get_tree().get_first_node_in_group("grid")
	if not grid: 
		return

	for cell in cells:
		var world_pos = grid.grid_to_world_center(cell)
		_spawn_shard_explosion(world_pos)

func _spawn_shard_explosion(pos: Vector2) -> void:
	var particles = GPUParticles2D.new()
	particles.name = "SkillExplosionFX"
	
	# 載入資源 (暫時改用已確認可見的 Landing 材質進行交叉測試)
	var mat_res = load("res://Resources/Shared/LandingExplosionProcess.tres")
	var tex_res = load("res://Resources/Shared/RetroSquare.tres")
	
	if not mat_res or not tex_res:
		return
		
	particles.process_material = mat_res.duplicate()
	particles.texture = tex_res
	
	# 基礎配置
	particles.amount = 32
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.z_index = 200 # 提高層級
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.local_coords = false
	
	# 加入場景並啟動
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(particles)
		particles.global_position = pos
		particles.restart() # 使用 restart 確保發射
		
		# 自動清理
		get_tree().create_timer(1.2).timeout.connect(func():
			if is_instance_valid(particles):
				particles.queue_free()
		)

func _fire_cross_arrows(caster: GridEntity) -> void:
	var map_loader = get_tree().get_first_node_in_group("map_loader")
	if not map_loader: return
	
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	var arrow_scene = load("res://Scenes/Shared/ArrowProjectile.tscn")
	
	for dir in directions:
		map_loader.spawn_projectile(arrow_scene, caster, dir, {"speed": 100.0})

func _fire_whirlwind_axes(caster: GridEntity) -> void:
	var map_loader = get_tree().get_first_node_in_group("map_loader")
	if not map_loader: return
	
	var axe_scene = load("res://Scenes/Shared/AxeProjectile.tscn")
	
	# 尋找場上所有敵人
	var all_entities = get_tree().get_nodes_in_group("grid_entities")
	var target_enemies = []
	var is_caster_player = caster.is_in_group("player")
	
	for entity in all_entities:
		if entity is GridEntity and entity != caster:
			var is_target_player = entity.is_in_group("player")
			if is_caster_player != is_target_player:
				if not target_enemies.has(entity):
					target_enemies.append(entity)
	
	print("[SkillManager] Firing whirlwind axes for ", caster.name, " | Targets found: ", target_enemies.size())
	
	for enemy in target_enemies:
		var target_dir = (enemy.global_position - caster.global_position).normalized()
		if target_dir == Vector2.ZERO: target_dir = Vector2.RIGHT
		
		# 傷害倍率 50%
		var dmg = int((caster.character_data.get_effective_attack() if caster.character_data else 10) * 0.5)
		map_loader.spawn_projectile(axe_scene, caster, target_dir, {"speed": 400.0, "damage": dmg})

func create_lightning_chain(caster: GridEntity, target: GridEntity, damage: int) -> void:
	var lightning_scene = load("res://Scenes/Shared/LightningChain.tscn")
	if not lightning_scene: return
	
	var lightning = lightning_scene.instantiate()
	get_tree().current_scene.add_child(lightning)
	
	if lightning.has_method("setup"):
		lightning.setup(caster, target, damage, 2.0)
		print("[SkillManager] Lightning chain created between ", caster.name, " and ", target.name)

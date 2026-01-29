extends "res://Scripts/Entities/EnemyAttackComponent.gd"

## Enemy 003: Slime - 【分裂攻擊】
## 消耗 50% 當前生命值，向最近玩家發射一個分身

func perform_attack() -> void:
	var target = _get_nearest_player()
	if not target:
		await get_tree().process_frame
		return

	# 1. 播放發動演出
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_skill_cast_visual"):
		visuals.play_skill_cast_visual()
		await get_tree().create_timer(0.2).timeout

	# 2. 消耗生命值 (50% 當前血量)
	if parent_entity.character_data:
		var current_hp = parent_entity.character_data.current_health
		var damage_taken = floor(current_hp * 0.5)
		# 確保至少扣 1 點血，除非已經沒血
		if damage_taken < 1.0 and current_hp > 0:
			damage_taken = 1.0
		
		parent_entity.character_data.take_damage(damage_taken)
		print("[EnemyAttack_Slime] Splitting! Parent takes ", damage_taken, " damage. Remaining: ", parent_entity.character_data.current_health)

		# 3. 視覺效果：分裂變形與粒子
		_play_split_visuals()

		# 4. 準備分身資源與數據
		var slime_scene = load("res://Scenes/Entities/Enemy/Enemy003.tscn")
		var card = load("res://Resources/Cards/Enemy_003.tres")
		
		# 5. 計算發射方向
		var target_pos = target.global_position
		var dir = (target_pos - parent_entity.global_position).normalized()
		if dir == Vector2.ZERO: dir = Vector2.RIGHT
		
		# 6. 使用 MapLoader 統一生成 API
		var map_loader = get_tree().get_first_node_in_group("map_loader")
		if not map_loader:
			print("[EnemyAttack_Slime] ERROR: MapLoader not found!")
			return
			
		var clone = map_loader.spawn_entity(slime_scene, card, parent_entity.grid_position, "enemy", {}, true)
		
		if clone:
			# 核心修正：將分身的實際位置稍微推離母體，避免物理重疊擠壓導致瞄準失效
			clone.global_position = parent_entity.global_position + (dir * 12.0)
			
			# 核心修正：分裂時解鎖母體與分身的物理狀態
			if parent_entity.has_method("unlock_physics"):
				parent_entity.unlock_physics()
			if clone.has_method("unlock_physics"):
				clone.unlock_physics()

			# 設置生命值為本體扣除的量
			if clone.character_data:
				clone.character_data.max_health = int(damage_taken)
				clone.character_data.current_health = int(damage_taken)
			
			# 分身保留分裂能力
			var attack_comp = clone.get_node_or_null("AttackComponent")
			if attack_comp:
				attack_comp.set_script(load("res://Scripts/Entities/EnemyAttack_Slime.gd"))
			
			# 7. 發射分身
			var launch_force = dir * 600.0
			
			# 核心修正：延遲一幀執行衝量，並在發射前清除因重疊產生的隨機初速度
			await get_tree().physics_frame
			if is_instance_valid(clone):
				clone.linear_velocity = Vector2.ZERO 
				clone.apply_central_impulse(launch_force)
				
				if TurnManager and TurnManager.has_method("on_unit_launched"):
					TurnManager.on_unit_launched(clone, launch_force)
				
				print("[EnemyAttack_Slime] Clone launched towards ", target.name, " with direction ", dir)

	await get_tree().create_timer(0.3).timeout

func _play_split_visuals() -> void:
	# 擠壓變形
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.sprite:
		var original_scale = visuals.sprite.scale
		var tween = create_tween()
		tween.tween_property(visuals.sprite, "scale", original_scale * Vector2(1.5, 0.5), 0.1).set_trans(Tween.TRANS_SINE)
		tween.tween_property(visuals.sprite, "scale", original_scale, 0.2).set_trans(Tween.TRANS_BACK)

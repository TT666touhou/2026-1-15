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
		
		# 5. 使用 MapLoader 統一生成 API (自動處理物理、群組、UI 偵測)
		# 設置 is_dynamic = true 確保外觀立即顯示
		var map_loader = get_tree().get_first_node_in_group("map_loader")
		if not map_loader:
			print("[EnemyAttack_Slime] ERROR: MapLoader not found!")
			return
			
		var clone = map_loader.spawn_entity(slime_scene, card, parent_entity.grid_position, "enemy", {}, true)
		
		if clone:
			# 設置生命值為本體扣除的量
			if clone.character_data:
				clone.character_data.max_health = int(damage_taken)
				clone.character_data.current_health = int(damage_taken)
			
			# 分身保留分裂能力，實現無限分裂（直到血量不足）
			var attack_comp = clone.get_node_or_null("AttackComponent")
			if attack_comp:
				attack_comp.set_script(load("res://Scripts/Entities/EnemyAttack_Slime.gd"))
				print("[EnemyAttack_Slime] Clone inherited Splitting ability")
			
			# 6. 發射分身
			var target_pos = target.global_position
			var dir = (target_pos - parent_entity.global_position).normalized()
			var launch_force = dir * 600.0
			
			clone.apply_central_impulse(launch_force)
			
			if TurnManager and TurnManager.has_method("on_unit_launched"):
				TurnManager.on_unit_launched(clone, launch_force)
			
			print("[EnemyAttack_Slime] Clone launched towards ", target.name)

	await get_tree().create_timer(0.3).timeout

func _play_split_visuals() -> void:
	# 擠壓變形
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.sprite:
		var tween = create_tween()
		tween.tween_property(visuals.sprite, "scale", Vector2(1.5, 0.5), 0.1).set_trans(Tween.TRANS_SINE)
		tween.tween_property(visuals.sprite, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BACK)
	
	# 噴濺粒子
	var particles = GPUParticles2D.new()
	get_tree().current_scene.add_child(particles)
	particles.global_position = parent_entity.global_position
	
	var mat = ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.gravity = Vector3(0, 400, 0)
	mat.initial_velocity_min = 80.0
	mat.initial_velocity_max = 150.0
	mat.scale_min = 2.0
	mat.scale_max = 5.0
	mat.color = Color(0.3, 0.9, 0.3, 0.8)
	
	particles.process_material = mat
	particles.amount = 24
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = 0.5
	# 嘗試加載現有粒子貼圖
	var tex = load("res://Resources/Shared/ParticlePixel.tres")
	if tex:
		particles.texture = tex
	
	particles.emitting = true
	get_tree().create_timer(0.6).timeout.connect(particles.queue_free)

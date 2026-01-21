extends Button

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	print("[DEBUG] Killing all enemies and triggering transition...")
	
	if not BoardManager:
		print("[DEBUG] ERROR: BoardManager not found!")
		return

	# 1. 獲取所有敵方單位並消滅它們
	var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
	if not enemy_faction:
		print("[DEBUG] ERROR: Could not load Faction_Enemy.tres")
		return
		
	print("[DEBUG] Target faction: ", enemy_faction.faction_name, " (", enemy_faction.get_instance_id(), ")")

	# 列出 BoardManager 中所有的實體來檢查
	var all_entities = BoardManager.get_all_entities()
	print("[DEBUG] Total entities in BoardManager: ", all_entities.size())
	
	var kill_count = 0
	for entity in all_entities:
		if not is_instance_valid(entity): continue
		
		var ent_faction = entity.faction
		var faction_name = str(ent_faction.faction_name) if ent_faction != null else "NONE"
		var faction_id = ent_faction.get_instance_id() if ent_faction else 0
		
		print("[DEBUG] Checking entity: ", entity.name, " | Faction: ", faction_name, " (", faction_id, ")")
		
		# 這裡做更寬鬆的判定：名稱包含 "Enemy" 或是實例 ID 相同
		var is_enemy = false
		if ent_faction == enemy_faction:
			is_enemy = true
		elif faction_name.to_lower().contains("enemy"):
			is_enemy = true
			
		if is_enemy:
			print("[DEBUG] -> Killing enemy: ", entity.name)
			if entity.character_data:
				entity.character_data.barriers = 0
				entity.character_data.shield = 0
				entity.character_data.current_health = 0
				entity.character_data.health_changed.emit(0, entity.character_data.get_effective_max_health())
				entity.character_data.stats_changed.emit()
				entity.character_data.died.emit()
			elif entity.has_method("take_damage"):
				# 注意：take_damage 可能是非同步的
				var do_kill = func(): await entity.take_damage(9999, true, true)
				do_kill.call()
			else:
				# 最後手段：直接 queue_free 並從 BoardManager 移除
				entity.queue_free()
			kill_count += 1

	print("[DEBUG] Kill process complete. Killed: ", kill_count)
	
	# 2. 觸發動畫
	if DungeonManager:
		print("[DEBUG] Triggering transition via DungeonManager...")
		# 稍微等待死亡動畫
		await get_tree().create_timer(0.5).timeout
		DungeonManager.debug_test_gate_transition()
	else:
		print("[DEBUG] ERROR: DungeonManager not found!")

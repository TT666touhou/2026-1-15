extends "res://Scripts/Entities/EnemyAttackComponent.gd"

## Enemy 005: Lich - 【靈魂彈】
## 向隨機玩家單位發射一顆靈魂子彈

var _projectile_scene = preload("res://Scenes/Shared/EnemyProjectile.tscn")

func perform_attack() -> void:
	# 1. 播放發動演出
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_skill_cast_visual"):
		visuals.play_skill_cast_visual()
		await get_tree().create_timer(0.2).timeout

	# 2. 尋找目標
	var players = _get_all_players()
	if players.is_empty():
		await get_tree().process_frame
		return
	
	# 隨機挑選一個玩家
	var target = players.pick_random()
	
	if target is GridEntity:
		# 3. 使用 MapLoader 統一生成 API
		var map_loader = get_tree().get_first_node_in_group("map_loader")
		if not map_loader: return
		
		var dir = (target.global_position - parent_entity.global_position).normalized()
		var dmg = parent_entity.character_data.get_effective_attack() if parent_entity.character_data else 10
		
		# 巫妖的子彈使用魔球貼圖，速度稍慢但有追蹤感
		map_loader.spawn_projectile(_projectile_scene, parent_entity, dir, {
			"speed": 200.0,
			"damage": dmg,
			"texture": load("res://Tilesheet/1bit_assetpack/1bit_assetpack/items/offhand_magicorb.png")
		})
		
		print("[EnemyAttack_Lich] Coin Bolt launched towards ", target.name)
		
	# 給予一點點等待時間讓玩家看清
	await get_tree().create_timer(0.4).timeout

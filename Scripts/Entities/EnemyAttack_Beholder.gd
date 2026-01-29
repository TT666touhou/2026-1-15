extends "res://Scripts/Entities/EnemyAttackComponent.gd"

## Enemy 002: Beholder - 【反射雷射】
## 直接向最近的玩家發射反射雷射，穿透單位並反彈牆壁

@export var damage: int = 40

func perform_attack() -> void:
	# 1. 播放發動演出
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_skill_cast_visual"):
		visuals.play_skill_cast_visual()
		await get_tree().create_timer(0.2).timeout

	# 2. 尋找目標玩家
	var target = _get_nearest_player()
	if not target: return
	
	# 3. 直接發射雷射
	_fire_laser(target.global_position)

func _fire_laser(target_pos: Vector2) -> void:
	# 視覺演出：眼睛發光
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.sprite:
		var tween_flash = create_tween()
		visuals.sprite.self_modulate = Color(5, 2, 5) # HDR 發光
		tween_flash.tween_property(visuals.sprite, "self_modulate", Color.WHITE, 0.5)
	
	# 生成反射雷射投射物
	var laser_scene = load("res://Scenes/Shared/BeholderLaser.tscn")
	if laser_scene:
		var laser = laser_scene.instantiate()
		var eye_pos = parent_entity.global_position + Vector2(0, -8)
		var dir = (target_pos - eye_pos).normalized()
		
		# 核心修正：雷射傷害與自身攻擊力掛鉤 (100%)
		var final_damage = damage
		if parent_entity.character_data:
			final_damage = int(parent_entity.character_data.get_effective_attack())
		
		get_tree().current_scene.add_child(laser)
		laser.setup(eye_pos, dir, final_damage, parent_entity)
		print("[EnemyAttack] Beholder firing direct bouncing laser at target | Damage: ", final_damage)

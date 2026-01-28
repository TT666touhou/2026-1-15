extends "res://Scripts/Entities/EnemyAttackComponent.gd"

## Enemy 001: Skeleton - 【骨刺突擊】
## 向最近的玩家單位進行短距離物理衝鋒

@export var impulse_force: float = 400.0

func perform_attack() -> void:
	var target = _get_nearest_player()
	if not target: return
	
	# 1. 播放發動演出
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_skill_cast_visual"):
		visuals.play_skill_cast_visual()
		await get_tree().create_timer(0.2).timeout
	
	# 2. 播放攻擊預告動畫 (不使用 Tween 動畫，改為直接衝鋒)
	var dir = (target.global_position - parent_entity.global_position).normalized()
	
	# 3. 施加衝力
	parent_entity.apply_central_impulse(dir * impulse_force)
	
	# 4. 標記 TurnManager 進入物理監控
	if TurnManager:
		TurnManager.on_unit_launched(parent_entity, dir * impulse_force)
	
	# 等待衝鋒開始
	await get_tree().process_frame
	
	print("[EnemyAttack] Skeleton charging towards ", target.name)

extends "res://Scripts/Entities/EnemyAttackComponent.gd"

## Enemy 002: Beholder - 【凝視射線】
## 每回合鎖定玩家生成預警圈，下一回合觸發傷害

@export var damage: int = 40
var _current_warning: Control = null
var _target_cell: Vector2i = Vector2i(-1, -1)

func perform_attack() -> void:
	# 1. 播放發動演出
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_skill_cast_visual"):
		visuals.play_skill_cast_visual()
		await get_tree().create_timer(0.2).timeout

	# 2. 如果已有預警，則觸發射線傷害
	if _current_warning and is_instance_valid(_current_warning):
		await _fire_ray()
		return
	
	# 2. 否則，尋找新目標並生成預警
	var target = _get_nearest_player()
	if not target: return
	
	_target_cell = target.grid_position
	await _spawn_warning(target.global_position)

func _spawn_warning(pos: Vector2) -> void:
	var scene = load("res://Scenes/Shared/WarningZone.tscn")
	if not scene: return
	
	_current_warning = scene.instantiate()
	get_tree().current_scene.add_child(_current_warning)
	_current_warning.global_position = pos
	
	# 視覺效果：閃爍
	var tween = create_tween().set_loops(3) # 閃爍三次
	tween.tween_property(_current_warning, "modulate:a", 0.3, 0.2)
	tween.tween_property(_current_warning, "modulate:a", 1.0, 0.2)
	
	await tween.finished
	print("[EnemyAttack] Beholder locking target at ", pos)

func _fire_ray() -> void:
	if not _current_warning: return
	
	# 視覺演出：射線 (Line2D)
	var line = Line2D.new()
	get_tree().current_scene.add_child(line)
	line.width = 10.0
	line.default_color = Color(0.8, 0.2, 1.0, 1.0)
	
	# 起點對齊眼睛 (向上偏移 8 像素)
	var eye_pos = parent_entity.global_position + Vector2(0, -8)
	line.add_point(eye_pos)
	line.add_point(_current_warning.global_position)
	
	# 眼睛發光效果
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.sprite:
		var tween_flash = create_tween()
		visuals.sprite.self_modulate = Color(5, 2, 5) # HDR 發光
		tween_flash.tween_property(visuals.sprite, "self_modulate", Color.WHITE, 0.5)
	
	# 傷害判定
	var grid = get_tree().get_first_node_in_group("grid")
	if grid:
		var occupant = grid.get_occupant(_target_cell)
		if occupant is GridEntity and occupant.is_in_group("player"):
			# 如果發動者已死亡，則傳入 null
			var attacker = parent_entity if is_instance_valid(parent_entity) else null
			occupant.apply_damage(damage, false, false, attacker)
	
	# 清理
	_current_warning.queue_free()
	_current_warning = null
	
	var tween = create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.4)
	await tween.finished
	line.queue_free()
	
	print("[EnemyAttack] Beholder firing ray at ", _target_cell)

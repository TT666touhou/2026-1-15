extends Node2D
class_name LightningChain

var source_entity: GridEntity
var target_entity: GridEntity
var damage_per_tick: int = 0
var tick_rate: float = 0.1

@onready var line: Line2D = $Line2D
@onready var ray: RayCast2D = $RayCast2D

var _tick_timer: float = 0.0

func _ready() -> void:
	add_to_group("projectiles")
	# 設置 RayCast2D 偵測敵人 (Layer 1 & 3)
	ray.enabled = true
	ray.collision_mask = 1 | 4
	ray.collide_with_areas = true
	ray.collide_with_bodies = true
	
	# 設置 Line2D 樣式
	line.width = 0.8
	line.default_color = Color(0.4, 0.7, 1.0, 1.0) # 淺藍色雷電
	
	# 確保在所有實體之上
	z_index = 100
	z_as_relative = false

func setup(src: GridEntity, tgt: GridEntity, dmg: int, _unused_dur: float = 2.0) -> void:
	source_entity = src
	target_entity = tgt
	damage_per_tick = dmg

func _process(delta: float) -> void:
	if not is_instance_valid(source_entity) or not is_instance_valid(target_entity):
		queue_free()
		return
	
	# 檢查雙方是否都停止移動
	var src_moving = source_entity.character_data.is_moving_physics if source_entity.character_data else false
	var tgt_moving = target_entity.character_data.is_moving_physics if target_entity.character_data else false
	
	if not src_moving and not tgt_moving:
		queue_free()
		return
		
	var start_pos = source_entity.global_position
	var end_pos = target_entity.global_position
	
	# 更新 Line2D (加入抖動效果模擬雷電)
	line.clear_points()
	var segments = 8
	for i in range(segments + 1):
		var t = float(i) / segments
		var pos = start_pos.lerp(end_pos, t)
		if i > 0 and i < segments:
			pos += Vector2(randf_range(-4, 4), randf_range(-4, 4))
		line.add_point(to_local(pos))
	
	# 更新 RayCast2D 進行碰撞偵測
	ray.global_position = start_pos
	ray.target_position = ray.to_local(end_pos)
	
	# 處理傷害 Tick
	_tick_timer += delta
	if _tick_timer >= tick_rate:
		_tick_timer = 0.0
		_check_collision_and_damage()

func _check_collision_and_damage() -> void:
	# 使用 ShapeCast 或多次 RayCast 以覆蓋雷電寬度
	# 這裡使用簡單的 RayCast 模擬，實際專案中可用多條 Ray 或 SegmentShape
	if ray.is_colliding():
		var collider = ray.get_collider()
		# 如果發動者已死亡，則傳入 null
		var attacker = source_entity if is_instance_valid(source_entity) else null
		
		if collider is GridEntity and (attacker == null or collider.faction != attacker.faction):
			collider.apply_damage(damage_per_tick, false, false, attacker)
		elif collider is Area2D:
			var parent = collider.get_parent()
			if parent is GridEntity and (attacker == null or parent.faction != attacker.faction):
				parent.apply_damage(damage_per_tick, false, false, attacker)

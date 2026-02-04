extends Node2D
class_name BeholderLaser

## 邪眼反射雷射 (視覺優化版)
## 負責分段計算路徑、逐段繪製 Line2D 並造成穿透傷害

# 顏色定義 (來自色錶)
const COLOR_LASER_CORE = Color("#b59c90")
const COLOR_LASER_GLOW = Color("#6b6a80")

@export var damage: int = 15
@export var max_bounces: int = 2
@export var max_length: float = 1000.0

var attacker_entity: GridEntity = null
var _hit_cooldowns: Dictionary = {}
const HIT_INTERVAL_MS: int = 500

@onready var line_glow: Line2D = $LineGlow
@onready var line_core: Line2D = $LineCore

func _ready() -> void:
	# 初始化 Line2D
	line_glow.default_color = COLOR_LASER_GLOW
	line_core.default_color = COLOR_LASER_CORE
	line_glow.clear_points()
	line_core.clear_points()
	
	# 初始寬度
	line_glow.width = 18.0
	line_core.width = 6.0

func setup(pos: Vector2, dir: Vector2, dmg: int, attacker: GridEntity) -> void:
	global_position = pos
	damage = dmg
	attacker_entity = attacker
	
	# 執行非同步雷射序列
	_run_laser_sequence(dir.normalized())

func _run_laser_sequence(initial_dir: Vector2) -> void:
	var current_start = Vector2.ZERO
	var current_direction = initial_dir
	var remaining_length = max_length
	var bounces_left = max_bounces
	
	# 加入起點
	line_glow.add_point(current_start)
	line_core.add_point(current_start)
	
	while remaining_length > 0:
		# 轉換為全域座標進行射線檢測
		var global_start = to_global(current_start)
		var global_end = global_start + current_direction * remaining_length
		
		var query = PhysicsRayQueryParameters2D.create(global_start, global_end)
		query.collision_mask = 2 # 牆壁層
		if is_instance_valid(attacker_entity):
			query.exclude = [attacker_entity.get_rid()]
			
		var space_state = get_world_2d().direct_space_state
		var result = space_state.intersect_ray(query)
		
		var actual_hit_pos: Vector2
		var segment_length: float
		
		if result:
			actual_hit_pos = result.position
			segment_length = global_start.distance_to(actual_hit_pos)
		else:
			actual_hit_pos = global_end
			segment_length = remaining_length
			
		# 更新 Line2D (增加一個段落)
		var local_hit_pos = to_local(actual_hit_pos)
		line_glow.add_point(local_hit_pos)
		line_core.add_point(local_hit_pos)
		
		# 執行當前段落的傷害
		_check_damage_on_segment(global_start, actual_hit_pos)
		
		# 播放反彈/撞擊效果
		_play_segment_impact_fx()
		
		# 如果還有剩餘反彈次數且撞到了牆
		if result and bounces_left > 0:
			var normal = result.normal
			if normal.length_squared() > 0.001:
				# 等待一拍 (0.2秒) 再發射下一段
				await get_tree().create_timer(0.2).timeout
				
				current_direction = current_direction.bounce(normal)
				current_start = local_hit_pos
				remaining_length -= segment_length
				bounces_left -= 1
			else:
				break
		else:
			break
			
	# 全部發射完畢，等待一下後整體消失
	await get_tree().create_timer(0.4).timeout
	_fade_out_and_free()

func _check_damage_on_segment(start: Vector2, end: Vector2) -> void:
	var query = PhysicsRayQueryParameters2D.create(start, end)
	query.collision_mask = 1 # 單位層
	query.collide_with_areas = true
	
	var space_state = get_world_2d().direct_space_state
	var excluded = []
	if is_instance_valid(attacker_entity): 
		excluded.append(attacker_entity.get_rid())
	
	for i in range(10): # 最多檢測 10 個單位
		query.exclude = excluded
		var result = space_state.intersect_ray(query)
		if result:
			var collider = result.collider
			if collider is GridEntity and collider.is_in_group("player"):
				_apply_damage(collider)
			excluded.append(result.rid)
		else:
			break

func _apply_damage(target: GridEntity) -> void:
	var target_id = target.get_instance_id()
	var now = Time.get_ticks_msec()
	
	if _hit_cooldowns.has(target_id):
		if now - _hit_cooldowns[target_id] < HIT_INTERVAL_MS:
			return
			
	_hit_cooldowns[target_id] = now
	
	var attacker = attacker_entity if is_instance_valid(attacker_entity) else null
	target.apply_damage(damage, false, false, attacker)

func _play_segment_impact_fx() -> void:
	var tw = create_tween()
	var old_glow_w = line_glow.width
	var old_core_w = line_core.width
	
	tw.set_parallel(true)
	tw.tween_property(line_glow, "width", old_glow_w * 1.2, 0.05)
	tw.tween_property(line_core, "width", old_core_w * 1.5, 0.05)
	tw.chain().set_parallel(true)
	tw.tween_property(line_glow, "width", old_glow_w, 0.1)
	tw.tween_property(line_core, "width", old_core_w, 0.1)

func _fade_out_and_free() -> void:
	var tw = create_tween().set_parallel(true)
	tw.tween_property(line_glow, "width", 0.0, 0.3)
	tw.tween_property(line_core, "width", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)

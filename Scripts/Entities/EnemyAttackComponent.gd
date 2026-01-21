extends Node
class_name EnemyAttackComponent

## 敵人預警遠程攻擊組件
## 負責循環計時、閃爍預警並發射子彈

@export_group("Timing Settings")
@export var attack_interval: float = 5.0      # 兩次攻擊之間的間隔 (秒)
@export var telegraph_duration: float = 2.0   # 預警箭頭填滿的時長 (秒)

@export_group("Attack Mode")
@export var is_ram_attack: bool = true

@export_group("Enable")
@export var enabled: bool = false

@export_group("Projectile Settings")
@export var attack_range: int = 0               # 攻擊射程 (0 為無限)
@export var single_direction_only: bool = false
@export var current_attack_dir: Vector2i = Vector2i.UP
@export var bullet_scene: PackedScene = preload("res://Scenes/Shared/EnemyProjectile.tscn")
@export var bullet_travel_time: float = 0.15   # 子彈飛行一格的時間 (秒)

@onready var parent_entity: GridEntity = get_parent()

var _timer: float = 0.0
var _is_telegraphing: bool = false
var _telegraph_timer: float = 0.0

func _ready() -> void:
	if not parent_entity:
		push_error("[EnemyAttackComponent] Parent must be GridEntity")
		set_process(false)
		return

	if not enabled:
		set_process(false)
		# 確保指示器不會停留在紅色狀態
		if parent_entity.has_method("update_attack_indicators"):
			parent_entity.update_attack_indicators(0.0)
		return
	
	# 稍微隨機化初始計時，避免所有敵人同時發射
	_timer = randf_range(0, attack_interval * 0.5)

func _process(delta: float) -> void:
	if not _is_telegraphing:
		_timer += delta
		# 只有當計時結束「且」玩家在射程內時，才開始預警
		if _timer >= attack_interval and _is_any_target_in_range():
			_start_telegraph()
	else:
		_telegraph_timer += delta
		
		# 更新攻擊指示器進度 (變紅)
		if parent_entity.has_method("update_attack_indicators"):
			var progress = clamp(_telegraph_timer / telegraph_duration, 0.0, 1.0)
			var target_dir = current_attack_dir if single_direction_only else Vector2i.ZERO
			parent_entity.update_attack_indicators(progress, target_dir)
			
		if _telegraph_timer >= telegraph_duration:
			await _fire_projectiles()
			_timer = 0.0
			_telegraph_timer = 0.0
			_is_telegraphing = false
			
			# 重置指示器
			if parent_entity.has_method("update_attack_indicators"):
				parent_entity.update_attack_indicators(0.0)

func _start_telegraph() -> void:
	_is_telegraphing = true
	_telegraph_timer = 0.0
	print("[EnemyAttackComponent] %s: Player in range, starting telegraph." % parent_entity.name)

func _fire_projectiles() -> void:
	# 確保停止預警狀態
	_is_telegraphing = false 
	
	if is_ram_attack:
		var mover = parent_entity.get_node_or_null("GridMover") as GridMover
		if mover:
			var target_cell = parent_entity.grid_position + current_attack_dir
			# 執行撞擊：朝 current_attack_dir 移動。
			# mover.move_to 會自動處理碰撞並觸發 ram_attack
			# print("[EnemyAttackComponent] %s executing RAM ATTACK towards %s" % [parent_entity.name, current_attack_dir])
			await mover.move_to(target_cell, false, current_attack_dir)
		return
		
	if not parent_entity.movement_range_data:
		return
		
	# 根據 MovementRangeData 中非 BLOCKED 的方向發射
	# 目前系統已經改為 4 方向 (WASD)
	var directions = []
	if single_direction_only:
		directions = [current_attack_dir]
	else:
		directions = [
			Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
		]
	
	var damage = 10
	if parent_entity.character_data:
		damage = parent_entity.character_data.get_effective_attack()
	
	# 處理多格實體的子彈發射點
	var occupied_cells = [parent_entity.grid_position]
	if parent_entity.has_method("get_occupied_cells"):
		occupied_cells = parent_entity.get_occupied_cells()
	
	for dir in directions:
		# 檢查該方向是否允許移動/攻擊 (非 BLOCKED)
		var move_type = parent_entity.movement_range_data.get_movement_type(dir)
		if move_type == MovementRangeData.MovementType.BLOCKED:
			continue
			
		# 找出此方向最前端的格子集合 (Leading Edge)
		var leading_cells = _get_leading_edge_for_dir(occupied_cells, dir)
		for cell in leading_cells:
			_spawn_projectile_from_cell(cell, dir, damage)

func _get_leading_edge_for_dir(cells: Array[Vector2i], dir: Vector2i) -> Array[Vector2i]:
	var leading: Array[Vector2i] = []
	for cell in cells:
		var ahead = cell + dir
		# 如果前方格子不在佔用格子內，說明這是邊緣格子
		if not ahead in cells:
			leading.append(cell)
	return leading

func _spawn_projectile_from_cell(cell: Vector2i, dir: Vector2i, dmg: int) -> void:
	if not bullet_scene: return
	
	var bullet = bullet_scene.instantiate() as EnemyProjectile
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(bullet)
	else:
		parent_entity.get_parent().add_child(bullet)
	
	bullet.setup(cell, dir, dmg, bullet_travel_time, parent_entity)

func _spawn_projectile(_dir: Vector2i, _dmg: int) -> void:
	# 此函式已由 _spawn_projectile_from_cell 取代
	pass

func _is_any_target_in_range() -> bool:
	"""檢查是否有玩家在任何攻擊方向的射程內"""
	var player = get_tree().get_first_node_in_group("player") as GridEntity
	if not player or not is_instance_valid(player):
		return false
	
	var p_pos = player.grid_position
	var occupied_cells = [parent_entity.grid_position]
	if parent_entity.has_method("get_occupied_cells"):
		occupied_cells = parent_entity.get_occupied_cells()
	
	var directions = []
	if single_direction_only:
		directions = [current_attack_dir]
	else:
		directions = [
			Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
		]
		
	for dir in directions:
		for cell in occupied_cells:
			if _is_target_in_direction_range(p_pos, cell, dir):
				return true
	return false

func _is_target_in_direction_range(p_pos: Vector2i, e_pos: Vector2i, dir: Vector2i) -> bool:
	"""檢查目標點是否在指定起點與方向的直線（或斜向）射程內"""
	var diff = p_pos - e_pos
	
	# 水平對齊
	if dir.x != 0 and dir.y == 0:
		if diff.y == 0 and sign(diff.x) == sign(dir.x):
			var dist = abs(diff.x)
			return attack_range <= 0 or dist <= attack_range
	# 垂直對齊
	elif dir.y != 0 and dir.x == 0:
		if diff.x == 0 and sign(diff.y) == sign(dir.y):
			var dist = abs(diff.y)
			return attack_range <= 0 or dist <= attack_range
	# 斜向對齊
	elif dir.x != 0 and dir.y != 0:
		if abs(diff.x) == abs(diff.y) and sign(diff.x) == sign(dir.x) and sign(diff.y) == sign(dir.y):
			var dist = abs(diff.x) # 斜向距離以格數計
			return attack_range <= 0 or dist <= attack_range
			
	return false

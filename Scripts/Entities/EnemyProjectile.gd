extends Node2D
class_name EnemyProjectile

## 敵人子彈實體
## 負責在網格上飛行並偵測與玩家的碰撞

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var grid: Node
var grid_position: Vector2i
var direction: Vector2i
var damage: int = 1
var travel_time_per_cell: float = 0.2
var attacker_entity: GridEntity = null

var _is_active: bool = false

func setup(start_grid_pos: Vector2i, dir: Vector2i, dmg: int, speed: float, attacker: GridEntity) -> void:
	grid_position = start_grid_pos
	direction = dir
	damage = dmg
	travel_time_per_cell = speed
	attacker_entity = attacker
	
	grid = get_tree().get_first_node_in_group("grid")
	
	# 設定初始世界座標
	if grid and grid.has_method("grid_to_world_center"):
		global_position = grid.grid_to_world_center(grid_position)
	
	# 根據方向旋轉子彈
	rotation = atan2(direction.y, direction.x)
	
	_is_active = true
	_start_flying()

func _start_flying() -> void:
	if not _is_active: return
	
	# 開始循環移動到下一格
	_move_to_next_cell()

func _move_to_next_cell() -> void:
	if not _is_active or grid == null: 
		_destroy()
		return
		
	var next_cell = grid_position + direction
	
	# 邊界檢查
	if not grid.has_method("is_in_bounds") or not grid.is_in_bounds(next_cell):
		_destroy()
		return
		
	var target_world_pos = grid.grid_to_world_center(next_cell)
	
	var tween = create_tween()
	tween.tween_property(self, "global_position", target_world_pos, travel_time_per_cell)\
		.set_trans(Tween.TRANS_LINEAR)
	
	await tween.finished
	
	grid_position = next_cell
	
	# 每到一格就檢查碰撞
	if await _check_collision():
		_destroy()
	else:
		# 繼續飛向下一格
		_move_to_next_cell()

func _check_collision() -> bool:
	if not grid or not grid.has_method("get_occupant"):
		return false
		
	var occupant = grid.get_occupant(grid_position)
	if occupant is GridEntity and occupant != attacker_entity:
		# 檢查陣營：只撞擊敵對陣營 (玩家方)
		if attacker_entity and attacker_entity.faction and occupant.faction:
			if attacker_entity.faction != occupant.faction:
				# 造成傷害
				if occupant.has_method("apply_damage"):
					print("[Projectile] Hit: ", occupant.name, " for ", damage, " damage.")
					# apply_damage 現在是非同步的
					await occupant.apply_damage(damage, false, false, attacker_entity)
				return true
	return false

func _destroy() -> void:
	_is_active = false
	# 可以加入消失特效
	queue_free()

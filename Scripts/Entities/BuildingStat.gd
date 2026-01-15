extends Node
class_name BuildingStat

## Building 狀態管理腳本
## 管理 Building 的狀態（血量）並提供狀態信息

@export var max_health: int = 200
@export var current_health: int = 200
@export var enable_debug_log: bool = false

var _parent: CharacterBody2D = null
var _is_dead: bool = false

signal building_died(building: CharacterBody2D)
signal health_changed(current_health: int, max_health: int)
signal health_depleted

func _ready() -> void:
	_parent = get_parent() as CharacterBody2D
	if _parent == null:
		push_error("[BuildingStat] Parent must be CharacterBody2D")
		return
	
	current_health = max_health
	
	if enable_debug_log:
		print("[BuildingStat] Initialized: HP=", current_health, "/", max_health)

func get_info() -> Dictionary:
	# 返回狀態信息供選擇系統使用
	return {
		health = current_health,
		max_health = max_health,
		health_percent = float(current_health) / float(max_health) if max_health > 0 else 0.0
	}

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	
	current_health = max(0, current_health - amount)
	
	# 發出血量變化信號
	health_changed.emit(current_health, max_health)
	
	if enable_debug_log:
		print("[BuildingStat] Took damage: ", amount, " HP=", current_health, "/", max_health)
	
	# 檢查死亡
	if current_health <= 0 and not _is_dead:
		health_depleted.emit()
		_die()

func heal(amount: int) -> void:
	if _is_dead:
		return
	
	var previous_health = current_health
	current_health = min(max_health, current_health + amount)
	
	# 發出血量變化信號
	if previous_health != current_health:
		health_changed.emit(current_health, max_health)
	
	if enable_debug_log:
		print("[BuildingStat] Healed: ", amount, " HP=", current_health, "/", max_health)

func set_health(value: int) -> void:
	if _is_dead:
		return
	
	var previous_health = current_health
	current_health = clamp(value, 0, max_health)
	
	# 發出血量變化信號
	if previous_health != current_health:
		health_changed.emit(current_health, max_health)
	
	# 檢查死亡
	if current_health <= 0 and not _is_dead:
		health_depleted.emit()
		_die()
	
	if enable_debug_log:
		print("[BuildingStat] Set health: ", current_health, "/", max_health)

## 死亡處理
func _die() -> void:
	if _is_dead:
		return
	
	_is_dead = true
	
	if enable_debug_log:
		print("[BuildingStat] Building died: ", _parent.name)
	
	# 發出死亡信號
	if _parent != null:
		building_died.emit(_parent)
	
	# 延遲銷毀，允許信號接收者處理
	call_deferred("_destroy_building")

## 銷毀建築
func _destroy_building() -> void:
	if _parent != null and is_instance_valid(_parent):
		_parent.queue_free()

## 檢查是否已死亡
func is_dead() -> bool:
	return _is_dead


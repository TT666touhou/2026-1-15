extends RigidBody2D
class_name PhysicalCoin

## 物理金幣實體
## 負責噴發、物理碰撞以及最終飛向 UI 被回收

const COLOR_COIN = Color("#f2b233") # 假設的金幣色

var _is_collecting: bool = false
var _target_node: Node2D = null
var _collection_speed: float = 0.0
const MAX_COLLECTION_SPEED = 600.0
const ACCELERATION = 1200.0

func _ready() -> void:
	add_to_group("loot")
	add_to_group("physical_coins")
	
	# 給予隨機初始衝量
	var random_dir = Vector2.RIGHT.rotated(randf_range(0, TAU))
	var force = randf_range(100.0, 250.0)
	apply_central_impulse(random_dir * force)
	
	# 隨機旋轉力 (移除，保持外觀不旋轉)
	# apply_torque_impulse(randf_range(-50.0, 50.0))

func _physics_process(delta: float) -> void:
	if _is_collecting and is_instance_valid(_target_node):
		# 加速移動向目標
		_collection_speed = move_toward(_collection_speed, MAX_COLLECTION_SPEED, ACCELERATION * delta)
		global_position = global_position.move_toward(_target_node.global_position, _collection_speed * delta)
		
		# 距離夠近就回收
		if global_position.distance_to(_target_node.global_position) < 10.0:
			_on_reached_target()

func collect_to_node(target: Node2D) -> void:
	if _is_collecting: return
	_is_collecting = true
	_target_node = target
	_collection_speed = linear_velocity.length() # 從當前速度開始銜接
	
	# 停止物理模擬
	set_deferred("freeze", true)
	# 關閉碰撞，避免干擾玩家
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

func enable_collection() -> void:
	# [相容性介面]
	pass

func collect(target_global_pos: Vector2) -> void:
	if _is_collecting: return
	_is_collecting = true
	
	# 停止物理模擬 (使用 set_deferred 避開 flushing_queries 錯誤)
	set_deferred("freeze", true)
	
	var tw = create_tween()
	# 先稍微往上跳一下再飛過去
	var mid_pos = global_position + Vector2(randf_range(-20, 20), -40)
	
	tw.set_parallel(false)
	tw.tween_property(self, "global_position", mid_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", target_global_pos, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	# 移除縮小動畫
	# tw.parallel().tween_property(self, "scale", Vector2.ZERO, 0.5)
	
	tw.finished.connect(_on_reached_ui)

func _on_reached_target() -> void:
	# 增加實際資源
	var ledger = get_tree().get_first_node_in_group("ledger")
	if ledger:
		ledger.add_resource("coin", 1)
	
	queue_free()

func _on_reached_ui() -> void:
	_on_reached_target()

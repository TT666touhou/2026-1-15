extends RigidBody2D
class_name PhysicalCoin

## 物理金幣實體
## 負責噴發、物理碰撞以及最終飛向 UI 被回收

const COLOR_COIN = Color("#f2b233") # 假設的金幣色

var _is_collecting: bool = false

func _ready() -> void:
	add_to_group("physical_coins")
	# 初始隨機旋轉 (移除，保持像素對齊)
	# rotation = randf_range(0, TAU)
	# 物理設定：Layer 8 (128), Mask 131 (1+2+128)
	collision_layer = 128
	collision_mask = 131
	
	# 給予隨機初始衝量
	var random_dir = Vector2.RIGHT.rotated(randf_range(0, TAU))
	var force = randf_range(100.0, 250.0)
	apply_central_impulse(random_dir * force)
	
	# 隨機旋轉力 (移除，保持外觀不旋轉)
	# apply_torque_impulse(randf_range(-50.0, 50.0))

func collect(target_global_pos: Vector2) -> void:
	if _is_collecting: return
	_is_collecting = true
	
	# 停止物理模擬
	freeze = true
	
	var tw = create_tween()
	# 先稍微往上跳一下再飛過去
	var mid_pos = global_position + Vector2(randf_range(-20, 20), -40)
	
	tw.set_parallel(false)
	tw.tween_property(self, "global_position", mid_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", target_global_pos, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	# 移除縮小動畫
	# tw.parallel().tween_property(self, "scale", Vector2.ZERO, 0.5)
	
	tw.finished.connect(_on_reached_ui)

func _on_reached_ui() -> void:
	# 增加實際資源
	var ledger = get_tree().get_first_node_in_group("ledger")
	if ledger:
		ledger.add_resource("coin", 1)
	
	queue_free()

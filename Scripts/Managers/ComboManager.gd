extends Node

# 全局連擊管理器 (Autoload: ComboManager)

signal combo_updated(count: int, window_time: float)

var current_combo: int = 0
var last_hit_time: float = 0.0
var combo_window: float = 0.8 # 連擊有效窗口 (秒)

func _process(_delta: float) -> void:
	if current_combo > 0:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_hit_time > combo_window:
			reset_combo()

func register_hit() -> float:
	"""註冊一次擊中，更新連擊並回傳傷害倍率"""
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if current_time - last_hit_time <= combo_window:
		current_combo += 1
	else:
		current_combo = 1
	
	last_hit_time = current_time
	combo_updated.emit(current_combo, combo_window)
	
	# 每層連擊提升 10% 傷害 (Combo 1 = 1.0, Combo 2 = 1.1 ...)
	return 1.0 + (max(0, current_combo - 1) * 0.1)

func reset_combo() -> void:
	if current_combo != 0:
		current_combo = 0
		combo_updated.emit(0, combo_window)
		print("[ComboManager] Combo Reset")

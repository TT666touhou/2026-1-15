extends Marker2D
class_name FloatingText

@onready var label: Label = $Label

var _tween: Tween
var _base_scale: Vector2 = Vector2(0.0625, 0.0625) # 0.25 * 0.25 = 0.0625

func _ready() -> void:
	# 記錄初始縮放值 (這通常來自 .tscn 中的設定，如 0.25)
	_base_scale = scale
	
	# 核心修正：移除這裡的 top_level = true，改由外部設定位置後再開啟
	
	# --- Debug 模式 ---
	# 如果是單獨運行此場景 (F6)，自動添加相機並啟用測試
	if get_tree().current_scene == self:
		var cam = Camera2D.new()
		cam.zoom = Vector2(4, 4)
		add_child(cam)
		print("[FloatingText] Debug Mode Started. Press 'D' for Damage, 'A' for Attack.")
		
		# Debug 模式下不隱藏自己，否則子節點也會看不見
		visible = true
		
		# 顯示一個初始測試值
		var instance = duplicate()
		add_child(instance)
		instance.popup_damage(123)
	else:
		# 正常遊戲模式下，初始化時隱藏
		visible = false

func popup_damage(amount: int) -> void:
	_reset_state()
	
	if amount < 0:
		# 治療效果
		label.text = "+" + str(abs(amount))
		var heal_settings = load("res://Scenes/UI/FloatingTextSettings_Heal.tres")
		if heal_settings:
			label.label_settings = heal_settings
		else:
			label.modulate = Color.GREEN # Fallback
	else:
		# 傷害效果
		label.text = str(amount)
		# 復原為預設設定 (假設場景中預設是 Damage 的設定)
		var default_settings = load("res://Scenes/UI/FloatingTextSettings.tres")
		if default_settings:
			label.label_settings = default_settings
		else:
			label.modulate = Color.WHITE
	
	_play_bounce_animation()

func popup_text(text_content: String, color: Color = Color.WHITE) -> void:
	_reset_state()
	label.text = text_content
	label.modulate = color
	# 如果有預設樣式，嘗試加載 (為了閃避字體大小等)
	var default_settings = load("res://Scenes/UI/FloatingTextSettings.tres")
	if default_settings:
		label.label_settings = default_settings
		
	_play_bounce_animation()

func popup_pursuit(amount: int) -> void:
	_reset_state()
	label.text = "PURSUIT: " + str(amount)
	# 使用亮青色以區分普通傷害
	label.modulate = Color(0, 1, 1) 
	
	var default_settings = load("res://Scenes/UI/FloatingTextSettings.tres")
	if default_settings:
		label.label_settings = default_settings
		
	_play_bounce_animation()

func popup_parry() -> void:
	_reset_state()
	label.text = "PARRIED"
	# 使用紫色或深藍色表示格擋
	label.modulate = Color(0.6, 0.4, 1.0)
	
	var default_settings = load("res://Scenes/UI/FloatingTextSettings.tres")
	if default_settings:
		label.label_settings = default_settings
		
	_play_bounce_animation()

func popup_barrier() -> void:
	_reset_state()
	label.text = "防護罩"
	# 使用金黃色或亮橙色表示防護罩抵擋
	label.modulate = Color(1, 0.8, 0.2)
	
	var default_settings = load("res://Scenes/UI/FloatingTextSettings.tres")
	if default_settings:
		label.label_settings = default_settings
		
	_play_bounce_animation()

func popup_attack(amount: int) -> void:
	_reset_state()
	label.text = str(amount)
	
	# 只播放出現動畫，不自動消失
	_play_attack_appear_animation()

func dismiss() -> void:
	"""手動播放消失動畫"""
	if _tween and _tween.is_valid():
		_tween.kill()
		
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ZERO, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_callback(queue_free)

func _reset_state() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	
	visible = true
	scale = _base_scale
	# 核心修正：恢復 position 動畫邏輯，但因為 top_level = true，
	# 這裡的 position 會在 _ready 時被 GridEntity 設定為正確的世界座標
	modulate.a = 1.0
	rotation = 0.0

func _play_bounce_animation() -> void:
	# 計算隨機參數 (縮減至 1/4)
	var spread = 15.0 # 60.0 * 0.25
	var target_x = randf_range(-spread, spread)
	var height = randf_range(-12.5, -20.0) # (-50 to -80) * 0.25
	# 增加 30% 旋轉幅度 (原本 0.1 -> 0.13)
	var rand_rot = randf_range(-0.13, 0.13)
	# 核心修正：落點高度調整為單位的腳部位置
	# 假設單位高度約 16-20 像素，從頭頂 (-16) 墜落到腳部 (+8)，大約需要 24 像素的偏移
	var land_y = 24.0 + randf_range(-2.5, 2.5)
	
	# 記錄起始位置 (由 GridEntity 設定的 global_position)
	var start_pos = position
	
	_tween = create_tween()
	_tween.set_parallel(false)
	
	# 1. 上升 (Up)
	# 向上彈起並變大 (相對於 base_scale)
	_tween.tween_property(self, "scale", _base_scale * 1.5, 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	_tween.parallel().tween_property(self, "position:y", start_pos.y + height, 0.15)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "position:x", start_pos.x + target_x * 0.4, 0.15)
	_tween.parallel().tween_property(self, "rotation", rand_rot, 0.15)
		
	# 2. 落下 (Down)
	# 落點不再是 0.0，而是 land_y
	_tween.tween_property(self, "position:y", start_pos.y + land_y, 0.35)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "scale", _base_scale, 0.35)
	_tween.parallel().tween_property(self, "position:x", start_pos.x + target_x, 0.35)
	_tween.parallel().tween_property(self, "rotation", 0.0, 0.35)
	
	# 3. 停留
	_tween.tween_interval(0.3)
	
	# 4. 淡出消失
	_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_tween.tween_callback(queue_free)

func _play_attack_appear_animation() -> void:
	_tween = create_tween()
	
	# 1. 瞬間放大 (Punch)
	scale = Vector2.ZERO
	_tween.tween_property(self, "scale", _base_scale * 1.8, 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 2. 稍微回彈並停留 (不消失)
	_tween.tween_property(self, "scale", _base_scale * 1.2, 0.1)

# Debug Input Logic
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build(): return
	if get_tree().current_scene != self: return
	
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_D:
			print("[FloatingText] Key D Pressed -> Spawning Damage")
			var val = randi_range(1, 9999)
			_spawn_debug_instance(val, "damage")
			
		elif event.keycode == KEY_A:
			print("[FloatingText] Key A Pressed -> Spawning Attack")
			var val = randi_range(1, 9999)
			_spawn_debug_instance(val, "attack")

func _spawn_debug_instance(amount: int, type: String) -> void:
	# 複製自身 (因為這是一個已經加載的場景)
	# 但最好的方式是實例化 PackedScene，這裡簡單用 duplicate
	# 注意：duplicate 預設不複製信號和 group，但對於這個簡單物件夠用了
	# 更好的做法是 load 場景，避免狀態污染
	var scene = load("res://Scenes/UI/FloatingText.tscn")
	if scene:
		var instance = scene.instantiate()
		add_child(instance)
		if type == "damage":
			instance.popup_damage(amount)
		elif type == "attack":
			instance.popup_attack(amount)

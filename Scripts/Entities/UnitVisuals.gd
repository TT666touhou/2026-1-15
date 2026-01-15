extends Node
class_name UnitVisuals

@export var sprite_path: NodePath = "../Sprite2D"
@onready var sprite: Sprite2D = get_node_or_null(sprite_path)

var _original_scale: Vector2 = Vector2.ONE
var _original_pos: Vector2 = Vector2.ZERO
var _tween: Tween

signal spawn_animation_finished

func _ready() -> void:
	# 延遲獲取以確保 Sprite 已初始化
	if sprite:
		_original_scale = sprite.scale
		_original_pos = sprite.position
	else:
		# 嘗試自動查找
		var parent = get_parent()
		if parent:
			sprite = parent.get_node_or_null("Sprite2D")
			if sprite:
				_original_scale = sprite.scale
				_original_pos = sprite.position

func play_tick_animation() -> void:
	if sprite == null: return
	
	# 確保上一個動畫停止
	if _tween and _tween.is_valid():
		_tween.kill()
		
	# 重置狀態
	sprite.scale = _original_scale
	sprite.position = _original_pos
		
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_OUT)
	
	# 1. 蓄力 (Squash) - 0.1s
	_tween.tween_property(sprite, "scale", _original_scale * Vector2(1.2, 0.8), 0.1)
	
	# 2. 跳起 (Jump & Stretch) - 0.15s
	_tween.set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(sprite, "position:y", _original_pos.y - 10.0, 0.15) # 向上跳 10px
	_tween.parallel().tween_property(sprite, "scale", _original_scale * Vector2(0.9, 1.1), 0.15)
	
	# 3. 落地 (Land & Squash) - 0.15s
	_tween.set_ease(Tween.EASE_IN)
	_tween.chain().parallel().tween_property(sprite, "position:y", _original_pos.y, 0.15)
	_tween.parallel().tween_property(sprite, "scale", _original_scale * Vector2(1.2, 0.8), 0.15)
	
	# 4. 恢復 (Recover) - 0.1s
	_tween.chain().tween_property(sprite, "scale", _original_scale, 0.1)

func play_damage_animation() -> void:
	if sprite == null: return
	
	# 1. 強制重置狀態 (防止上次動畫未結束導致偏移疊加)
	if _tween and _tween.is_valid():
		_tween.kill()
	
	sprite.position = _original_pos
	sprite.scale = _original_scale
	sprite.modulate = Color.WHITE
	
	_tween = create_tween()
	
	# --- 視覺閃爍 (Flash) ---
	# 並行軌道 1: 顏色變化 (使用獨立的 Tween 或 parallel 處理)
	var flash_tween = create_tween()
	flash_tween.tween_property(sprite, "modulate", Color(10, 10, 10), 0.05) # 高亮白/紅 (HDR)
	flash_tween.chain().tween_property(sprite, "modulate", Color(1, 0.2, 0.2), 0.05) # 轉紅
	flash_tween.chain().tween_property(sprite, "modulate", Color.WHITE, 0.2) # 回復
	
	# --- 位置抖動 (Shake) ---
	# 並行軌道 2: 位置變化 (衰減正弦波模式)
	var shake_strength = 8.0
	var step_time = 0.05
	
	# Step 1: 右移 (受擊瞬間)
	_tween.tween_property(sprite, "position:x", _original_pos.x + shake_strength, step_time)\
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		
	# Step 2: 左移 (反彈)
	_tween.chain().tween_property(sprite, "position:x", _original_pos.x - (shake_strength * 0.7), step_time)
	
	# Step 3: 右移 (震盪)
	_tween.chain().tween_property(sprite, "position:x", _original_pos.x + (shake_strength * 0.4), step_time)
	
	# Step 4: 左移 (微震)
	_tween.chain().tween_property(sprite, "position:x", _original_pos.x - (shake_strength * 0.2), step_time)
	
	# Step 5: 歸位 (確保不漂移)
	_tween.chain().tween_property(sprite, "position:x", _original_pos.x, step_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func play_attack_animation(target_dir: Vector2) -> void:
	if sprite == null: return
	
	# 歸一化方向向量 (確保對角線長度一致)
	var dir = target_dir.normalized()
	
	# 停止舊動畫並重置
	if _tween and _tween.is_valid():
		_tween.kill()
	sprite.position = _original_pos
	sprite.scale = _original_scale
	sprite.rotation = 0 # 如果有用到旋轉
	sprite.modulate = Color.WHITE
	
	_tween = create_tween()
	
	# 參數設定
	var windup_time = 0.15 # 蓄力時間
	var strike_time = 0.05 # 打擊時間 (快速)
	var recovery_time = 0.2 # 恢復時間
	
	var windup_dist = -8.0 # 反向後退距離
	var strike_dist = 24.0 # 正向衝刺距離
	
	# 1. 蓄力 (Anticipation) - 向後退
	_tween.tween_property(sprite, "position", _original_pos + (dir * windup_dist), windup_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
	# 2. 攻擊衝刺 (Strike) - 向前衝
	_tween.chain().tween_property(sprite, "position", _original_pos + (dir * strike_dist), strike_time)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	# 3. 恢復 (Recovery) - 彈回原點
	_tween.chain().tween_property(sprite, "position", _original_pos, recovery_time)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func play_spawn_animation(type_int: int) -> void:
	# 停止當前任何 Tween
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	
	# 獲取視覺根節點的引用 (可能是 Sprite 或其他)
	if not sprite: return
	
	# 重置狀態 (確保視覺歸位)
	sprite.position = _original_pos
	sprite.scale = _original_scale
	sprite.rotation = 0.0
	sprite.modulate.a = 1.0
	
	match type_int:
		0: # DROP
			sprite.position.y = _original_pos.y - 300
			sprite.modulate.a = 0.0
			_tween.set_parallel(true)
			_tween.tween_property(sprite, "position:y", _original_pos.y, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_tween.tween_property(sprite, "modulate:a", 1.0, 0.3)
			
		1: # LEAP (模擬拋物線)
			# 讓它從左上方跳進來
			var start_offset = Vector2(-100, -100)
			sprite.position = _original_pos + start_offset
			sprite.modulate.a = 0.0
			
			_tween.set_parallel(true)
			_tween.tween_property(sprite, "modulate:a", 1.0, 0.2)
			
			# X軸: 線性移動
			_tween.tween_property(sprite, "position:x", _original_pos.x, 0.5)
			
			# Y軸: 模擬重力 (使用 TRANS_BOUNCE 讓它落地有彈性)
			_tween.tween_property(sprite, "position:y", _original_pos.y, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			
		2: # POP
			sprite.scale = Vector2.ZERO
			sprite.rotation_degrees = -360
			_tween.set_parallel(true)
			_tween.tween_property(sprite, "scale", _original_scale, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(sprite, "rotation_degrees", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		3: # NONE
			pass
			
	# 當動畫結束時發送信號
	if _tween:
		_tween.finished.connect(func(): spawn_animation_finished.emit())
	else:
		# 如果是 NONE 或動畫建立失敗，延遲發送以避免同步調用導致的死鎖
		spawn_animation_finished.emit.call_deferred()

var _preview_tween: Tween

func start_preview_shake() -> void:
	"""開始持續的預覽抖動動畫"""
	if sprite == null: return
	
	# 如果已經在播放預覽動畫，則忽略
	if _preview_tween and _preview_tween.is_valid():
		return
		
	# 確保其他動畫已停止並重置
	if _tween and _tween.is_valid():
		_tween.kill()
		
	_preview_tween = create_tween()
	_preview_tween.set_loops() # 無限循環
	
	var offset = 3.0
	var duration = 0.05
	
	# 簡單的左右快速抖動循環 (Looping)
	_preview_tween.tween_property(sprite, "position:x", _original_pos.x + offset, duration)
	_preview_tween.tween_property(sprite, "position:x", _original_pos.x - offset, duration)

func stop_preview_shake() -> void:
	"""停止預覽抖動動畫並歸位"""
	if _preview_tween:
		_preview_tween.kill()
		_preview_tween = null
	
	if sprite:
		# 使用 Tween 平滑歸位，確保位置正確
		var reset_tween = create_tween()
		reset_tween.tween_property(sprite, "position", _original_pos, 0.1)
		reset_tween.parallel().tween_property(sprite, "scale", _original_scale, 0.1)
		reset_tween.parallel().tween_property(sprite, "modulate", Color.WHITE, 0.1)

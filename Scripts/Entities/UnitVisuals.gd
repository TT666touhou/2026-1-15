extends Node
class_name UnitVisuals

@export var sprite_path: NodePath = "../Sprite2D"
@onready var sprite: Sprite2D = get_node_or_null(sprite_path)

var _original_scale: Vector2 = Vector2.ONE
var _original_pos: Vector2 = Vector2.ZERO
var _tween: Tween
var _hit_particles: GPUParticles2D

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
	
	# 初始化受擊粒子
	_setup_hit_particles.call_deferred()

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
	
	# 觸發粒子
	if _hit_particles:
		_hit_particles.global_position = sprite.global_position
		_hit_particles.restart()
	
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
	var shake_strength = 4.0
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
	# 獲取視覺根節點的引用 (可能是 Sprite 或其他)
	if not sprite: 
		spawn_animation_finished.emit.call_deferred()
		return
		
	# 停止當前任何 Tween
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	
	# 移除鎖定，遵從傳入的動畫類型
	var final_type = type_int
	
	# 重置狀態 (確保視覺歸位)
	sprite.position = _original_pos
	sprite.scale = _original_scale
	sprite.rotation = 0.0
	sprite.modulate.a = 1.0
	
	match final_type:
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
	if _tween and _tween.is_valid() and final_type != 3: # NONE (3) 不使用 Tween
		# 在動畫進行中監聽特定時刻觸發落地特效
		if type_int == 0:
			_tween.finished.connect(play_landing_effect)
		elif type_int == 1:
			_tween.finished.connect(play_landing_effect)
			
		_tween.finished.connect(func(): spawn_animation_finished.emit())
	else:
		if _tween: _tween.kill() # 清除空 Tween
		spawn_animation_finished.emit.call_deferred()

func play_landing_effect() -> void:
	"""播放角色落地時的方形煙塵特效"""
	var tex = load("res://Resources/Shared/RetroSquare.tres")
	var mat_res = load("res://Resources/Shared/LandingExplosionProcess.tres")
	if not tex or not mat_res: return
	
	var land_particles = GPUParticles2D.new()
	land_particles.name = "LandingParticles"
	
	# 獲取角色尺寸 (footprint_size)
	var size_vec = Vector2i(1, 1)
	var parent = get_parent()
	if parent and parent.has_method("get_footprint_size"):
		size_vec = parent.get_footprint_size()
	
	var footprint_scale_x: float = float(size_vec.x)
	
	# 動態調整材質參數 (建立獨特實例)
	var mat = mat_res.duplicate()
	var box_w: float = 8.0 * footprint_scale_x
	mat.emission_box_extents = Vector3(box_w, 2.0, 0.0)
	
	land_particles.process_material = mat
	land_particles.texture = tex
	land_particles.amount = int(12 * footprint_scale_x)
	land_particles.lifetime = 0.5
	land_particles.explosiveness = 1.0
	land_particles.one_shot = true
	land_particles.emitting = true
	land_particles.local_coords = false
	land_particles.z_index = 10
	land_particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	add_child(land_particles)
	# 修正位置：使用全域座標並精確對齊單位底部
	var y_offset: float = (float(size_vec.y) / 2.0) * 16.0
	land_particles.global_position = sprite.global_position + Vector2(0, y_offset)
	
	# 自動清理
	get_tree().create_timer(land_particles.lifetime + 0.1).timeout.connect(
		func(): land_particles.queue_free()
	)

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

func _setup_hit_particles() -> void:
	if not sprite or not sprite.texture: return
	
	_hit_particles = GPUParticles2D.new()
	_hit_particles.name = "HitParticles"
	add_child(_hit_particles)
	
	# 基礎配置
	_hit_particles.texture = load("res://Resources/Shared/ParticlePixel.tres")
	_hit_particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hit_particles.emitting = false
	_hit_particles.one_shot = true
	_hit_particles.amount = 24
	_hit_particles.lifetime = 0.6
	_hit_particles.explosiveness = 1.0
	_hit_particles.local_coords = false # 粒子彈出後留在世界座標，不隨角色抖動
	_hit_particles.z_index = 10 # 確保在單位上方
	
	var mat = ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.spread = 180.0
	mat.gravity = Vector3(0.0, 500.0, 0.0) # 重力向下
	mat.initial_velocity_min = 80.0
	mat.initial_velocity_max = 160.0
	mat.damping_min = 30.0
	mat.damping_max = 50.0
	
	# 縮放曲線：由大變小消失
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1), 0, 0)
	curve.add_point(Vector2(1, 0), -2.0, 0)
	var curve_tex = CurveTexture.new()
	curve_tex.curve = curve
	mat.scale_curve = curve_tex
	
	# 提取色盤
	var img = sprite.texture.get_image()
	if not img: return
	
	# 考慮 region_rect (如果開啟的話) 或 hframes/vframes (如果是動畫序列)
	var rect = sprite.region_rect if sprite.region_enabled else Rect2(0, 0, img.get_width(), img.get_height())
	
	# 如果有 hframes/vframes，我們只取第一幀來採樣 (通常第一幀具備角色主要顏色)
	if sprite.hframes > 1 or sprite.vframes > 1:
		var frame_w = rect.size.x / sprite.hframes
		var frame_h = rect.size.y / sprite.vframes
		rect = Rect2(rect.position.x, rect.position.y, frame_w, frame_h)
	
	var counts = {}
	var total_samples = 0
	
	# 抽樣掃描 (間隔 2 像素以節省效能)
	for y in range(rect.position.y, rect.end.y, 2):
		for x in range(rect.position.x, rect.end.x, 2):
			if x >= img.get_width() or y >= img.get_height(): continue
			var c = img.get_pixel(x, y)
			if c.a > 0.8: # 只取不透明色
				counts[c] = counts.get(c, 0) + 1
				total_samples += 1
	
	if total_samples > 0:
		var grad = Gradient.new()
		grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		
		var sorted_colors = counts.keys()
		sorted_colors.sort_custom(func(a, b): return counts[a] > counts[b])
		
		# 根據顏色佔比分配漸層區段 (Proportional Gradient)
		var current_offset = 0.0
		for i in range(min(sorted_colors.size(), 8)): # 最多取前 8 種主要顏色
			var c = sorted_colors[i]
			var weight = float(counts[c]) / total_samples
			
			if i == 0:
				grad.set_color(0, c)
				grad.set_offset(0, 0.0)
			elif i == 1:
				# 這裡要注意，如果 offset 很小，可能會跟第 0 個點重合
				# 但因為我們是 CONSTANT 插值，所以沒關係
				grad.set_color(1, c)
				grad.set_offset(1, max(0.01, current_offset))
			else:
				grad.add_point(current_offset, c)
			
			current_offset += weight
			if current_offset >= 1.0: break
			
		var grad_tex = GradientTexture1D.new()
		grad_tex.gradient = grad
		mat.color_initial_ramp = grad_tex
	
	_hit_particles.process_material = mat

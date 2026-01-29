extends Node
class_name UnitVisuals

@export var sprite_path: NodePath = "../Sprite2D"
@onready var sprite: Sprite2D = get_node_or_null(sprite_path)

var _original_scale: Vector2 = Vector2.ONE
var _original_pos: Vector2 = Vector2.ZERO
var _tween: Tween
var _hit_particles: GPUParticles2D
var _move_dust_particles: GPUParticles2D

signal spawn_animation_finished

func _ready() -> void:
	# 延遲獲取以確保 Sprite 已初始化
	if sprite:
		_original_scale = sprite.scale
		# 修正：強制使用 (0,0) 作為原始相對位置，避免受到初始化時的位移干擾
		_original_pos = Vector2.ZERO
	else:
		# 嘗試自動查找
		var parent = get_parent()
		if parent:
			sprite = parent.get_node_or_null("Sprite2D")
			if sprite:
				_original_scale = sprite.scale
				_original_pos = Vector2.ZERO
	
	# 初始化受擊粒子與牆體碰撞粒子
	_setup_visual_particles.call_deferred()
	# _setup_move_dust_particles.call_deferred() # 已停用沙塵特效

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

func play_skill_cast_visual() -> void:
	"""播放施法時的壓縮與放大動畫"""
	if sprite == null: return
	
	if _tween and _tween.is_valid():
		_tween.kill()
		
	sprite.scale = _original_scale
	_tween = create_tween()
	
	# 1. 快速壓縮 (Squash)
	_tween.tween_property(sprite, "scale", _original_scale * Vector2(1.4, 0.6), 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# 2. 彈力放大 (Stretch/Pop)
	_tween.chain().tween_property(sprite, "scale", _original_scale * Vector2(0.8, 1.2), 0.1)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
	# 3. 恢復原狀
	_tween.chain().tween_property(sprite, "scale", _original_scale, 0.3)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

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
	_tween.chain().tween_property(sprite, "position", _original_pos, step_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func play_death_animation() -> void:
	"""播放死亡時的縮小與淡出動畫"""
	if sprite == null: return
	
	if _tween and _tween.is_valid():
		_tween.kill()
		
	_tween = create_tween()
	_tween.set_parallel(true)
	
	# 1. 縮小並旋轉
	_tween.tween_property(sprite, "scale", Vector2.ZERO, 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_property(sprite, "rotation_degrees", 180.0, 0.4)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	# 2. 淡出
	_tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	
	# 3. 觸發受擊粒子作為死亡碎裂感
	if _hit_particles:
		_hit_particles.amount = 32 # 增加粒子數量
		_hit_particles.restart()

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
	
	# 獲取視覺根節點的引用
	if not sprite: 
		_finalize_spawn()
		return
	
	# 重置狀態 (確保視覺歸位)
	if not _original_pos.is_zero_approx():
		sprite.position = _original_pos
	else:
		sprite.position = Vector2.ZERO
		
	sprite.scale = _original_scale
	sprite.rotation = 0.0
	sprite.modulate.a = 1.0
	
	# 如果有 AnimationPlayer，確保它在進場前不會播放預設動畫干擾
	var anim_player = get_parent().get_node_or_null("AnimationPlayer")
	if anim_player:
		anim_player.stop()
	
	# 只有在需要動畫時才創建 Tween
	if type_int == 3: # NONE
		_finalize_spawn()
		return

	_tween = create_tween()
	match type_int:
		0: # DROP
			sprite.position.y = _original_pos.y - 300
			sprite.modulate.a = 0.0
			_tween.set_parallel(true)
			_tween.tween_property(sprite, "position:y", _original_pos.y, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_tween.tween_property(sprite, "modulate:a", 1.0, 0.3)
			_tween.chain().tween_callback(play_landing_effect)
			
		1: # LEAP (模擬拋物線)
			var start_offset = Vector2(-100, -100)
			sprite.position = _original_pos + start_offset
			sprite.modulate.a = 0.0
			_tween.set_parallel(true)
			_tween.tween_property(sprite, "modulate:a", 1.0, 0.2)
			_tween.tween_property(sprite, "position:x", _original_pos.x, 0.5)
			_tween.tween_property(sprite, "position:y", _original_pos.y, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_tween.chain().tween_callback(play_landing_effect)
			
		2: # POP
			sprite.scale = Vector2.ZERO
			sprite.rotation_degrees = -360
			_tween.set_parallel(true)
			_tween.tween_property(sprite, "scale", _original_scale, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(sprite, "rotation_degrees", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	_tween.finished.connect(_finalize_spawn)

func _finalize_spawn() -> void:
	"""統一處理進場後的恢復邏輯"""
	spawn_animation_finished.emit()
	
	# 確保 Sprite 可見
	if sprite:
		sprite.modulate.a = 1.0
		
	# 恢復 AnimationPlayer 的循環動畫 (如 idle)
	var parent = get_parent()
	if is_instance_valid(parent):
		var anim_player = parent.get_node_or_null("AnimationPlayer")
		if anim_player and anim_player.has_animation("idle"):
			anim_player.play("idle")

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
	land_particles.top_level = true
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

func _setup_visual_particles() -> void:
	if not sprite or not sprite.texture: return
	
	# 1. 設置基礎受擊粒子 (HitParticles)
	_hit_particles = GPUParticles2D.new()
	_hit_particles.name = "HitParticles"
	add_child(_hit_particles)
	_setup_base_particle_config(_hit_particles)
	_hit_particles.amount = 24
	
	# 2. 設置牆體碰撞粒子 (由 GridEntity 控制)
	var parent = get_parent()
	var wall_particles = {
		"CollisionParticles_Left": Vector3(1, 0, 0),
		"CollisionParticles_Right": Vector3(-1, 0, 0),
		"CollisionParticles_Top": Vector3(0, 1, 0),
		"CollisionParticles_Bottom": Vector3(0, -1, 0)
	}
	
	var styled_mat = _create_styled_material()
	
	# 套用到受擊粒子
	var hit_mat = styled_mat.duplicate()
	hit_mat.spread = 180.0
	hit_mat.gravity = Vector3(0, 500, 0)
	hit_mat.initial_velocity_min = 80.0
	hit_mat.initial_velocity_max = 160.0
	_hit_particles.process_material = hit_mat
	
	# 套用到牆體粒子 (動態建立缺失的節點)
	for p_name in wall_particles:
		var p_node = parent.get_node_or_null(p_name) as GPUParticles2D
		if not p_node:
			# 動態建立粒子節點
			p_node = GPUParticles2D.new()
			p_node.name = p_name
			parent.add_child(p_node)
			
			# 根據名稱設定位置偏移
			var offset = 8.0
			if parent.has_method("get_footprint_size"):
				var size = parent.get_footprint_size()
				offset = (max(size.x, size.y) / 2.0) * 16.0
				
			match p_name:
				"CollisionParticles_Left": p_node.position = Vector2(-offset, 0)
				"CollisionParticles_Right": p_node.position = Vector2(offset, 0)
				"CollisionParticles_Top": p_node.position = Vector2(0, -offset)
				"CollisionParticles_Bottom": p_node.position = Vector2(0, offset)
		
		_setup_base_particle_config(p_node)
		# 核心修正：確保牆體粒子可見
		p_node.top_level = false
		p_node.z_index = 10 
		p_node.z_as_relative = true
		
		var mat = styled_mat.duplicate()
		mat.direction = wall_particles[p_name]
		mat.spread = 45.0
		mat.gravity = Vector3(0, 0, 0)
		mat.initial_velocity_min = 100.0
		mat.initial_velocity_max = 200.0
		p_node.process_material = mat

func play_wall_collision_fx(normal: Vector2) -> void:
	"""根據碰撞法線播放對應的牆體粒子與音效"""
	var p_name = ""
	if abs(normal.x) > abs(normal.y):
		# 橫向碰撞
		p_name = "CollisionParticles_Left" if normal.x > 0.5 else "CollisionParticles_Right"
	else:
		# 縱向碰撞
		p_name = "CollisionParticles_Top" if normal.y > 0.5 else "CollisionParticles_Bottom"
	
	var parent = get_parent()
	if parent:
		var p_node = parent.get_node_or_null(p_name) as GPUParticles2D
		if p_node:
			# 確保位置正確 (對齊當前全域座標)
			p_node.global_position = parent.global_position + p_node.position
			p_node.restart()
			p_node.emitting = true
			print("[UnitVisuals] Triggering wall particles: %s for %s at %s" % [p_name, parent.name, p_node.global_position])
	
	# 透過全域 AudioManager 播放音效，對接 Setting 系統
	var am = get_node_or_null("/root/AudioManager")
	if am:
		# 將音量從 -5.0 提升至 0.0 (標準音量)
		am.play_sfx_2d("wall_collision", parent.global_position if parent else Vector2.ZERO, 0.0)

func _setup_base_particle_config(p: GPUParticles2D) -> void:
	p.texture = load("res://Resources/Shared/ParticlePixel.tres")
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.top_level = true
	p.z_index = 10
	p.lifetime = 0.6

func _create_styled_material() -> ParticleProcessMaterial:
	var mat = ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.damping_min = 30.0
	mat.damping_max = 50.0
	
	# 縮放曲線 (調整為與受擊碎片一致的像素感)
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1), 0, 0)
	curve.add_point(Vector2(1, 0), -2.0, 0)
	var curve_tex = CurveTexture.new()
	curve_tex.curve = curve
	mat.scale_curve = curve_tex
	
	# 基礎縮放 (確保粒子不會過大)
	mat.scale_min = 1.0
	mat.scale_max = 1.0
	
	# 顏色採樣
	var img = sprite.texture.get_image()
	if not img: return mat
	
	var rect = sprite.region_rect if sprite.region_enabled else Rect2(0, 0, img.get_width(), img.get_height())
	if sprite.hframes > 1 or sprite.vframes > 1:
		var frame_w = rect.size.x / sprite.hframes
		var frame_h = rect.size.y / sprite.vframes
		rect = Rect2(rect.position.x, rect.position.y, frame_w, frame_h)
	
	var counts = {}
	var total_samples = 0
	for y in range(rect.position.y, rect.end.y, 2):
		for x in range(rect.position.x, rect.end.x, 2):
			if x >= img.get_width() or y >= img.get_height(): continue
			var c = img.get_pixel(x, y)
			if c.a > 0.8:
				counts[c] = counts.get(c, 0) + 1
				total_samples += 1
	
	if total_samples > 0:
		var grad = Gradient.new()
		grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		var sorted_colors = counts.keys()
		sorted_colors.sort_custom(func(a, b): return counts[a] > counts[b])
		
		var current_offset = 0.0
		for i in range(min(sorted_colors.size(), 8)):
			var c = sorted_colors[i]
			var weight = float(counts[c]) / total_samples
			if i == 0:
				grad.set_color(0, c)
				grad.set_offset(0, 0.0)
			elif i == 1:
				grad.set_color(1, c)
				grad.set_offset(1, max(0.01, current_offset))
			else:
				grad.add_point(current_offset, c)
			current_offset += weight
			if current_offset >= 1.0: break
			
		var grad_tex = GradientTexture1D.new()
		grad_tex.gradient = grad
		mat.color_initial_ramp = grad_tex
	
	return mat

func _setup_hit_particles() -> void:
	# 此函數已被 _setup_visual_particles 取代
	pass

func _setup_move_dust_particles() -> void:
	"""初始化移動時的沙塵粒子"""
	var tex = load("res://Resources/Shared/RetroSquare.tres")
	var mat_res = load("res://Resources/Shared/LandingExplosionProcess.tres")
	if not tex or not mat_res: 
		print("[UnitVisuals] ERROR: Could not load dust resources: ", tex, " | ", mat_res)
		return
	
	_move_dust_particles = GPUParticles2D.new()
	_move_dust_particles.name = "MoveDustParticles"
	
	# 建立獨特的材質實例並調整為持續噴發感
	var mat = mat_res.duplicate()
	mat.emission_box_extents = Vector3(4.0, 1.0, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 40.0
	mat.gravity = Vector3(0, -10, 0) # 輕微向上飄
	
	_move_dust_particles.process_material = mat
	_move_dust_particles.texture = tex
	_move_dust_particles.amount = 12
	_move_dust_particles.lifetime = 0.4
	_move_dust_particles.explosiveness = 0.0 # 持續噴發
	_move_dust_particles.emitting = false
	_move_dust_particles.local_coords = false # 粒子留在路徑上
	_move_dust_particles.top_level = false # 核心修正：作為子節點跟隨
	_move_dust_particles.z_index = 1000 # 保持置頂
	_move_dust_particles.z_as_relative = false
	_move_dust_particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	add_child(_move_dust_particles)
	# 核心修正：將粒子掛載到擁有座標的父節點 (GridEntity)
	if _move_dust_particles.get_parent():
		_move_dust_particles.get_parent().remove_child(_move_dust_particles)
	get_parent().add_child(_move_dust_particles)
	
	print("[UnitVisuals] MoveDustParticles initialized and attached to parent: ", get_parent().name)
	
	# 初始位置設在腳下
	var size_y = 16.0
	var parent = get_parent()
	if parent and parent.has_method("get_footprint_size"):
		size_y = (float(parent.get_footprint_size().y) / 2.0) * 16.0
	_move_dust_particles.position = Vector2(0, size_y)

func set_moving_fx(enabled: bool) -> void:
	"""開啟或關閉移動特效"""
	if _move_dust_particles:
		if enabled:
			# 更新相對座標到單位腳下 (相對於 GridEntity)
			var size_y = 8.0
			var parent = get_parent()
			if parent and parent.has_method("get_footprint_size"):
				size_y = (float(parent.get_footprint_size().y) / 2.0) * 16.0
			
			_move_dust_particles.position = Vector2(0, size_y)
		
		if _move_dust_particles.emitting != enabled:
			var parent_name = get_parent().name
			var g_pos = _move_dust_particles.global_position
			var z = _move_dust_particles.z_index
			print("[UnitVisuals] Dust for %s | Emitting: %s | GPos: %s | Z: %d" % [parent_name, enabled, g_pos, z])
		
		_move_dust_particles.emitting = enabled

extends Control

# 拖曳預覽控制器
# 負責顯示單位的實際場景，並提供拖曳時的物理搖晃效果

var content_node: Node2D
var _last_global_pos: Vector2
var _oscillator_velocity: float = 0.0
var _oscillator_displacement: float = 0.0
var enable_debug_log: bool = true

# 物理參數 (參考 GridSelector)
const ROTATION_SPRING: float = 150.0
const ROTATION_DAMP: float = 10.0
# 速度乘數，控制搖晃靈敏度
# GridSelector 使用的是 1.0, 且使用 normalized velocity
# 這裡我們也需要調整，因為 UI 座標系與 World 座標系可能有差異，且 _get_drag_data 的更新頻率可能不同
const VELOCITY_MULTIPLIER: float = 1.0

var _last_targets: Dictionary = {}
var _active_preview_targets: Dictionary = {}

func setup_with_data(scene: PackedScene, data: CharacterData) -> void:
	if scene == null:
		return
		
	# 實例化單位場景
	content_node = scene.instantiate()
	
	# 禁用單位的遊戲邏輯 (避免在預覽時觸發 _ready 或 _process 中的遊戲邏輯)
	content_node.process_mode = Node.PROCESS_MODE_DISABLED
	
	# 添加到容器
	add_child(content_node)
	
	# 居中放置 (用戶指定 (0,0))
	content_node.position = Vector2.ZERO
	
	# 放大四倍 (配合 Camera 縮放)
	content_node.scale = Vector2(4, 4)
	
	# 手動應用數據以顯示箭頭
	var card_provider = content_node.get_node_or_null("CardProvider")
	if card_provider:
		if enable_debug_log: print("[DragPreview] Found CardProvider")
		if data.unit_def:
			if enable_debug_log: print("[DragPreview] Applying unit_def: ", data.unit_def)
			# CardProvider 會自動觸發 MovementDirectionIndicator 的更新
			card_provider.set_card_and_apply(data.unit_def)
		else:
			if enable_debug_log: print("[DragPreview] Error: data.unit_def is null")
	else:
		if enable_debug_log: print("[DragPreview] Error: CardProvider not found on content_node")
			
	# 強制更新箭頭可見性 (如果節點初始化順序導致未顯示)
	# ArrowIndicators 已被移除，此段代碼已廢棄
	
	_last_global_pos = global_position

func setup_with_scene(scene: PackedScene) -> void:
	# 舊方法保留相容性
	setup_with_data(scene, null)

func _process(delta: float) -> void:
	if content_node == null:
		return

	# 1. 計算全域移動速度
	var current_pos = global_position
	# 使用 global_position 的變化來計算速度
	var velocity = (current_pos - _last_global_pos) / delta
	_last_global_pos = current_pos
	
	# 2. 應用 Oscillator 物理邏輯
	if velocity.length() > 0.0:
		# 根據 X 軸移動方向施加力 (產生左右搖晃)
		# 參考 GridSelector: velocity.normalized().x * VELOCITY_MULTIPLIER
		_oscillator_velocity += velocity.normalized().x * VELOCITY_MULTIPLIER
		
	var force = -ROTATION_SPRING * _oscillator_displacement - ROTATION_DAMP * _oscillator_velocity
	_oscillator_velocity += force * delta
	_oscillator_displacement += _oscillator_velocity * delta
	
	# 3. 應用旋轉到內部節點
	content_node.rotation = _oscillator_displacement
	
	# 4. 攻擊預覽
	_update_attack_preview()

var _last_debug_grid_pos: Vector2i = Vector2i(-999, -999)

func _update_attack_preview() -> void:
	if content_node == null or not content_node.has_method("get_attack_targets"):
		return
		
	# 獲取 Grid (嘗試從場景獲取，因為 DragPreview 可能不在 Grid 的子樹中)
	var grid = get_tree().get_first_node_in_group("grid")
	if grid == null:
		if enable_debug_log: print_rich("[color=red][DragPreview] Error: Grid not found![/color]")
		return
		
	# --- 座標轉換修正 ---
	var world_pos = global_position
	var viewport = get_viewport()
	var camera = viewport.get_camera_2d()
	
	if camera:
		# 獲取滑鼠在 Viewport 中的位置 (屏幕座標)
		var screen_pos = viewport.get_mouse_position()
		# 使用 CanvasTransform 將屏幕座標轉換為世界座標
		# 這考慮了 Camera 的縮放和位置
		world_pos = (screen_pos - viewport.canvas_transform.origin) / viewport.canvas_transform.get_scale()
	else:
		# 如果沒有 Camera，假設 UI 和 World 1:1 (通常不正確，但作為後備)
		pass
		
	# 計算當前 Grid 位置
	var grid_pos = grid.world_to_grid(world_pos)
	
	# --- Debug Log (防止洪水) ---
	if enable_debug_log and grid_pos != _last_debug_grid_pos:
		print("[DragPreview] Grid Pos: ", grid_pos, " | World Pos: ", world_pos)
		_last_debug_grid_pos = grid_pos
		
		# 檢查 Data 完整性
		if content_node.get("movement_range_data") == null:
			print_rich("[color=yellow][DragPreview] Warning: ContentNode has NO MovementRangeData![/color]")
	
	# 獲取當前所有目標
	var results = content_node.get_attack_results(grid_pos)
	
	# 如果發現目標，打印詳細信息
	if enable_debug_log and not results.is_empty() and grid_pos != _last_debug_grid_pos:
		print_rich("[color=green][DragPreview] Targets found at %s: %s[/color]" % [grid_pos, results.size()])
	
	# 使用 AttackManager 計算全局 Combo 預覽
	var combo_results = {}
	if AttackManager:
		combo_results = AttackManager.calculate_preview_combos(content_node as GridEntity, grid_pos)
	
	# 這裡我們使用 combo_results 的 keys 作為目標集合，因為它包含了所有被攻擊的目標
	# 如果 AttackManager 不可用，則退回到 targets (僅顯示自己打的)
	var current_targets = []
	if not combo_results.is_empty():
		current_targets = combo_results.keys()
	else:
		current_targets = results.keys()

	# 1. 更新現有目標與新增目標
	for target in current_targets:
		# 啟動抖動預覽
		if not _active_preview_targets.has(target):
			# Fix: Ensure target is a valid Node before calling get_node_or_null
			if not is_instance_valid(target) or not target is Node:
				continue
				
			var visuals = target.get_node_or_null("UnitVisuals")
			if visuals and visuals.has_method("start_preview_shake"):
				visuals.start_preview_shake()
				_active_preview_targets[target] = visuals
				if enable_debug_log: print("[DragPreview] Start preview shake on: ", target.name)
		
		# 更新 Combo UI
		pass

	# 2. 處理移除目標
	var targets_to_remove = []
	for active_target in _active_preview_targets:
		if not active_target in current_targets:
			# 停止抖動
			var visuals = _active_preview_targets[active_target]
			if visuals and visuals.has_method("stop_preview_shake"):
				visuals.stop_preview_shake()
			
			# 隱藏 Combo UI
			pass
				
			targets_to_remove.append(active_target)
			if enable_debug_log: print("[DragPreview] Stop preview shake on: ", active_target.name)
			
	for t in targets_to_remove:
		_active_preview_targets.erase(t)
	
	_last_targets = results
	
func _exit_tree() -> void:
	# 清理所有殘留的動畫和 UI
	for target in _active_preview_targets:
		var visuals = _active_preview_targets[target]
		if visuals and visuals.has_method("stop_preview_shake"):
			visuals.stop_preview_shake()
	_active_preview_targets.clear()

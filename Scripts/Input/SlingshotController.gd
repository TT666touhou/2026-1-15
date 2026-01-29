extends Node
class_name SlingshotController

## 彈弓射擊控制器 (Pool Style)
## 往後拉，往前射

signal unit_selected(unit: GridEntity)

@export var force_multiplier: float = 4.0
@export var max_drag_distance: float = 75.0

var selected_unit: GridEntity = null
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var launch_arrow: Line2D
var _current_swing_angle: float = 0.0
var _swing_tween: Tween = null
var _current_raw_diff: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("slingshot")
	launch_arrow = Line2D.new()
	launch_arrow.width = 3.0
	launch_arrow.default_color = Color.YELLOW
	launch_arrow.z_index = 100
	add_child(launch_arrow)
	launch_arrow.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if TurnManager and TurnManager.is_busy():
					return
				_try_select_unit()
			elif is_dragging:
				_launch_unit()

	elif event is InputEventMouseMotion and is_dragging:
		_update_drag_visual()

func _process(_delta: float) -> void:
	if is_dragging and selected_unit:
		_refresh_arrow_points()

func _try_select_unit() -> void:
	var camera = get_viewport().get_camera_2d()
	if not camera: return
	
	var mouse_pos = camera.get_global_mouse_position()
	var space_state = get_viewport().get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collision_mask = 1 # Unit Layer
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var results = space_state.intersect_point(query)
	for res in results:
		var collider = res.collider
		if collider is GridEntity:
			var is_controllable = collider.is_player or (collider.faction and collider.faction.is_controllable) or collider.is_in_group("player")
			if is_controllable:
				selected_unit = collider
				is_dragging = true
				drag_start_pos = mouse_pos
				launch_arrow.visible = true
				unit_selected.emit(selected_unit)
				
				# 檢查混亂狀態並啟動動畫
				var is_confused = false
				var status_mgr = selected_unit.get_node_or_null("StatusManager") as StatusManager
				if status_mgr:
					is_confused = status_mgr.active_statuses.has("confusion")
				elif selected_unit.character_data:
					is_confused = selected_unit.character_data.is_confused
				
				if is_confused:
					_start_swing_animation()
				else:
					_current_swing_angle = 0.0
				
				break

func _update_drag_visual() -> void:
	if not selected_unit: return
	
	var camera = get_viewport().get_camera_2d()
	var current_mouse = camera.get_global_mouse_position()
	
	# 核心修正：將滑鼠位置轉換為相對於設計解析度的座標空間
	# 這樣無論視窗如何縮放，150 像素的拖曳距離在視覺上佔比都一樣
	var viewport_transform = get_viewport().get_final_transform()
	var drag_start_local = viewport_transform * drag_start_pos
	var current_mouse_local = viewport_transform * current_mouse
	_current_raw_diff = (drag_start_local - current_mouse_local) / viewport_transform.get_scale().x
	
	if _current_raw_diff.length() > max_drag_distance:
		_current_raw_diff = _current_raw_diff.normalized() * max_drag_distance
	
	_refresh_arrow_points()

func _refresh_arrow_points() -> void:
	if not selected_unit or not is_dragging: return
	
	var diff = _current_raw_diff
	
	var is_confused_status = false
	var status_mgr = selected_unit.get_node_or_null("StatusManager") as StatusManager
	if status_mgr:
		is_confused_status = status_mgr.active_statuses.has("confusion")
	elif selected_unit.character_data:
		is_confused_status = selected_unit.character_data.is_confused
		
	if is_confused_status:
		diff = diff.rotated(_current_swing_angle)
		launch_arrow.default_color = Color(0.8, 0.5, 1.0)
	else:
		var intensity = diff.length() / max_drag_distance
		launch_arrow.default_color = Color(1.0, 1.0 - intensity * 0.5, 0.0)
	
	launch_arrow.clear_points()
	launch_arrow.add_point(selected_unit.global_position)
	launch_arrow.add_point(selected_unit.global_position + diff)

func _start_swing_animation() -> void:
	_stop_swing_animation()
	_swing_tween = create_tween()
	_swing_tween.set_loops() # 無限循環
	
	var swing_range = deg_to_rad(35.0)
	# 擺動週期：從 0 到 35，再到 -35，最後回到 0，總共 0.5 秒完成一次完整來回
	_swing_tween.tween_property(self, "_current_swing_angle", swing_range, 0.125).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(self, "_current_swing_angle", -swing_range, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(self, "_current_swing_angle", 0.0, 0.125).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _stop_swing_animation() -> void:
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing_tween = null
	_current_swing_angle = 0.0

func _launch_unit() -> void:
	if not selected_unit: return
	
	var camera = get_viewport().get_camera_2d()
	var current_mouse = camera.get_global_mouse_position()
	
	# 核心修正：使用與視覺一致的縮放座標計算發射力道
	var viewport_transform = get_viewport().get_final_transform()
	var drag_start_local = viewport_transform * drag_start_pos
	var current_mouse_local = viewport_transform * current_mouse
	var raw_diff = (drag_start_local - current_mouse_local) / viewport_transform.get_scale().x
	
	if raw_diff.length() > 15:
		var final_diff = raw_diff
		var is_confused_launch = false
		var status_mgr = selected_unit.get_node_or_null("StatusManager") as StatusManager
		if status_mgr:
			is_confused_launch = status_mgr.active_statuses.has("confusion")
		elif selected_unit.character_data:
			is_confused_launch = selected_unit.character_data.is_confused
			
		if is_confused_launch:
			final_diff = raw_diff.rotated(_current_swing_angle)
			# 發射後解除混亂 (如果是 StatusManager 管理，則移除狀態)
			if status_mgr and status_mgr.active_statuses.has("confusion"):
				status_mgr.active_statuses.erase("confusion")
				status_mgr.status_removed.emit("confusion")
			elif selected_unit.character_data:
				selected_unit.character_data.is_confused = false
			print("[Slingshot] Confused launch executed! Angle offset: ", rad_to_deg(_current_swing_angle))
		var effective_speed = 1.0
		if selected_unit.character_data:
			effective_speed = selected_unit.character_data.get_effective_speed()
			
		var current_force_multiplier = effective_speed * 600.0 / max_drag_distance
		var force = final_diff.limit_length(max_drag_distance) * current_force_multiplier
			
		if selected_unit.has_method("launch"):
			selected_unit.launch(force)
		else:
			if selected_unit is RigidBody2D:
				selected_unit.apply_central_impulse(force)
		
		if TurnManager and TurnManager.has_method("on_unit_launched"):
			TurnManager.on_unit_launched(selected_unit, force)
	
	_stop_swing_animation()
	is_dragging = false
	selected_unit = null
	launch_arrow.visible = false
	launch_arrow.clear_points()

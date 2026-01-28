extends Control
class_name Hand

# 預載入 FootprintData 以確保類型可被找到
const FootprintDataScript = preload("res://Footprints/FootprintData.gd")

@export var card_scene: PackedScene
# 手牌區的卡牌大小，預設維持 80x120
@export var hand_card_size: Vector2 = Vector2(80, 120)
@export var spacing: float = 100.0
@export var card_spread_angle: float = 30.0
@export var rotation_curve: Curve
@export var y_offset_curve: Curve
@export var hand_bottom_offset: float = 140.0
@export var lock_offset_y: float = 80.0 # Distance to move down when locked

var _lock_y_shift: float = 0.0
var _tween_lock: Tween = null

@export var reflow_on_release: bool = true
@export var reflow_on_drag_preview: bool = true
@export var swap_animation_duration: float = 0.2
@export var swap_ease: int = Tween.EASE_OUT
@export var swap_trans: int = Tween.TRANS_CUBIC
@export var insert_threshold_px: float = 24.0
@export var use_center_for_insert: bool = true
@export var placeholder_scale: float = 0.9
@export var enable_debug_log: bool = false

var cards: Array = []
var selected_cards: Array = []

const LEDGER_NODE_NAME := "PlayerResourceLedger"
const DEFAULT_COST_RESOURCE := StringName("soul")

# Drag-reorder state
var dragging_card: Node = null
var drag_from_idx: int = -1
var preview_insert_idx: int = -1
var is_interactable: bool = true # 是否可交互

# Hand border reference (created at runtime)
var _hand_border: Node = null


func set_interactable(value: bool) -> void:
	# if enable_debug_log:
	# 	print("[Hand] set_interactable: ", value)
		
	if is_interactable == value:
		return
		
	is_interactable = value
	
	# Animate UI position (Lock/Unlock visualization)
	if _tween_lock and _tween_lock.is_running():
		_tween_lock.kill()
	_tween_lock = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	
	var target_shift: float = 0.0
	if not value: # Locked
		target_shift = lock_offset_y
		
	_tween_lock.tween_method(_update_lock_shift, _lock_y_shift, target_shift, 0.3)
	
	# 更新所有卡牌的視覺狀態
	for c in cards:
		if c.has_method("set_interactable"):
			c.set_interactable(value)
		elif "interactable" in c:
			c.interactable = value
			
		# Visual feedback (Modulate if no custom method handles it, or just consistent feedback)
		if not c.has_method("set_interactable"):
			c.modulate = Color.WHITE if value else Color(0.5, 0.5, 0.5, 1)
	
	# 如果變為不可交互，取消任何進行中的拖曳
	if not value and dragging_card != null:
		cancel_drag()
		_arrange()

func _update_lock_shift(val: float) -> void:
	_lock_y_shift = val
	_arrange(false) # Update layout without internal card tweens

func _ready() -> void:
	# 強制層級與可見性
	z_index = 500
	visible = true
	
	
	# 向 DeckManager 註冊自己 (確保 Autoload 知道要往哪發牌)
	if DeckManager:
		DeckManager.register_hand(self)
		
	# 確保 Hand 的根節點不攔截滑鼠輸入，允許點擊穿透到遊戲世界
	mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	# Defer arrange to ensure viewport size available
	call_deferred("_arrange")
	# Create hand border UI at runtime
	var ui = get_parent()
	if ui:
		var border_scene: PackedScene = load("res://Scenes/UI/HandBorder.tscn")
		if border_scene:
			_hand_border = border_scene.instantiate()
			ui.call_deferred("add_child", _hand_border)
			if _hand_border:
				_hand_border.call_deferred("configure_from_hand", self)
				_hand_border.call_deferred("update_layout", get_viewport().get_visible_rect())

func add_card(data, start_global_pos = null):
	# print("[Hand] add_card called with data: ", data)
	
	# 強制顯示手牌區域及其父節點
	visible = true
	if get_parent() is Control:
		get_parent().visible = true
	# print("[Hand Debug] FORCED VISIBILITY. Hand: %s, Parent: %s" % [visible, get_parent().visible if get_parent() else "N/A"])
	
	var c = null
	if card_scene != null:
		c = card_scene.instantiate()
		# print("[Hand] Card instance created from scene: ", card_scene.resource_path)
	else:
		c = Card.new()
		# print("[Hand] Card instance created via Card.new()")
	
	add_child(c)
	# print("[Hand] Card added as child of Hand. Current child count: ", get_child_count())
	
	# 應用手牌區專屬尺寸
	if c.get("card_size") != null:
		c.card_size = hand_card_size
		# print("[Hand] Applied card_size: ", hand_card_size)
		
	c.set_card_data(data)
	cards.append(c)
	
	# 如果提供了起始位置，設置初始狀態以便動畫
	if start_global_pos is Vector2:
		c.global_position = start_global_pos
		c.scale = Vector2(0.1, 0.1) # 縮小
		c.rotation = randf_range(-PI, PI) # 隨機旋轉
	
	# Connect selection signals
	if c.has_signal("selection_toggled"):
		c.selection_toggled.connect(_on_card_selection_toggled)
	if c.has_signal("request_deselect_all"):
		c.request_deselect_all.connect(_on_card_request_deselect_all)
	
	# print("[Hand] Triggering layout (_arrange)...")
	_arrange()
	return c

func _on_card_selection_toggled(card) -> void:
	if card.is_selected:
		_deselect_card(card)
	else:
		_select_card(card)

func _on_card_request_deselect_all() -> void:
	deselect_all()

func _select_card(card) -> void:
	if not card in selected_cards:
		card.is_selected = true
		selected_cards.append(card)
		_arrange()

func _deselect_card(card) -> void:
	if card in selected_cards:
		card.is_selected = false
		selected_cards.erase(card)
		_arrange()

func deselect_all() -> void:
	for card in selected_cards:
		card.is_selected = false
	selected_cards.clear()
	_arrange()

func is_dragging() -> bool:
	return dragging_card != null

func begin_drag(card) -> void:
	if not is_interactable:
		return
		
	dragging_card = card
	
	# 開始拖拽時，隱藏任何懸浮資訊 (如技能說明)
	var controller = get_tree().get_first_node_in_group("hover_info_controller")
	if controller and controller.has_method("_hide_all"):
		controller.call("_hide_all")
		
	drag_from_idx = cards.find(card)
	preview_insert_idx = drag_from_idx
	
	# If the card is selected, we drag the whole selection
	if card.is_selected:
		for c in selected_cards:
			c.z_index = 1000
			c._original_global_position = c.global_position
	else:
		card.z_index = 1000
		
	if reflow_on_drag_preview and not card.is_selected:
		_arrange()

func on_drag_move(mouse_global_pos: Vector2) -> void:
	if dragging_card == null:
		return
	
	if dragging_card.is_selected:
		# Unified Fan layout for ALL selected cards while dragging
		var count = selected_cards.size()
		# var time = Time.get_ticks_msec() / 1000.0
		
		# Shared anchor: exactly on mouse
		var base_pos = mouse_global_pos
		
		# Parameters for a more upright and clean spread
		var fan_spacing = 45.0   # Horizontal distance
		var fan_rotation = 0.08  # Very slight rotation for a natural but "straight" look
		var fan_y_curve = 5.0    # Minimal vertical arc
		
		var center_idx = (count - 1) * 0.5
		
		for i in range(count):
			var c = selected_cards[i]
			var offset = i - center_idx
			
			var target_x = base_pos.x + (offset * fan_spacing)
			var target_y = base_pos.y + (abs(offset) * fan_y_curve)
			var target_rot = offset * fan_rotation
			
			# Ensure no other script or animation is moving this
			if c.has_method("kill_tweens"): c.call("kill_tweens")
			
			c.z_index = 2000 + i 
			c.global_position = Vector2(target_x - 40, target_y - 60)
			c.rotation = target_rot
			c.scale = Vector2(1.2, 1.2)
	else:
		# Regular reorder drag
		var viewport_rect := get_viewport().get_visible_rect()
		var height := viewport_rect.size.y
		if height <= 0.0:
			height = get_window().size.y
		var base_list: Array = []
		for c in cards:
			if c == dragging_card:
				continue
			base_list.append(c)
		var count := base_list.size() + 1
		var center_index := (count - 1) * 0.5
		var best_idx: int = 0
		var best_dist: float = INF
		
		# 使用 Hand 節點自身的全域中心點
		var hand_center_x := get_global_rect().get_center().x
		
		for i in range(count):
			var local_x := (i - center_index) * spacing
			var x := hand_center_x + local_x - 40.0
			var d: float = abs(mouse_global_pos.x - x)
			if d < best_dist:
				best_dist = d
				best_idx = i
		if best_idx != preview_insert_idx:
			preview_insert_idx = best_idx
			if reflow_on_drag_preview:
				_arrange()
	

func end_drag() -> void:
	if dragging_card == null:
		return
	
	var mouse_pos = get_global_mouse_position()
	
	# 1. Highest Priority: Disposal Zone
	var zone = get_tree().get_first_node_in_group("disposal_zone")
	if zone and zone.get_global_rect().has_point(mouse_pos):
		if dragging_card.is_selected:
			# Discard all selected
			var to_discard = selected_cards.duplicate()
			deselect_all()
			for c in to_discard:
				request_dispose(c, mouse_pos)
		else:
			request_dispose(dragging_card, mouse_pos)
		dragging_card = null
		return

	# 2. Check forbidden UI area (LeftPanel of DeploymentUI)
	# var in_forbidden_ui := false
	var deployment_ui = get_tree().get_first_node_in_group("deployment_ui")
	if deployment_ui:
		# var panel = deployment_ui.get_node_or_null("LeftPanel")
		# if panel and panel.get_global_rect().has_point(mouse_pos):
		# 	in_forbidden_ui = true
		pass

	# 3. Check Hand Area
	var in_hand = is_point_in_hand_area(mouse_pos)

	# 4. Final Decision
	if dragging_card.is_selected:
		# If outside hand and outside left UI -> PLACING logic (if applicable)
		# For now, selected cards play logic is removed if it was purely poker-based.
		# If we still want to play them as individual actions, we could implement that here.
		# For now, just return to hand if no specific play logic is defined.
		for c in selected_cards:
			c.return_to_hand(true)
	else:
		# Regular card (not selected): only reorder if inside hand
		if in_hand:
			var base_list: Array = []
			for c in cards:
				if c == dragging_card: continue
				base_list.append(c)
			var insert_idx: int = clamp(preview_insert_idx, 0, base_list.size())
			base_list.insert(insert_idx, dragging_card)
			cards = base_list
			dragging_card.return_to_hand(true)
		else:
			# Outside hand area: TRY TO PLACE/PLAY
			_handle_card_placement(dragging_card, mouse_pos)
	
	dragging_card = null
	drag_from_idx = -1
	preview_insert_idx = -1
	_arrange()

## Helper to handle card placement
func _handle_card_placement(card, pos: Vector2) -> void:
	var played = request_place(card, pos)
	if not played and is_instance_valid(card):
		card.return_to_hand(true)
	_arrange()

func remove_last() -> void:
	if cards.is_empty():
		return
	var c = cards.pop_back()
	if is_instance_valid(c):
		c.queue_free()
	_arrange()

func remove_card(card) -> void:
	if card in cards:
		cards.erase(card)
		# 如果移除的是正在拖拽的卡片，清理拖拽狀態
		if card == dragging_card:
			dragging_card = null
			drag_from_idx = -1
			preview_insert_idx = -1
		if is_instance_valid(card):
			card.queue_free()
		_arrange()

func detach_card(card) -> void:
	if card in cards:
		cards.erase(card)
		if card == dragging_card:
			dragging_card = null
			drag_from_idx = -1
			preview_insert_idx = -1
		_arrange()

func get_card_count() -> int:
	return cards.size()

func arrange() -> void:
	_arrange()

func request_dispose(card, mouse_global_pos: Vector2) -> bool:
	var zone = get_tree().get_first_node_in_group("disposal_zone")
	if zone:
		var rect = zone.get_global_rect()
		if rect.has_point(mouse_global_pos):
			if zone.has_method("dispose_card"):
				detach_card(card)
				zone.dispose_card(card)
				return true
	return false

func request_place(card, drop_global_pos: Vector2) -> bool:
	# Card placement logic (same as before, excluding resource cards)
	var card_data = card.get("card_data")
	if card_data == null:
		return false
	
	var scene = get_tree().current_scene
	if not scene: return false
	
	var grid = scene.get_node_or_null("Grid")
	if grid == null:
		grid = get_tree().get_first_node_in_group("grid")
	
	if grid == null or not grid.has_method("world_to_grid"):
		return false
	
	var viewport = get_viewport()
	var mouse_world_pos: Vector2
	if viewport != null:
		var camera = viewport.get_camera_2d()
		if camera != null:
			mouse_world_pos = camera.get_global_mouse_position()
		else:
			mouse_world_pos = drop_global_pos
	else:
		mouse_world_pos = drop_global_pos
	
	var cell = grid.world_to_grid(mouse_world_pos)
	
	# Unit/Building Card logic
	var is_building := (card_data is BuildingCard)
	var is_unit := (card_data is UnitCard)

	if is_building:
		# ... (keep building placement logic)
		var cost_dict := _get_cost_dict_from_card(card_data)
		var ledger := _get_player_resource_ledger()
		if not _can_afford_cost(ledger, cost_dict, "building"): return false
		
		var footprint_data = card_data.get("footprint_data")
		if footprint_data == null: return false
		
		if not grid.has_method("is_footprint_occupied"): return false
		if grid.is_footprint_occupied(cell, footprint_data): return false
		
		var cells_to_check = grid.get_cells_in_footprint(cell, footprint_data)
		for check_cell in cells_to_check:
			if not grid.is_in_bounds(check_cell): return false
		
		var instance = card_data.building_scene.instantiate()
		if instance == null: return false
		
		var grid_entity = instance as GridEntity
		if grid_entity != null:
			grid_entity.footprint_data = footprint_data
			grid_entity.grid_position = cell
		
		var buildings_layer = scene.get_node_or_null("Entities/BuildingsLayer")
		if buildings_layer == null: buildings_layer = scene.get_node_or_null("BuildingsLayer")
		if buildings_layer != null: buildings_layer.add_child(instance)
		else: scene.add_child(instance)
		
		instance.global_position = grid.grid_to_world_center_footprint(cell, footprint_data)
		
		var card_provider = instance.get_node_or_null("CardProvider") as CardProvider
		if card_provider != null:
			card_provider.set_card_and_apply(card_data)
		
		_spend_cost(ledger, cost_dict)
		return true
	elif is_unit:
		# ... (keep unit placement logic)
		var cost_dict := _get_cost_dict_from_card(card_data)
		var ledger := _get_player_resource_ledger()
		if not _can_afford_cost(ledger, cost_dict, "unit"): return false
		
		var footprint_data = card_data.get("footprint_data")
		if footprint_data == null: return false
		
		if not grid.has_method("is_footprint_occupied"): return false
		if grid.is_footprint_occupied(cell, footprint_data): return false
		
		var cells_to_check = grid.get_cells_in_footprint(cell, footprint_data)
		for check_cell in cells_to_check:
			if not grid.is_in_bounds(check_cell): return false
		
		var instance = card_data.unit_scene.instantiate()
		if instance == null: return false
		
		var grid_entity = instance as GridEntity
		if grid_entity != null:
			grid_entity.footprint_data = footprint_data
			grid_entity.grid_position = cell
		
		var units_layer = scene.get_node_or_null("Entities/UnitsLayer")
		if units_layer == null: units_layer = scene.get_node_or_null("UnitsLayer")
		if units_layer != null: units_layer.add_child(instance)
		else: scene.add_child(instance)
		
		instance.global_position = grid.grid_to_world_center_footprint(cell, footprint_data)
		
		var card_provider = instance.get_node_or_null("CardProvider") as CardProvider
		if card_provider != null:
			card_provider.set_card_and_apply(card_data)
		
		_spend_cost(ledger, cost_dict)
		return true
	
	return false

func get_card_home_global_position(card) -> Vector2:
	var idx := cards.find(card)
	if idx == -1: return card.global_position
	var count := cards.size()
	if count == 0: return card.global_position
		
	var hand_bottom_y := get_global_rect().end.y
	var hand_center_x := get_global_rect().get_center().x
	
	var center_index := (count - 1) * 0.5
	var local_x := (idx - center_index) * spacing
	var x := hand_center_x + local_x - 40.0
	var t: float = float(idx) / float(max(count - 1, 1))
	var y_offset := 0.0
	if y_offset_curve:
		y_offset = -y_offset_curve.sample(t) * 50.0
	var y := hand_bottom_y - hand_bottom_offset - 120.0 + y_offset + _lock_y_shift
	return Vector2(x, y)

func _arrange(animate: bool = true) -> void:
	if cards.is_empty():
		return
	
#	print("[Hand] _arrange called for %d cards. Animate: %s" % [cards.size(), animate])
#	print("[Hand Debug] Hand Visible: %s | InTree: %s | Rect: %s | Parent: %s" % [
#		visible,
#		is_visible_in_tree(),
#		get_global_rect(),
#		get_parent().name if get_parent() else "None"
#	])
	var hand_bottom_y := get_global_rect().end.y
	var hand_center_x := get_global_rect().get_center().x
#	print("[Hand] Hand center X: %.2f, Bottom Y: %.2f" % [hand_center_x, hand_bottom_y])

	var is_dragging_selected = dragging_card != null and dragging_card.is_selected

	var base_list: Array = []
	for c in cards:
		if is_dragging_selected:
			if c.is_selected: continue
		elif c == dragging_card:
			continue
		base_list.append(c)
		
	var order: Array = base_list.duplicate()
	if dragging_card and preview_insert_idx >= 0 and preview_insert_idx <= base_list.size():
		order.insert(preview_insert_idx, null)

	var count := order.size()
	var center_index := (count - 1) * 0.5
	for i in range(count):
		var entry = order[i]
		var local_x := (i - center_index) * spacing
		var x := hand_center_x + local_x - 40.0
		var t: float = float(i) / float(max(count - 1, 1))
		var angle_deg := -card_spread_angle * 0.5 + card_spread_angle * t
		if rotation_curve:
			angle_deg = rotation_curve.sample(t) * (card_spread_angle * 0.5)
		var y_offset := 0.0
		if y_offset_curve:
			y_offset = -y_offset_curve.sample(t) * 50.0
		
		var selection_offset := 0.0
		if entry is Card and entry.is_selected:
			selection_offset = entry.selected_y_offset
			
		var y := hand_bottom_y - hand_bottom_offset - 120.0 + y_offset + _lock_y_shift + selection_offset
		if entry == null:
			continue
		var target := Vector2(x, y)
		if animate and swap_animation_duration > 0.0:
			var tw: Tween = entry.create_tween().set_parallel(true)
			tw.tween_property(entry, "global_position", target, swap_animation_duration).set_trans(swap_trans).set_ease(swap_ease)
			tw.tween_property(entry, "scale", Vector2.ONE, swap_animation_duration).set_trans(swap_trans).set_ease(swap_ease)
		else:
			entry.global_position = target
			entry.scale = Vector2.ONE
		entry.z_index = 100
		entry.visible = true
		entry.modulate = Color(1,1,1,1)
		entry.rotation = deg_to_rad(angle_deg)

func cancel_reorder_preview() -> void:
	preview_insert_idx = -1
	_arrange()

func cancel_drag() -> void:
	dragging_card = null
	drag_from_idx = -1
	preview_insert_idx = -1

func show_hand_border() -> void:
	if _hand_border and _hand_border.has_method("show_border"):
		_hand_border.show_border()

func hide_hand_border() -> void:
	if _hand_border and _hand_border.has_method("hide_border"):
		_hand_border.hide_border()



func is_point_in_hand_area(global_pos: Vector2) -> bool:
	var viewport_rect := get_viewport().get_visible_rect()
	var hand_bottom_y := get_global_rect().end.y
	var hand_y_top := hand_bottom_y - hand_bottom_offset - 120.0
	var hand_y_bottom := hand_bottom_y
	var hand_x_left := viewport_rect.position.x
	var hand_x_right := viewport_rect.position.x + viewport_rect.size.x
	return global_pos.x >= hand_x_left and global_pos.x <= hand_x_right and global_pos.y >= hand_y_top and global_pos.y <= hand_y_bottom

func _get_player_resource_ledger() -> Node:
	return get_node_or_null("/root/PlayerResourceLedger")

func _get_cost_dict_from_card(card_data) -> Dictionary:
	var result: Dictionary = {}
	if card_data == null: return result
	var raw = {}
	if card_data.has_method("get_cost_dict"): raw = card_data.get_cost_dict()
	elif card_data.has("cost"): raw = card_data.get("cost")
	if raw is Dictionary:
		for key in raw.keys():
			var amount := int(raw[key])
			if amount > 0: result[StringName(key)] = amount
	elif raw is int:
		if raw > 0: result[DEFAULT_COST_RESOURCE] = raw
	return result

func _can_afford_cost(ledger: Node, cost_dict: Dictionary, _context: String) -> bool:
	if cost_dict.is_empty(): return true
	if ledger == null: return false
	return ledger.call("can_afford", cost_dict)

func _spend_cost(ledger: Node, cost_dict: Dictionary) -> void:
	if ledger == null or cost_dict.is_empty(): return
	ledger.call("spend_resource", cost_dict.duplicate(true))

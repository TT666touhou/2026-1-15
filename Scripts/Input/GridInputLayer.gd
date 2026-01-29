extends Control
class_name GridInputLayer

# 覆蓋在 Grid 上方，用於接收 UI 拖曳

var grid: Node

func _ready() -> void:
	# ... (尋找 Grid 等邏輯)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F2:
			_debug_kill_all_enemies()

func _debug_kill_all_enemies() -> void:
	print("[Debug] Killing all enemies (triggering death logic)...")
	var enemies = get_tree().get_nodes_in_group("enemy")
	print("[Debug] Found ", enemies.size(), " enemies in group 'enemy'")
	
	for enemy in enemies:
		if is_instance_valid(enemy):
			print("[Debug] Killing: ", enemy.name)
			if enemy is GridEntity and enemy.character_data:
				# 確保觸發完整的死亡流程
				enemy.character_data.take_damage(999999)
			else:
				# 如果是建築或其他沒有數據的單位，直接移除
				if "is_dying" in enemy:
					enemy.is_dying = true
				enemy.queue_free()
	
	print("[Debug] All enemies death logic triggered. Requesting clear check...")
	
	# 等待一小段時間讓單位進入死亡狀態並標記 is_dying
	await get_tree().create_timer(0.2).timeout
	
	# 主動觸發 DungeonManager 的檢查
	if DungeonManager:
		print("[Debug] Calling DungeonManager.check_room_clear()")
		DungeonManager.check_room_clear()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# 只處理單位部署，技能系統已移除
	if data is CharacterData:
		return _can_drop_unit(data)
	elif data is RuntimeCardData:
		# 只處理單位卡片，不處理技能卡片
		if data.get_base_data() is UnitCard:
			# TODO: 適配 UnitCard 部署流程
			return false
	
	return false

func _can_drop_unit(data: CharacterData) -> bool:
	if not PartyManager:
		return false
		
	if grid == null:
		grid = get_tree().get_first_node_in_group("grid")
	if grid == null or not grid.has_method("world_to_grid"):
		return false
		
	var cell = _get_grid_cell_from_mouse()
	
	# 詢問 PartyManager 是否可放置
	return PartyManager.can_place_member(data, cell)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is CharacterData:
		_drop_unit(data)

func _drop_unit(data: CharacterData) -> void:
	if grid == null: return
	var cell = _get_grid_cell_from_mouse()
	
	var success = PartyManager.spawn_party_member(data, cell)
	if success:
		# Optional: Play sound or effect
		pass


func _get_grid_cell_from_mouse() -> Vector2i:
	if grid == null:
		grid = get_tree().get_first_node_in_group("grid")
		
	var camera = get_viewport().get_camera_2d()
	var mouse_world_pos = get_global_mouse_position()
	if camera:
		mouse_world_pos = camera.get_global_mouse_position()
		
	if grid and grid.has_method("world_to_grid"):
		return grid.world_to_grid(mouse_world_pos)
		
	return Vector2i.ZERO

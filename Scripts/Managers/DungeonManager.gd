extends Node

# DungeonManager (Autoload)
# 負責管理地牢流程、房間載入與隊伍生成

var current_room_template: RoomTemplate
var active_gates: Array[Node] = []

# 動態格子生成相關
# 必須與 MapLoader 的 extra_cell_coords 保持一致，或者從 MapLoader 獲取
# 為了簡單，這裡我們複製一份配置，實際運作時應以 MapLoader 為準
var extra_cells: Array[Vector2i] = [
	Vector2i(11, 1), # 上
	Vector2i(11, 3), # 中
	Vector2i(11, 5)  # 下
]
var _spawned_gates_by_index: Dictionary = {}
# var gate_scene = preload("res://Scenes/Map/GateEntity.tscn") # [暫時停用]

# 溶解特效資源
const DISSOLVE_SHADER = preload("res://Shaders/Dissolve.gdshader")
var _dissolve_noise_tex: NoiseTexture2D

func _ready() -> void:
	print("[DungeonManager] Initialized")
	_init_dissolve_assets()
	
	# 連接 BoardManager 信號以監測敵人
	if BoardManager:
		BoardManager.entity_unregistered.connect(_on_entity_unregistered)
	else:
		push_warning("[DungeonManager] BoardManager not found during init")
	
	if TurnManager:
		TurnManager.turn_started.connect(_on_turn_started)

func _capture_initial_extra_cells() -> void:
	# 委託給 MapLoader 處理
	pass 
	
func _on_entity_unregistered(entity: Node) -> void:
	# BOSS 勝利判定
	if entity is GridEntity and entity.is_boss:
		print("[DungeonManager] Boss defeated! Clearing all enemies.")
		_kill_all_enemies()

	# 延遲一幀檢查，確保 entity 已經完全移除
	call_deferred("_check_room_clear_condition_deferred")

func _kill_all_enemies() -> void:
	if not BoardManager: return
	
	var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
	if not enemy_faction: return
	
	var remaining_enemies = BoardManager.get_entities_by_faction(enemy_faction)
	for enemy in remaining_enemies:
		if is_instance_valid(enemy):
			if enemy.character_data:
				# 繞過所有防禦機制，直接歸零並觸發死亡
				enemy.character_data.barriers = 0
				enemy.character_data.shield = 0
				enemy.character_data.current_health = 0
				# 發送信號更新 UI 與執行動畫
				enemy.character_data.health_changed.emit(0, enemy.character_data.get_effective_max_health())
				enemy.character_data.stats_changed.emit()
				enemy.character_data.died.emit()
			elif enemy.has_method("take_damage"):
				# 對於沒有 character_data 的對象（如建築），使用原本的超大傷害
				enemy.take_damage(99999, true, true)

func _check_room_clear_condition_deferred() -> void:
	if not BoardManager: return
	
	# 我們不再知道哪個 entity 被移除了，但我們只關心 "Enemy" 陣營是否全滅
	# 假設敵人的 faction 資源路徑固定，或通過遍歷 FactionDefinition 來查找
	# 簡單起見，嘗試加載 Enemy Faction 資源
	var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
	if not enemy_faction:
		return
		
	var remaining_enemies = BoardManager.get_entities_by_faction(enemy_faction)
	
	if remaining_enemies.is_empty():
		# 避免重複觸發：如果門已經生成了，就不再生成
		if _spawned_gates_by_index.is_empty():
			print("[DungeonManager] All enemies defeated! Free roam mode enabled.")
			# spawn_room_exit_gates(2) # [暫時停用實體門生成]
			
			if TurnManager:
				TurnManager.set_free_roam_mode(true)

# 保留舊函數簽名以防萬一，但不再使用
func _check_room_clear_condition(_removed_entity: Node) -> void:
	pass

func spawn_room_exit_gates(_count: int) -> void:
	# [暫時停用]
	pass
	# 根據需求："當只有一個選項的時候就生成在中間，兩個就生成在兩側的圈上"
	# ...

func set_gate_active(_index: int, _active: bool) -> void:
	# [暫時停用實體門與格子啟動邏輯]
	return
	# if index < 0 or index >= extra_cells.size(): return
	# ...

# 兼容舊函數名 (若有其他地方呼叫)
func _activate_gate_grid(index: int, active: bool) -> void:
	set_gate_active(index, active)

func register_gate(_gate: Node) -> void:
	pass

func unregister_gate(_gate: Node) -> void:
	pass

func check_gate_trigger(entity: Node, cell: Vector2i) -> void:
	# [新邏輯]：不再檢查實體門，而是檢查單位是否到達右側邊界 (X >= 7)
	# 只有在非戰鬥模式 (Free Roam) 且是玩家單位時觸發
	if TurnManager and not TurnManager.is_free_roam_mode:
		return
		
	if entity.get("faction") != null and entity.faction.resource_path.contains("Player"):
		if cell.x >= 11:
			print("[DungeonManager] Player reached boundary at ", cell, ". Triggering transition...")
			# 建立一個臨時對象來攜帶 next_room_name
			var transition_info = { "next_room_name": "T001" } # 預設前往 T001
			
			# 如果當前房間有定義出口路徑，可以在這裡獲取
			# 目前簡單先固定為循環測試
			call_deferred("play_gate_transition", transition_info)

func load_room_by_name(room_name: String, skip_spawn_anim: bool = false, skip_ground_init: bool = false) -> Dictionary:
	var path = "res://Resources/Rooms/" + room_name + ".tres"
	print("[DungeonManager] Attempting to load room: ", path)
	if !FileAccess.file_exists(path):
		push_error("[DungeonManager] Room not found: " + path)
		return {"players": [], "enemies": []}
		
	var template = load(path)
	if template is RoomTemplate:
		return _load_room_template(template, skip_spawn_anim, skip_ground_init)
	else:
		push_error("[DungeonManager] Invalid resource type at: " + path)
		return {"players": [], "enemies": []}

func _load_room_template(template: RoomTemplate, skip_spawn_anim: bool = false, skip_ground_init: bool = false) -> Dictionary:
	print("[DungeonManager] Starting _load_room_template for: ", template.room_name)
	current_room_template = template
	
	var map_loader = get_tree().get_first_node_in_group("map_loader")
	if !map_loader:
		push_error("[DungeonManager] MapLoader not found in scene tree")
		return {"players": [], "enemies": []}
		
	# 1. 觸發當前場景中單位的狀態保存 (新增)
	var existing_units = get_tree().get_nodes_in_group("grid_entities")
	print("[DungeonManager] Saving data for ", existing_units.size(), " existing units")
	for unit in existing_units:
		if unit.has_method("save_runtime_data") and unit.faction and unit.faction.is_controllable:
			unit.save_runtime_data()
		
	# 2. 清空地圖
	if map_loader.has_method("clear_current_map"):
		map_loader.clear_current_map(skip_ground_init)
		
	# Reset Camera after clearing/before spawning
	# _reset_camera()
		
	# 清除所有動態生成的門和格子
	for i in range(extra_cells.size()):
		set_gate_active(i, false)
	
	# 2. 生成房間內容 (敵人/障礙物)
	var spawned_enemies: Array[GridEntity] = []
	if map_loader.has_method("instantiate_room"):
		var result = map_loader.instantiate_room(template)
		if result is Array: 
			for item in result:
				if item is GridEntity:
					spawned_enemies.append(item as GridEntity)
	
	print("[DungeonManager] Instantiated ", spawned_enemies.size(), " enemies")
		
	# 3. 生成玩家隊伍
	var spawned_players = spawn_player_party(map_loader)
	print("[DungeonManager] Spawned ", spawned_players.size(), " players")
	
	# 4. 播放進場動畫序列 (如果沒有跳過)
	if not skip_spawn_anim:
		_play_spawn_sequence(spawned_players, spawned_enemies)
	
	# 5. 重置回合 (假設 TurnManager 存在)
	if TurnManager:
		# 嘗試獲取預設陣營資源
		var player_faction = load("res://Resources/Factions/Faction_Player.tres")
		var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
		
		if player_faction and enemy_faction:
			TurnManager.start_combat([player_faction, enemy_faction])
			if TurnManager.has_method("end_deployment"):
				TurnManager.end_deployment()
		else:
			push_warning("[DungeonManager] Could not load default factions for TurnManager")
			
	return {"players": spawned_players, "enemies": spawned_enemies}

func spawn_player_party(map_loader: Node) -> Array[GridEntity]:
	var spawned_units: Array[GridEntity] = []
	if !current_room_template: return spawned_units
	if !PartyManager: return spawned_units
	
	var spawn_points = current_room_template.player_spawn_points
	var party = PartyManager.get_members() # Expects Array[CharacterData]
	
	if party.is_empty():
		print("[DungeonManager] Party is empty, skipping spawn")
		return spawned_units
		
	print("[DungeonManager] Spawning party of size: ", party.size())
	
	for i in range(party.size()):
		if i >= spawn_points.size():
			push_warning("[DungeonManager] Not enough spawn points for party member " + str(i))
			break
			
		var char_data = party[i]
		var spawn_pos = spawn_points[i]
		
		var card = null
		if char_data.get("unit_def"):
			card = char_data.unit_def
		
		if card and card.unit_scene:
			var instance = card.unit_scene.instantiate()
			
			# 設定 Grid Position
			if instance.has_method("set_grid_position"):
				# 1. 配置 CardProvider (獲取靜態配置：移動、陣營等)
				var card_provider = instance.get_node_or_null("CardProvider")
				if card_provider:
					# 使用完整套用流程，確保 faction / footprint / movement_range_data 以及 CharacterData 初始化正確
					card_provider.set_card_and_apply(card)

				# 3. 先加入場景 (確保 _ready 執行)
				if map_loader.has_method("add_unit_to_scene"):
					map_loader.add_unit_to_scene(instance)

				# 4. 注入 CharacterData (狀態保持)
				# 必須在加入場景之後執行，因為 CardProvider 會在 _ready 中創建新的 CharacterData
				if instance.has_method("setup_character"):
					instance.setup_character(char_data)

				# 5. 再設定 Grid Position (觸發視覺同步與網格註冊)
				instance.set_grid_position(spawn_pos)
				
				# 6. 準備進場 (隱藏) - 不再直接播放動畫
				if instance.has_method("prepare_for_entry"):
					instance.prepare_for_entry()

				spawned_units.append(instance as GridEntity)
			else:
				instance.queue_free()
		else:
			push_error("[DungeonManager] Could not instantiate unit for party member " + str(i))
			
	# 單次、集中的佔用註冊與驗證流程
	_force_player_units_occupancy(spawned_units)

	return spawned_units


func _force_player_units_occupancy(units: Array[GridEntity]) -> void:
	var grid = get_tree().get_first_node_in_group("grid")
	if grid == null:
		return
	
	for u in units:
		if u == null or u.footprint_data == null:
			continue
		
		if grid.has_method("get_cells_in_footprint") and grid.has_method("set_cell_occupied"):
			var cells = grid.get_cells_in_footprint(u.grid_position, u.footprint_data)
			for c in cells:
				grid.set_cell_occupied(c, u)
			# print("[SpawnForce] Occupancy set for ", u.name, " at ", u.grid_position, " cells:", cells.size()) # Debug removed

func _play_spawn_sequence(players: Array[GridEntity], enemies: Array[GridEntity]) -> void:
	"""
	依序播放進場動畫：
	1. 裝備/物件 (由上而下, 由左而右)
	2. 玩家單位 (由上而下, 由左而右)
	3. 敵方單位 (由上而下, 由左而右)
	"""
	
	# 定義排序函數
	var sort_func = func(a: GridEntity, b: GridEntity) -> bool:
		if a.grid_position.y != b.grid_position.y:
			return a.grid_position.y < b.grid_position.y
		return a.grid_position.x < b.grid_position.x
	
	# 拆分敵人清單中的「真實敵人」與「環境物/裝備」
	var real_enemies: Array[GridEntity] = []
	var environment_items: Array[GridEntity] = []
	
	for e in enemies:
		if e is EquipmentEntity or e is PropEntity or e is TrapEntity:
			environment_items.append(e)
		else:
			real_enemies.append(e)
			
	players.sort_custom(sort_func)
	real_enemies.sort_custom(sort_func)
	environment_items.sort_custom(sort_func)
	
	var full_sequence: Array[GridEntity] = []
	full_sequence.append_array(environment_items)
	full_sequence.append_array(players)
	full_sequence.append_array(real_enemies)
	
	# 依序執行動畫
	# 1. 環境物件：全部同時進場
	var env_promises = []
	for unit in environment_items:
		if is_instance_valid(unit):
			unit.visible = true
			if unit.has_method("play_entry_animation"):
				unit.play_entry_animation(0.0)
				if unit.has_signal("entry_animation_finished"):
					env_promises.append(unit.entry_animation_finished)
			else:
				if unit.has_node("Sprite2D"):
					unit.get_node("Sprite2D").modulate.a = 1.0
	
	# 等待所有環境物件進場 (如果有信號的話)
	for promise in env_promises:
		await promise
	
	# 如果環境物件很多，給予一個極短的緩衝時間
	if not environment_items.is_empty():
		await get_tree().create_timer(0.2).timeout

	# 2. 玩家與敵人：維持逐一進場 (以維持打擊感)
	var combatants: Array[GridEntity] = []
	combatants.append_array(players)
	combatants.append_array(real_enemies)
	
	for unit in combatants:
		if is_instance_valid(unit):
			unit.visible = true
			if unit.has_method("play_entry_animation"):
				unit.play_entry_animation(0.0)
				if unit.has_signal("entry_animation_finished"):
					await unit.entry_animation_finished
				else:
					await get_tree().create_timer(0.3).timeout
			else:
				if unit.has_node("Sprite2D"):
					unit.get_node("Sprite2D").modulate.a = 1.0

func on_gate_entered(gate: Node) -> void:
	print("[DungeonManager] Player entered gate: ", gate.name)
	if gate.get("next_room_name"):
		var next_room = gate.next_room_name
		if next_room != "":
			# Call deferred to avoid issues with changing scenes during physics callback
			# Play transition animation instead of direct load
			call_deferred("play_gate_transition", gate)
		else:
			print("[DungeonManager] Gate has no next room configured.")

func _on_turn_started(faction: FactionDefinition) -> void:
	# 當玩家回合開始時
	if faction and faction.is_controllable:
		# 1. 回復 Soul (每回合 +3)
		if PlayerResourceLedger:
			PlayerResourceLedger.add_resource("soul", 3)
			print("[DungeonManager] Recovered 3 Soul for Player Turn")

# --- Scene Visibility Control ---

func set_battle_view_active(active: bool) -> void:
	var world = get_tree().current_scene
	if not world: return

	var nodes_to_toggle = [
		"Grid",
		"Ground",
		"Entities",
		"MovementRangeIndicator",
		"SkillPreviewLayers",
		"SelectionHighlight"
	]
	
	for node_name in nodes_to_toggle:
		var node = world.get_node_or_null(node_name)
		if node:
			if "visible" in node:
				node.visible = active
			else:
				# If the node itself is not a CanvasItem (e.g., pure Node), try to toggle its children
				# This is common for managers like Grid that might have visual children
				for child in node.get_children():
					if "visible" in child:
						child.visible = active
			
	# Special handling for GridLines
	var grid_lines_nodes = get_tree().get_nodes_in_group("grid_lines")
	for node in grid_lines_nodes:
		if "visible" in node:
			node.visible = active

	# Special handling for GridInputLayer to prevent interaction
	var grid_input = world.find_child("GridInputLayer", true, false)
	if grid_input:
		if "visible" in grid_input:
			grid_input.visible = active
		else:
			# If it's not visual, maybe disable processing
			grid_input.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

# --- Gate Transition Animation ---

func play_gate_transition(gate: Variant) -> void:
	print("\n[DungeonManager] >>> STEP-BASED TRANSITION START <<<")
	
	var world = get_tree().current_scene
	if not world: return
		
	var map_loader = get_tree().get_first_node_in_group("map_loader")
	var selector = get_tree().get_first_node_in_group("grid_selector")
	
	if !map_loader:
		print("[DungeonManager] MapLoader not found, falling back to basic load")
		if gate.get("next_room_name"):
			load_room_by_name(gate.next_room_name)
		return

	# 1. 關閉輸入
	if selector: selector.set_process_unhandled_input(false)
	
	# 設定參數
	var stream_distance = 320.0 # 捲動/跑步的總距離 (20格)
	var duration = 1.5
	
	# --- 階段一：出鏡 (Exit) ---
	var current_player_units = get_tree().get_nodes_in_group("grid_entities").filter(func(u): 
		return u.faction != null and u.faction.is_controllable
	)
	
	# 1. 處理地面裝備溶解 (先等待溶解完成再開始移動)
	var equipment = get_tree().get_nodes_in_group("equipment_entities")
	print("[DungeonManager] Transition: Found ", equipment.size(), " equipment entities to dissolve.")
	
	if not equipment.is_empty():
		var dissolve_time = 0.6
		for e in equipment:
			if is_instance_valid(e) and e is Node2D:
				_apply_dissolve_to_entity(e, dissolve_time)
			else:
				print("[DungeonManager] Warning: Equipment entity is invalid or not a Node2D.")
		# 等待溶解動畫完成
		await get_tree().create_timer(dissolve_time + 0.1).timeout
			
	# 2. 開始單位跑動轉場
	print("[DungeonManager] EXIT PHASE: Moving ", current_player_units.size(), " controllable units")
	for u in current_player_units:
		print("  - Unit: ", u.name, " current pos: ", u.global_position)
		
	await _play_step_transition(current_player_units, duration, stream_distance, false)

	# --- 階段二：載入新房間 (Switch) ---
	var next_room = gate.get("next_room_name")
	print("[DungeonManager] SWITCH PHASE: Target room: ", next_room)
	
	var result = {"players": [], "enemies": []}
	if next_room and next_room != "":
		result = load_room_by_name(next_room, true, true) 
	
	var new_players = result.get("players", [])
	var new_enemies = result.get("enemies", [])
	
	print("[DungeonManager] SWITCH PHASE: Room loaded. Players spawned: ", new_players.size(), " Enemies spawned: ", new_enemies.size())
	
	# --- 關鍵修復：在 await 之前立即執行平移與隱藏/顯示設定，消除閃爍 ---
	for unit in new_players:
		if is_instance_valid(unit):
			var target_world_pos = unit.global_position
			unit.global_position.x = target_world_pos.x - stream_distance
			unit.visible = true
			if unit.has_node("Sprite2D"):
				unit.get_node("Sprite2D").modulate.a = 1.0
			print("[DungeonManager] Repositioned ", unit.name, " for entry to start at X: ", unit.global_position.x, " (Target X: ", target_world_pos.x, ")")
	
	for unit in new_enemies:
		if is_instance_valid(unit):
			unit.visible = false
			if unit.has_node("Sprite2D"):
				unit.get_node("Sprite2D").modulate.a = 0.0

	# 給引擎時間初始化
	await get_tree().process_frame
	await get_tree().process_frame
	
	# --- 階段三：入鏡 (Entry) ---
	if new_players.is_empty():
		print("[DungeonManager] Entry search: player list from load was empty, checking group 'grid_entities'...")
		new_players = get_tree().get_nodes_in_group("grid_entities").filter(func(u): 
			return u.faction != null and u.faction.is_controllable
		)
		# 如果是從群組抓取的，也需要同步平移一次 (備援)
		for unit in new_players:
			if unit.visible and unit.global_position.x > -100: # 簡單判斷是否還沒被平移
				unit.global_position.x -= stream_distance
	
	print("[DungeonManager] ENTRY PHASE: Starting entry for ", new_players.size(), " player units")
	
	if new_players.is_empty():
		push_error("[DungeonManager] CRITICAL: No player units found for entry phase!")
		if selector: selector.set_process_unhandled_input(true)
		return
	
	# 2. 從左側跑入，同步生成地塊
	await _play_step_transition(new_players, duration, stream_distance, true)
	
	# --- 階段四：敵人進場 (Enemy Spawn) ---
	if new_enemies.is_empty():
		print("[DungeonManager] new_enemies list empty, searching group...")
		new_enemies = get_tree().get_nodes_in_group("grid_entities").filter(func(u): 
			return u.faction != null and not u.faction.is_controllable
		)
		
	print("[DungeonManager] SPAWN PHASE: ", new_enemies.size(), " enemies appearing...")
	
	if !new_enemies.is_empty():
		# 確保敵人在播放動畫前是可見的
		for u in new_enemies:
			if is_instance_valid(u):
				u.visible = true
				
		await _play_spawn_sequence([], new_enemies)
	
	print("[DungeonManager] >>> STEP-BASED TRANSITION END <<<\n")
	if selector: selector.set_process_unhandled_input(true)

## 格進式轉場引擎：每 16 像素更新一排地塊，確保與單位同步
func _play_step_transition(units: Array, duration: float, delta_x: float, is_entry: bool) -> void:
	if units.is_empty(): 
		print("[DungeonManager] Step transition skipped: no units provided.")
		return
		
	var map_loader = get_tree().get_first_node_in_group("map_loader")
	if !map_loader: 
		print("[DungeonManager] Step transition error: MapLoader not found.")
		return
	
	var grid_steps = int(abs(delta_x) / 16.0) # 20 步
	var step_time = duration / grid_steps
	
	print("[DungeonManager] --- Step Loop Start (%s) ---" % ("Entry" if is_entry else "Exit"))
	print("[DungeonManager] Steps: ", grid_steps, " Interval: ", step_time)
	
	# 1. 啟動單位線性位移
	var tween = create_tween().set_parallel(true)
	var valid_unit_count = 0
	for u in units:
		if is_instance_valid(u):
			var target_x = u.global_position.x + delta_x
			tween.tween_property(u, "global_position:x", target_x, duration).set_trans(Tween.TRANS_LINEAR)
			_play_run_hop(u, duration, 6)
			valid_unit_count += 1
	
	if valid_unit_count == 0:
		print("[DungeonManager] No valid units to animate, skipping loop.")
		return

	# 2. 每隔 X 秒更新一排地塊 (啟用動畫效果)
	for i in range(grid_steps):
		if !is_entry:
			# 出鏡：在地圖 right 之外生成，在 left 刪除
			map_loader.generate_column(11 + i, true) 
			map_loader.erase_column(i, true)
		else:
			# 入鏡：單位從 -20 格開始跑向 0 格
			var current_gx = -grid_steps + i
			map_loader.generate_column(current_gx + 11, true) # 在視窗右緣生成
			map_loader.erase_column(current_gx, true)        # 在視窗左緣擦除
		
		# 每 5 步印一次進度
		if i % 5 == 0:
			print("[DungeonManager] Transition progress: ", i, "/", grid_steps)
			
		await get_tree().create_timer(step_time).timeout

	# 3. 等待 Tween 完成 (確保位移到位)
	if tween.is_running():
		await tween.finished
		
	print("[DungeonManager] --- Step Loop Finished (%s) ---" % ("Entry" if is_entry else "Exit"))

# 輔助函數：跑動時的跳躍感
func _play_run_hop(unit: Node, total_duration: float, hop_count: int) -> void:
	var sprite = unit.get_node_or_null("Sprite2D")
	if !sprite: return
	
	var hop_duration = total_duration / hop_count
	# 使用一個單獨的 Tween 鏈來處理 Y 軸跳動，避免與 X 軸 Tween 衝突
	var y_tween = create_tween()
	for i in range(hop_count):
		y_tween.tween_property(sprite, "position:y", -6, hop_duration/2).set_trans(Tween.TRANS_SINE)
		y_tween.tween_property(sprite, "position:y", 0, hop_duration/2).set_trans(Tween.TRANS_SINE)

func _reset_camera(camera: Camera2D = null) -> void:
	if not camera:
		var world = get_tree().current_scene
		if world:
			camera = world.find_child("Camera2D", true, false)
			
			# 同步重置背景位置
			var bg_ground = world.get_node_or_null("BackgroundGround")
			if bg_ground:
				bg_ground.position.x = 0
				print("[DungeonManager] Background position reset to 0")
	
	if camera:
		# Reset to default values from World.tscn
		camera.zoom = Vector2(4, 4)
		camera.position = Vector2(16, 56)
		camera.rotation = 0.0 # Reset rotation
		# camera.ignore_rotation = true # Reset to default (Removed rotation anim)
		print("[DungeonManager] Camera reset to default")

func debug_test_gate_transition() -> void:
	var world = get_tree().current_scene
	if not world: return
	
	var grid = world.get_node_or_null("Grid")
	var target_pos = Vector2.ZERO
	if grid and grid.has_method("grid_to_world_center"):
		target_pos = grid.grid_to_world_center(Vector2i(3, 3)) # Center of map
	
	# Create a fake gate object
	var fake_gate = Node2D.new()
	fake_gate.name = "DebugFakeGate"
	fake_gate.global_position = target_pos
	# Add property dynamically
	fake_gate.set_meta("next_room_name", "T001") # Loop to T001
	
	# Add to scene momentarily so it's valid
	world.add_child(fake_gate)
	
	# Inject get method for next_room_name compatibility
	var script = GDScript.new()
	script.source_code = "extends Node2D\nvar next_room_name = 'T001'"
	script.reload()
	fake_gate.set_script(script)
	
	play_gate_transition(fake_gate)
	
	# Cleanup fake gate after animation start (it's passed by reference, pos is what matters)
	# Actually wait a bit or let it stay until scene reload

func _init_dissolve_assets() -> void:
	var noise = FastNoiseLite.new()
	noise.seed = -15
	noise.frequency = 1.0 # 提高頻率，產生更細密的點陣溶解感
	noise.fractal_octaves = 4
	_dissolve_noise_tex = NoiseTexture2D.new()
	_dissolve_noise_tex.noise = noise
	_dissolve_noise_tex.width = 256 # 增大尺寸以獲得更細膩的雜訊
	_dissolve_noise_tex.height = 256

func _apply_dissolve_to_entity(entity: Node2D, time: float) -> void:
	var sprite = entity.get_node_or_null("Sprite2D")
	if not sprite:
		print("[DungeonManager] Error: Sprite2D not found on entity ", entity.name)
		return
	
	print("[DungeonManager] Applying dissolve to: ", entity.name, " (Sprite visible: ", sprite.visible, ")")
	
	# 建立 Shader 材質
	var mat = ShaderMaterial.new()
	mat.shader = DISSOLVE_SHADER
	
	# 確保 NoiseTexture 已經生成
	if _dissolve_noise_tex == null:
		_init_dissolve_assets()
		
	mat.set_shader_parameter("dissolve_texture", _dissolve_noise_tex)
	mat.set_shader_parameter("dissolve_value", 1.0)
	mat.set_shader_parameter("burn_size", 0.1) # 增加燒邊寬度，使其在小圖示上更明顯
	mat.set_shader_parameter("burn_color", Color(2.0, 1.0, 0.2, 1.0)) # 增強發光強度
	
	sprite.material = mat
	
	# 動畫處理
	var tween = create_tween()
	if tween:
		# 這裡稍微延長動畫時間，確保玩家能看清楚
		tween.tween_property(mat, "shader_parameter/dissolve_value", 0.0, time)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		print("[DungeonManager] Dissolve tween started for ", entity.name)
	else:
		print("[DungeonManager] Error: Failed to create tween for dissolve.")

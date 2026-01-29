extends Node

# DungeonManager (Autoload)
# 負責管理地牢流程、房間載入與隊伍生成

var current_room_template: RoomTemplate
var _is_transitioning: bool = false # 防止重複觸發轉場

func _ready() -> void:
	print("[DungeonManager] Initialized")
	
	# 連接 BoardManager 信號以監測敵人
	if BoardManager:
		BoardManager.entity_unregistered.connect(_on_entity_unregistered)
	else:
		push_warning("[DungeonManager] BoardManager not found during init")

## 公開接口：註冊當前房間模板
func register_current_room(template: RoomTemplate) -> void:
	current_room_template = template
	print("[DungeonManager] Current room registered: ", template.room_name, " | Next: ", template.next_room_name)

func _on_entity_unregistered(entity: Node) -> void:
	# 只有在非轉場期間才檢查
	if _is_transitioning: return
	
	# BOSS 勝利判定
	if entity is GridEntity and entity.get("is_boss"):
		print("[DungeonManager] Boss defeated! Clearing all enemies.")
		_kill_all_enemies()

	# 核心修正：如果是寶箱房 (T004)，需要等待裝備被拾取
	if current_room_template and current_room_template.room_name.to_lower() == "t004":
		# 如果掉落的是裝備，則延遲檢查
		if entity is TreasureChestEnemy:
			print("[DungeonManager] Chest defeated in T004. Waiting for equipment pickup...")
			return
		
		# 如果被移除的是裝備實體，則檢查是否可以進關
		if entity.is_in_group("equipment_entities"):
			print("[DungeonManager] Equipment picked up. Checking room status...")
			# 核心修正：使用 call_deferred 並給予微小延遲，確保群組已更新
			get_tree().create_timer(0.1).timeout.connect(check_room_clear)
			return

	# 延遲一幀檢查，確保 entity 已經完全從 BoardManager 移除
	call_deferred("check_room_clear")

func _kill_all_enemies() -> void:
	if not BoardManager: return
	
	var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
	if not enemy_faction: return
	
	var remaining_enemies = BoardManager.get_entities_by_faction(enemy_faction)
	for enemy in remaining_enemies:
		if is_instance_valid(enemy):
			if enemy.character_data:
				enemy.character_data.take_damage(999999)
			elif enemy.has_method("take_damage"):
				enemy.take_damage(99999, true, true)

## 公開接口：檢查房間是否清空並處理進關
func check_room_clear() -> void:
	if _is_transitioning: return
	if not BoardManager: return
	
	# 針對 T004 的特殊檢查：如果場上還有裝備，則不進關
	if current_room_template and current_room_template.room_name.to_lower() == "t004":
		# 延遲一幀獲取群組，確保 queue_free 的實體已被移除
		await get_tree().process_frame
		var equipment = get_tree().get_nodes_in_group("equipment_entities")
		if not equipment.is_empty():
			print("[DungeonManager] T004: Equipment still on field (Count: %d), staying." % equipment.size())
			return
		else:
			print("[DungeonManager] T004: All equipment picked up!")

	var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
	if not enemy_faction: return
		
	# 1. 檢查敵人是否清空
	var remaining_in_group = get_tree().get_nodes_in_group("enemy")
	var active_enemies = remaining_in_group.filter(func(e): 
		var dying = e.get("is_dying") if e.has_method("get") or "is_dying" in e else false
		return is_instance_valid(e) and not dying
	)
	
	if not active_enemies.is_empty():
		return

	# 2. 檢查場上是否還有未拾取的裝備
	var remaining_equipment = get_tree().get_nodes_in_group("equipment_entities")
	if not remaining_equipment.is_empty():
		print("[DungeonManager] Enemies cleared, but waiting for equipment to be picked up.")
		return
	
	if not _is_transitioning:
		print("[DungeonManager] SUCCESS: All enemies defeated and equipment picked up! Advancing...")
		advance_to_next_room()

func advance_to_next_room() -> void:
	if _is_transitioning: return
	
	if current_room_template and current_room_template.next_room_name != "":
		var next_room = current_room_template.next_room_name
		print("[DungeonManager] All enemies defeated. Waiting for physics to settle before advancing to: ", next_room)
		_is_transitioning = true
		
		# 1. 等待物理完全靜止且無飛行物
		if TurnManager and TurnManager.has_method("_wait_for_physics"):
			await TurnManager._wait_for_physics()
		
		# 2. 額外延遲，增加儀式感
		await get_tree().create_timer(0.8).timeout
		
		# 3. 載入房間
		load_room_by_name(next_room)
		
		# 核心修正：延遲重置轉場標記，確保新房間的初始物理重疊（擠開過程）不會觸發傷害
		await get_tree().create_timer(1.0).timeout
		_is_transitioning = false
		print("[DungeonManager] Transition finished, damage enabled.")
	else:
		print("[DungeonManager] No next room defined. Game Clear!")
		_show_game_clear_ui()

func _show_game_clear_ui() -> void:
	var scn = load("res://Scenes/UI/GameClearUI.tscn")
	if not scn: return
	
	var ui = scn.instantiate()
	# 尋找適當的 UI 層級
	var ui_layer = get_tree().current_scene.get_node_or_null("UI")
	if ui_layer:
		ui_layer.add_child(ui)
	else:
		get_tree().root.add_child(ui)
	
	# 隱藏 DeploymentUI (紅圈部分)
	var deployment_ui = get_tree().get_first_node_in_group("deployment_ui")
	if deployment_ui:
		deployment_ui.visible = false
		print("[DungeonManager] Hidden DeploymentUI for GameClear")

func load_room_by_name(room_name: String) -> void:
	var paths_to_try = [
		"res://Resources/Rooms/" + room_name + ".tres",
		"res://Resources/Rooms/" + room_name.to_upper() + ".tres",
		"res://Resources/Rooms/" + room_name.capitalize() + ".tres"
	]
	
	var path = ""
	for p in paths_to_try:
		if FileAccess.file_exists(p):
			path = p
			break
			
	if path == "":
		push_warning("[DungeonManager] Room not found: " + room_name)
		return
		
	print("[DungeonManager] Loading room: ", path)
	var template = load(path)
	if template is RoomTemplate:
		_load_room_template(template)
	else:
		push_error("[DungeonManager] Invalid resource type at: " + path)

func _load_room_template(template: RoomTemplate) -> void:
	print("[DungeonManager] Starting _load_room_template for: ", template.room_name)
	current_room_template = template
	
	var map_loader = get_tree().get_first_node_in_group("map_loader")
	if !map_loader:
		push_error("[DungeonManager] MapLoader not found in scene tree")
		return
		
	# 1. 狀態保存
	var existing_units = get_tree().get_nodes_in_group("grid_entities")
	for unit in existing_units:
		if unit.has_method("save_runtime_data") and unit.faction and unit.faction.is_controllable:
			unit.save_runtime_data()
	
	# 2. 核心機制：先回血 (在載入新單位前)
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.character_data:
			var data = p.character_data
			var max_hp = data.get_effective_max_health()
			var current_hp = data.current_health
			var missing_hp = max_hp - current_hp
			
			if missing_hp > 0:
				var heal_amount = int(missing_hp * 0.5)
				if heal_amount > 0:
					data.heal(heal_amount)
					if p.has_method("_spawn_text"):
						p._spawn_text("+%d HP" % heal_amount, Color.GREEN)
					print("[DungeonManager] %s healed for %d (50%% of missing HP)" % [p.name, heal_amount])
	
	# 等待回血動畫顯示一下
	await get_tree().create_timer(0.5).timeout
		
	# 3. 生成房間內容 (敵人與地圖)
	var spawned_enemies = map_loader.instantiate_room(template)
	
	# 4. 確保保留的玩家單位在新的網格中重新註冊佔用
	players = get_tree().get_nodes_in_group("player") # 重新獲取以防變動
	for p in players:
		if p.has_method("set_grid_position"):
			# 核心修正：不再強制重新對齊網格中心，而是根據當前物理位置更新網格座標並註冊佔用
			var current_cell = Vector2i(-1, -1)
			var grid_node = get_tree().get_first_node_in_group("grid")
			if grid_node:
				current_cell = grid_node.world_to_grid(p.global_position)
				
			if current_cell != Vector2i(-1, -1):
				# 直接更新座標並註冊，不觸發物理位移
				p.grid_position = current_cell
				if p.has_method("_register_cells"):
					p._register_cells()
				print("[DungeonManager] Player %s staying at current pos, registered at cell %s" % [p.name, current_cell])
	
	# 5. 播放進場動畫
	for entity in spawned_enemies:
		if entity.has_method("play_entry_animation"):
			entity.play_entry_animation(0.2)
			
	# 6. 自動部署玩家隊伍 (僅在場上沒有玩家時執行)
	var existing_players = get_tree().get_nodes_in_group("player")
	if existing_players.is_empty() and map_loader.has_method("_auto_deploy_party"):
		map_loader._auto_deploy_party(template)
	else:
		print("[DungeonManager] Players already on field, skipping auto-deploy.")
	
	# 7. 重置回合
	if TurnManager:
		var player_faction = load("res://Resources/Factions/Faction_Player.tres")
		var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
		if player_faction and enemy_faction:
			TurnManager.start_combat([player_faction, enemy_faction])
			TurnManager.end_deployment()

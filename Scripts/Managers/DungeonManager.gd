extends Node

# [DungeonManager] 地牢流程管理器 (Autoload)
# 職責：
# 1. 管理地牢房間載入與初始化 (load_room_by_name)。
# 2. 監控戰鬥狀態 (check_battle_status)，判定勝利條件。
# 3. 執行房間轉場 (advance_to_next_room)，處理戰利品清除與動畫。

# [相關外部連動腳本]:
# - TurnManager.gd: 負責告知是否進入搜刮階段 (trigger_loot_phase)，並在轉場前等待物理結算 (_wait_for_physics)。
# - BoardManager.gd: 監聽實體移除信號 (entity_unregistered) 以觸發勝利判定。
# - MapLoader.gd: 實際執行實例化房間與生成單位的邏輯。

var current_room_template: RoomTemplate
var _is_transitioning: bool = false

func _ready() -> void:
	print("[DungeonManager] Initialized")
	if BoardManager:
		BoardManager.entity_unregistered.connect(_on_entity_unregistered)

func register_current_room(template: RoomTemplate) -> void:
	current_room_template = template
	print("[DungeonManager] Registered: ", template.room_name)

func start_new_run() -> void:
	print("[DungeonManager] >>> STARTING NEW RUN")
	reset_state()
	# 初始啟動時載入 T001
	load_room_by_name("T001")

func reset_state() -> void:
	current_room_template = null
	_is_transitioning = false
	print("[DungeonManager] State reset.")

func _on_entity_unregistered(entity: Node) -> void:
	if _is_transitioning: return
	
	# BOSS 勝利判定
	if entity is GridEntity and entity.get("is_boss"):
		_kill_all_remaining_enemies()

	# 每次有實體移除，都檢查是否戰鬥結束
	call_deferred("check_battle_status")

func _kill_all_remaining_enemies() -> void:
	var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
	var remaining = BoardManager.get_entities_by_faction(enemy_faction)
	for enemy in remaining:
		if is_instance_valid(enemy) and enemy.has_method("apply_damage"):
			enemy.apply_damage(999999)

func check_battle_status() -> void:
	if _is_transitioning: return
	if TurnManager.current_state == TurnManager.State.LOOT_PHASE: return
	
	if not has_active_enemies():
		handle_battle_cleared()

func has_active_enemies() -> bool:
	var enemies = get_tree().get_nodes_in_group("enemy")
	var active = enemies.filter(func(e):
		return is_instance_valid(e) and not e.get("is_dying")
	)
	return not active.is_empty()

## 戰鬥結束後的決策點
func handle_battle_cleared() -> void:
	if _is_transitioning: return
	
	# 掃描場上戰利品
	var loot = get_tree().get_nodes_in_group("loot")
	var equipment = get_tree().get_nodes_in_group("equipment_entities")
	
	if loot.is_empty() and equipment.is_empty():
		print("[DungeonManager] No loot. Advancing...")
		advance_to_next_room()
	else:
		print("[DungeonManager] Loot detected. Triggering LOOT_PHASE.")
		if TurnManager.has_method("trigger_loot_phase"):
			TurnManager.trigger_loot_phase()
		else:
			advance_to_next_room()

func advance_to_next_room() -> void:
	if _is_transitioning: return
	_is_transitioning = true
	print("[DungeonManager] >>> ADVANCING TO NEXT ROOM")
	
	# 1. 清理掉落物動畫
	_clear_all_loot_visuals()
	
	# 2. 等待物理靜止
	if TurnManager.has_method("_wait_for_physics"):
		await TurnManager._wait_for_physics()
	
	await get_tree().create_timer(0.5).timeout
	
	# 3. 載入新房間
	if current_room_template and current_room_template.next_room_name != "":
		load_room_by_name(current_room_template.next_room_name)
		await get_tree().create_timer(1.0).timeout
		_is_transitioning = false
	else:
		_show_game_clear_ui()

func _clear_all_loot_visuals() -> void:
	var all_loot = get_tree().get_nodes_in_group("loot") + get_tree().get_nodes_in_group("equipment_entities")
	for node in all_loot:
		if not is_instance_valid(node): continue
		if node is RigidBody2D:
			node.collision_layer = 0
			node.collision_mask = 0
			node.freeze = true
		
		var tw = create_tween()
		tw.set_parallel(true)
		tw.tween_property(node, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(node, "modulate:a", 0.0, 0.3)
		tw.set_parallel(false)
		tw.tween_callback(node.queue_free)

func load_room_by_name(room_name: String) -> void:
	var path = "res://Resources/Rooms/" + room_name + ".tres"
	if not ResourceLoader.exists(path):
		# 嘗試大小寫相容
		path = "res://Resources/Rooms/" + room_name.to_upper() + ".tres"
	
	if ResourceLoader.exists(path):
		var template = load(path)
		if template is RoomTemplate:
			_load_room_template(template)

func _load_room_template(template: RoomTemplate) -> void:
	current_room_template = template
	var map_loader = get_tree().get_first_node_in_group("map_loader")
	if not map_loader: return
	
	# 核心優化：在載入新房間前，檢查是否已經有玩家單位在場上
	var player_faction = load("res://Resources/Factions/Faction_Player.tres")
	var existing_players = []
	if BoardManager:
		existing_players = BoardManager.get_entities_by_faction(player_faction)
	
	# 玩家回血
	for p in existing_players:
		if p.character_data:
			var missing = p.character_data.get_effective_max_health() - p.character_data.current_health
			if missing > 0: p.character_data.heal(int(missing * 0.5))
	
	await get_tree().create_timer(0.5).timeout
	var spawned = map_loader.instantiate_room(template)
	
	# 核心修正：僅當場上沒有玩家單位時才進行自動部署 (避免 F2 偵錯或切換房間時重複生成)
	if existing_players.is_empty():
		if map_loader.has_method("_auto_deploy_party"):
			print("[DungeonManager] No existing players found. Triggering auto-deployment for room: ", template.room_name)
			map_loader._auto_deploy_party(template)
	else:
		print("[DungeonManager] %d existing players found. Skipping auto-deployment." % existing_players.size())
		# 如果是已存在的玩家，確保他們被移動到新房間的對應位置 (可選，目前先保持原位或由 instantiate_room 處理)
	
	# 重新註冊玩家位置
	for p in get_tree().get_nodes_in_group("player"):
		var grid_node = get_tree().get_first_node_in_group("grid")
		if grid_node and p.has_method("_register_cells"):
			p.grid_position = grid_node.world_to_grid(p.global_position)
			p._register_cells()
	
	for e in spawned:
		if e.has_method("play_entry_animation"): e.play_entry_animation(0.2)
	
	if TurnManager:
		var pf = load("res://Resources/Factions/Faction_Player.tres")
		var ef = load("res://Resources/Factions/Faction_Enemy.tres")
		TurnManager.start_combat([pf, ef])

func _show_game_clear_ui() -> void:
	var scn = load("res://Scenes/UI/GameClearUI.tscn")
	if scn:
		var ui = scn.instantiate()
		var ui_layer = get_tree().current_scene.get_node_or_null("UI")
		if ui_layer: ui_layer.add_child(ui)
		var deployment_ui = get_tree().get_first_node_in_group("deployment_ui")
		if deployment_ui: deployment_ui.visible = false

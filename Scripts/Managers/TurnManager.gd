extends Node

const TraitServiceScript = preload("res://Scripts/Managers/TraitService.gd")

signal turn_changed(current_faction: FactionDefinition)
signal turn_count_changed(count: int)
signal turn_started(faction: FactionDefinition)
signal turn_ended(faction: FactionDefinition)
signal state_changed(new_state: State)
signal free_roam_mode_changed(enabled: bool)
signal enemy_turn_ticked # 用於通知子彈與攻擊組件的回合步進
signal loot_unlocked # 新增：通知場上所有戰利品可以被拾取了

enum State {
	DEPLOYMENT,
	PLAYER_TURN,
	ENEMY_TURN,
	RESOLVING, # 物理結算中
	WAITING,
	FREE_ROAM,
	LOOT_PHASE # 戰後搜刮階段
}

var current_state: State = State.WAITING

# 回合順序設定
var factions_order: Array[FactionDefinition] = []
var current_faction_index: int = 0
var current_faction: FactionDefinition = null
var turn_count: int = 1

var is_free_roam_mode: bool = false
var _is_input_locked: bool = false
var _units_launched: bool = false
var _is_currently_resolving: bool = false # 結算鎖，防止多重協程衝突

func _ready() -> void:
	Engine.time_scale = 1.0
	add_to_group("turn_manager")

## 全域輸入鎖定
func lock_input() -> void:
	_is_input_locked = true

func unlock_input() -> void:
	_is_input_locked = false

func reset_state() -> void:
	"""重置回合管理器狀態"""
	current_state = State.WAITING
	factions_order.clear()
	current_faction_index = 0
	current_faction = null
	turn_count = 1
	is_free_roam_mode = false
	_is_input_locked = false
	_units_launched = false
	_is_currently_resolving = false
	# print("[TurnManager] State reset.")

## 綜合忙碌狀態判定
func is_busy() -> bool:
	if _is_input_locked: return true
	if current_state == State.RESOLVING: return true
	if current_state == State.ENEMY_TURN: return true
	if current_state == State.WAITING: return false
	
	if current_state != State.PLAYER_TURN and current_state != State.DEPLOYMENT and current_state != State.LOOT_PHASE and not is_free_roam_mode:
		return true
		
	return false

## 初始化戰鬥並進入部署階段
func start_combat(factions: Array[FactionDefinition]) -> void:
	if factions.is_empty():
		push_error("[TurnManager] Cannot start combat with empty factions list")
		return
		
	factions_order = factions
	current_faction_index = 0
	turn_count = 1
	current_faction = factions_order[current_faction_index]
	is_free_roam_mode = false
	
	_set_state(State.DEPLOYMENT)
	if PartyManager:
		PartyManager.start_deployment()
	else:
		end_deployment()

## 結束部署，開始第一回合
func end_deployment() -> void:
	if current_faction.is_controllable:
		_set_state(State.PLAYER_TURN)
	else:
		_set_state(State.ENEMY_TURN)
	start_turn()

## 開始當前回合
func start_turn() -> void:
	# print("[TurnManager] start_turn() for Faction: %s" % [current_faction.faction_name if current_faction else "None"])
	if current_faction == null: return
	if is_free_roam_mode:
		_ensure_player_control()
		return
		
	_decrement_all_skill_cooldowns()
	enemy_turn_ticked.emit()
	
	if current_faction.is_controllable:
		_set_state(State.PLAYER_TURN)
		_units_launched = false
		if AttackManager:
			AttackManager.reset_global_combo()
		# 玩家回合開始：解鎖所有玩家單位
		unlock_all_players()
		# 解鎖戰利品拾取權限
		loot_unlocked.emit()
	else:
		_set_state(State.ENEMY_TURN)
		# 敵人回合開始前：確保所有單位（含玩家）都處於鎖定狀態，防止被誤推
		lock_all_entities()
		await _execute_enemy_actions()
		
		# 敵人回合結束：最終全體鎖定
		lock_all_entities()
		advance_turn()
		return
	
	turn_started.emit(current_faction)
	turn_changed.emit(current_faction)
	turn_count_changed.emit(turn_count)

func _execute_enemy_actions() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		
		var attack_comp = enemy.get_node_or_null("AttackComponent")
		if attack_comp:
			# 1. 解鎖當前行動的敵人
			if enemy.has_method("unlock_physics"):
				enemy.unlock_physics()
			
			# 2. 執行攻擊
			if attack_comp.has_method("perform_attack"):
				_units_launched = false
				await attack_comp.perform_attack()
				
				# 3. 等待該敵人的物理結算
				_set_state(State.RESOLVING)
				await _wait_for_physics()
				_set_state(State.ENEMY_TURN)
			
			# 4. 行動完畢後立即鎖定
			lock_all_entities()
			await get_tree().create_timer(0.4).timeout

func lock_all_entities() -> void:
	"""鎖定場上所有實體"""
	# 在搜刮階段不執行鎖定，除非是轉場前
	if current_state == State.LOOT_PHASE:
		return
		
	var entities = get_tree().get_nodes_in_group("grid_entities")
	for e in entities:
		if e.has_method("lock_physics"):
			e.lock_physics()

func unlock_all_players() -> void:
	"""解鎖所有玩家單位"""
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("unlock_physics"):
			p.unlock_physics()

func _wait_for_physics() -> void:
	"""嚴謹的物理結算協程"""
	# print("[TurnManager] Resolving physics...")
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var still_frames = 0
	var required_still_frames = 10
	
	while still_frames < required_still_frames:
		var entities = get_tree().get_nodes_in_group("grid_entities")
		var moving = false
		for e in entities:
			if e is RigidBody2D and not e.freeze:
				if e.linear_velocity.length() > 2.0:
					moving = true
					break
		
		var projectiles = get_tree().get_nodes_in_group("projectiles")
		if moving or not projectiles.is_empty():
			still_frames = 0
		else:
			still_frames += 1
		
		await get_tree().process_frame
	
	# print("[TurnManager] Physics settled.")
	
	# 物理結算完成後，根據設定決定是否自動回收金幣
	var should_auto = true
	if GlobalSettings and GlobalSettings.has_method("get_auto_collect_coins"):
		should_auto = GlobalSettings.get_auto_collect_coins()
	
	if should_auto:
		_collect_all_physical_coins()

func _collect_all_physical_coins() -> void:
	var coins = get_tree().get_nodes_in_group("physical_coins")
	if coins.is_empty(): return
	
	var target_pos = Vector2(40, 40)
	var hud = get_tree().get_first_node_in_group("resource_hud")
	if hud and hud.has_node("CoinEntry/Icon"):
		target_pos = hud.get_node("CoinEntry/Icon").global_position
	
	for coin in coins:
		if coin.has_method("collect"):
			coin.collect(target_pos)

func advance_turn() -> void:
	# print("[TurnManager] advance_turn() called. Current Faction: %s" % [current_faction.faction_name if current_faction else "None"])
	if current_faction == null: return
	if is_free_roam_mode:
		_ensure_player_control()
		return
		
	# 如果已經進入搜刮階段，禁止正常回合遞進
	if current_state == State.LOOT_PHASE:
		print("[TurnManager] advance_turn blocked: Currently in LOOT_PHASE.")
		return
		
	turn_ended.emit(current_faction)
	current_faction_index = (current_faction_index + 1) % factions_order.size()
	current_faction = factions_order[current_faction_index]
	
	if current_faction_index == 0:
		turn_count += 1
		
	# print("[TurnManager] Advancing to Faction Index: %d (%s)" % [current_faction_index, current_faction.faction_name])
	start_turn()

func on_unit_launched(_unit: Node, _force: Vector2) -> void:
	_units_launched = true
	# print("[TurnManager] Unit/Projectile launched: %s, Current State: %s" % [_unit.name, State.keys()[current_state]])
	
	# 如果已經在結算中，忽略此次呼叫，由現有的結算流程統一處理
	if _is_currently_resolving:
		# print("[TurnManager] Already resolving, ignoring launch event from: ", _unit.name)
		return
		
	# 核心修正：如果是敵人回合發射，將狀態轉為 RESOLVING 並等待物理靜止
	# 但不啟動 _resolve_action (因為那是專屬玩家/搜刮階段的邏輯)
	if current_state == State.ENEMY_TURN:
		_resolve_enemy_action()
	else:
		_resolve_action()

func _resolve_enemy_action() -> void:
	if _is_currently_resolving: return
	_is_currently_resolving = true
	
	# print("[TurnManager] _resolve_enemy_action() started.")
	_set_state(State.RESOLVING)
	await _wait_for_physics()
	
	# print("[TurnManager] Enemy action physics settled. Returning to ENEMY_TURN.")
	_set_state(State.ENEMY_TURN)
	_is_currently_resolving = false

func _resolve_action() -> void:
	if _is_currently_resolving: return
	_is_currently_resolving = true
	
	var prev_state = current_state
	# print("[TurnManager] _resolve_action() started. Previous State: ", State.keys()[prev_state])
	_set_state(State.RESOLVING)
	
	await _wait_for_physics()
	
	# print("[TurnManager] _resolve_action() physics settled. Deciding next step...")
	
	# 核心修正：結算結束後，先釋放鎖，再執行進關或換人邏輯，避免遞歸死鎖
	_is_currently_resolving = false
	
	# 根據結算前的狀態決定下一步
	if prev_state == State.LOOT_PHASE:
		# 搜刮射擊結束，交由 DungeonManager 處理轉場
		if DungeonManager:
			# print("[TurnManager] LOOT_PHASE resolved. Calling DungeonManager.advance_to_next_room()")
			DungeonManager.advance_to_next_room()
	elif prev_state == State.PLAYER_TURN or prev_state == State.DEPLOYMENT:
		# 正常玩家回合或部署階段射擊結束，檢查是否還有敵人
		var has_enemies = false
		if DungeonManager:
			has_enemies = DungeonManager.has_active_enemies()
			# print("[TurnManager] PLAYER_TURN/DEPLOYMENT resolved. Active enemies: ", has_enemies)
			
		if not has_enemies:
			# print("[TurnManager] No enemies remaining. Calling DungeonManager.handle_battle_cleared()")
			DungeonManager.handle_battle_cleared()
		else:
			# print("[TurnManager] Enemies still present. Locking entities and advancing turn.")
			lock_all_entities()
			advance_turn()
	else:
		# print("[TurnManager] RESOLVE completed for state: ", State.keys()[prev_state], ". Advancing turn.")
		lock_all_entities()
		advance_turn()

func trigger_loot_phase() -> void:
	print("[TurnManager] Entering LOOT_PHASE")
	_set_state(State.LOOT_PHASE)
	unlock_all_players()
	loot_unlocked.emit() # 進入搜刮階段也要解鎖
	if AttackManager:
		AttackManager.reset_global_combo()

func _set_state(new_state: State) -> void:
	if current_state == new_state: return
	# print("[TurnManager] State: ", State.keys()[current_state], " -> ", State.keys()[new_state])
	current_state = new_state
	state_changed.emit(new_state)
	
	# 核心修正：狀態變更時，強制通知 UI 更新
	turn_changed.emit(current_faction)

func _decrement_all_skill_cooldowns() -> void:
	var entities = get_tree().get_nodes_in_group("grid_entities")
	for e in entities:
		if e is GridEntity and e.character_data:
			e.character_data.decrement_cooldowns()

func set_free_roam_mode(enabled: bool) -> void:
	is_free_roam_mode = enabled
	free_roam_mode_changed.emit(enabled)
	if enabled: _ensure_player_control()

func _ensure_player_control() -> void:
	for i in range(factions_order.size()):
		if factions_order[i].is_controllable:
			current_faction_index = i
			current_faction = factions_order[i]
			_set_state(State.PLAYER_TURN)
			break

func is_enemy_turn() -> bool:
	return current_state == State.ENEMY_TURN

func is_player_turn() -> bool:
	return is_free_roam_mode or current_state == State.PLAYER_TURN or current_state == State.LOOT_PHASE

func get_phase_name() -> String:
	if is_free_roam_mode: return "Free Roam"
	return State.keys()[current_state]

func _spawn_random_enemy() -> void:
	var grid = get_tree().get_first_node_in_group("grid")
	var map_loader = get_tree().get_first_node_in_group("map_loader")
	if not grid or not map_loader: return
	
	var spawn_cell = Vector2i.ZERO
	var found = false
	for i in range(20):
		var cell = Vector2i(randi() % grid.map_width, randi() % grid.map_height)
		if not grid.is_cell_occupied(cell):
			spawn_cell = cell
			found = true
			break
	
	if not found: return
	
	var enemy_pool = ["res://Resources/Cards/Enemy_001.tres", "res://Resources/Cards/Enemy_003.tres", "res://Resources/Cards/Enemy_004.tres", "res://Resources/Cards/Enemy_005.tres"]
	var enemy_card_path = enemy_pool.pick_random()
	
	var multiplier = 1.0 + (turn_count * 0.1)
	var atk_multiplier = 1.0 + (turn_count * 0.05)
	
	var template = RoomTemplate.new()
	var new_entities: Array[Dictionary] = []
	new_entities.append({
		"pos": spawn_cell,
		"card_path": enemy_card_path,
		"overrides": {
			"max_health": int(500 * multiplier),
			"attack_damage": int(10 * atk_multiplier)
		}
	})
	template.entities = new_entities
	
	var spawned = map_loader.instantiate_room(template)
	for enemy in spawned:
		if enemy.has_method("play_entry_animation"):
			enemy.play_entry_animation(0.2)

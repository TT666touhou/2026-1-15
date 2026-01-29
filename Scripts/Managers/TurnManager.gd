extends Node

const TraitServiceScript = preload("res://Scripts/Managers/TraitService.gd")

signal turn_changed(current_faction: FactionDefinition)
signal turn_count_changed(count: int)
signal turn_started(faction: FactionDefinition)
signal turn_ended(faction: FactionDefinition)
signal state_changed(new_state: State)
signal free_roam_mode_changed(enabled: bool)
signal enemy_turn_ticked # 用於通知子彈與攻擊組件的回合步進

enum State {
	DEPLOYMENT,
	PLAYER_TURN,
	ENEMY_TURN,
	RESOLVING, # 物理結算中
	WAITING,
	FREE_ROAM
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
	print("[TurnManager] State reset.")

## 綜合忙碌狀態判定
func is_busy() -> bool:
	if _is_input_locked: return true
	if current_state == State.RESOLVING: return true
	if current_state == State.ENEMY_TURN: return true
	if current_state == State.WAITING: return false
	
	if current_state != State.PLAYER_TURN and current_state != State.DEPLOYMENT and not is_free_roam_mode:
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
	else:
		_set_state(State.ENEMY_TURN)
		# 敵人回合開始前：確保所有單位（含玩家）都處於鎖定狀態，防止被誤推
		lock_all_entities()
		await _execute_enemy_actions()
		
		# 敵人回合結束：最終全體鎖定
		lock_all_entities()
		advance_turn()
		return
	
	# TraitServiceScript.apply_trigger(TraitEffect.TriggerType.TURN_START, {"faction": current_faction})
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
				
				# 3. 等待該敵人的物理結算 (包含母體與可能產生的分身)
				_set_state(State.RESOLVING)
				await _wait_for_physics()
				_set_state(State.ENEMY_TURN)
			
			# 4. 行動完畢後立即鎖定該敵人及其可能產生的分身
			lock_all_entities()
			
			await get_tree().create_timer(0.4).timeout

func lock_all_entities() -> void:
	"""鎖定場上所有實體（玩家、敵人、分身）"""
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
	print("[TurnManager] Resolving physics...")
	# 增加等待幀數，確保所有衝量 (Impulse) 已經轉換為速度
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var still_frames = 0
	var required_still_frames = 10 # 增加判定幀數，防止中途停頓誤判
	
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
	
	print("[TurnManager] Physics settled.")
	
	# 核心優化：物理結算完成後，自動回收場上所有金幣
	_collect_all_physical_coins()

func _collect_all_physical_coins() -> void:
	var coins = get_tree().get_nodes_in_group("physical_coins")
	if coins.is_empty(): return
	
	# 獲取 UI 金幣圖示位置
	var target_pos = Vector2(40, 40) # 預設左上角
	var hud = get_tree().get_first_node_in_group("resource_hud")
	if hud and hud.has_node("CoinEntry/Icon"):
		target_pos = hud.get_node("CoinEntry/Icon").global_position
	
	print("[TurnManager] Collecting %d coins to UI..." % coins.size())
	for coin in coins:
		if coin.has_method("collect"):
			coin.collect(target_pos)

func advance_turn() -> void:
	if current_faction == null: return
	if is_free_roam_mode:
		_ensure_player_control()
		return
		
	turn_ended.emit(current_faction)
	current_faction_index = (current_faction_index + 1) % factions_order.size()
	current_faction = factions_order[current_faction_index]
	
	if current_faction_index == 0:
		turn_count += 1
		
	start_turn()

func on_unit_launched(_unit: Node, _force: Vector2) -> void:
	_units_launched = true
	print("[TurnManager] Unit/Projectile launched: ", _unit.name)
	if current_state == State.PLAYER_TURN:
		_resolve_player_action()

func _resolve_player_action() -> void:
	_set_state(State.RESOLVING)
	await _wait_for_physics()
	# 玩家行動結算完畢：鎖定所有實體
	lock_all_entities()
	advance_turn()

func _set_state(new_state: State) -> void:
	if current_state == new_state: return
	print("[TurnManager] State: ", State.keys()[current_state], " -> ", State.keys()[new_state])
	current_state = new_state
	state_changed.emit(new_state)
	
	# 物理保護邏輯已移至 lock_all_entities / unlock_all_players 統一調度
	# 這裡不再分散處理 _set_player_units_frozen

func _set_player_units_frozen(_frozen: bool) -> void:
	# [已棄用] 統一由 lock_physics / unlock_physics 管理
	pass

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
	return is_free_roam_mode or current_state == State.PLAYER_TURN

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

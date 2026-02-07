extends Node

# [TurnManager] 核心回合管理器 (Autoload)
# 職責：
# 1. 驅動戰鬥回合循環 (玩家、敵人、結算、搜刮)。
# 2. 嚴格控管物理結算 (RESOLVING) 流程，確保傷害與 UI 數值一致。
# 3. 作為多個 Manager 的中繼站，協調場地、隊伍與 UI 狀態。

# [相關外部連動腳本]:
# - DungeonManager.gd: 負責告知是否還有敵人 (has_active_enemies)，並在戰鬥清空時進場 (handle_battle_cleared)。
# - PartyManager.gd: 在戰鬥開始時切換部署階段 (start_deployment)。
# - AttackManager.gd: 在每一波物理結算完成後，重置全域連擊數 (reset_global_combo)。
# - BoardManager.gd: 提供場上實體資訊供鎖定物理 (lock_physics)。
# - GridEntity.gd / CharacterData.gd: 回合開始時扣除冷卻時間 (decrement_cooldowns)。

# 核心依賴
const TraitServiceScript = preload("res://Scripts/Managers/TraitService.gd")

# 對外信號 (用於同步 UI 與 實體狀態)
signal turn_changed(current_faction: FactionDefinition) # 陣營變更 (用於頂部 Bar 顯示)
signal turn_count_changed(count: int) # 回合計數更新
signal turn_started(faction: FactionDefinition) # 當前回合正式啟動
signal turn_ended(faction: FactionDefinition) # 當前回合結束清理
signal state_changed(new_state: State) # 狀態機切換時觸發
signal free_roam_mode_changed(enabled: bool) # 自由跑圖狀態同步
signal enemy_turn_ticked # 回合步進信号 (子彈/狀態扣除用)
signal loot_unlocked # 拾取權限解鎖 (戰後出現)
signal turn_visuals_finished # 新增：UI 動畫播放完畢信號 (解除回合鎖定)

enum State {
	DEPLOYMENT, # 部署階段 (連動 PartyManager)
	PLAYER_TURN, # 玩家操作階段 (允許輸入、解鎖物理)
	ENEMY_TURN, # 敵人 AI 執行階段 (自動化攻擊序列)
	RESOLVING, # 物理結算階段 (等待所有 RigidBody 靜止與子彈消失)
	WAITING, # 初始閒置
	FREE_ROAM, # 自由跑圖 (非戰鬥狀態)
	LOOT_PHASE # 戰後搜刮 (敵人全清但尚未轉場，允許玩家拾取掉落物)
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
var _active_resolution_faction: FactionDefinition = null # 記錄當前觸發結算的陣營

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
	_active_resolution_faction = null
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
		
	# 確保狀態重置
	reset_state()
	
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
## 流程：扣除冷卻 -> 發送 Tick 信号 -> 進入陣營專屬邏輯
func start_turn() -> void:
	# [邏輯匯總]: 這裡是回合切換的最上層進入點
	if current_faction == null: return
	if is_free_roam_mode:
		_ensure_player_control()
		return
		
	# 1. 冷卻與步進通知 (連動技能系統與組件)
	_decrement_all_skill_cooldowns()
	enemy_turn_ticked.emit()
	
	turn_started.emit(current_faction)
	turn_changed.emit(current_faction)
	turn_count_changed.emit(turn_count)
	
	if current_faction.is_controllable:
		# 玩家回合：解鎖物理與拾取權限
		_set_state(State.PLAYER_TURN)
		_units_launched = false
		unlock_all_players()
		loot_unlocked.emit()
	else:
		# 敵人回合：鎖定所有實體，執行自動化攻擊 (連動 AttackComponent)
		_set_state(State.ENEMY_TURN)
		lock_all_entities()
		
		# 檢查是否有回合提示 UI 存在，若有則等待其動畫結束
		# 避免硬編碼時間，改用信號同步
		if not get_tree().get_nodes_in_group("turn_indicator").is_empty():
			await turn_visuals_finished
		
		await _execute_enemy_actions()
		
		# 動畫與結算完成後，自動跳轉下一回合
		lock_all_entities()
		advance_turn()
		return

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
	"""解鎖所有玩家單位 (連動 GridEntity.gd: unlock_physics)"""
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
	
	# 核心修正：物理靜止後，重置全域連擊數
	if AttackManager:
		AttackManager.reset_global_combo()
	
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

## 切換至下一個陣營的回合
func advance_turn() -> void:
	# [邏輯匯總]: 負責計算 faction 索引並遞增 turn_count
	if current_faction == null: return
	if is_free_roam_mode:
		_ensure_player_control()
		return
		
	# 如果已經進入搜刮階段，禁止正常回合遞進 (由 DungeonManager 轉場觸發 reset)
	if current_state == State.LOOT_PHASE:
		print("[TurnManager] advance_turn blocked: Currently in LOOT_PHASE.")
		return
		
	turn_ended.emit(current_faction)
	current_faction_index = (current_faction_index + 1) % factions_order.size()
	current_faction = factions_order[current_faction_index]
	
	if current_faction_index == 0:
		turn_count += 1
		
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
	_active_resolution_faction = current_faction
	
	# print("[TurnManager] _resolve_enemy_action() started.")
	_set_state(State.RESOLVING)
	await _wait_for_physics()
	
	# print("[TurnManager] Enemy action physics settled. Returning to ENEMY_TURN.")
	_set_state(State.ENEMY_TURN)
	_is_currently_resolving = false
	_active_resolution_faction = null

func _resolve_action() -> void:
	if _is_currently_resolving: return
	_is_currently_resolving = true
	_active_resolution_faction = current_faction
	
	var prev_state = current_state
	# print("[TurnManager] _resolve_action() started. Previous State: ", State.keys()[prev_state])
	_set_state(State.RESOLVING)
	
	await _wait_for_physics()
	
	# print("[TurnManager] _resolve_action() physics settled. Deciding next step...")
	
	# 核心修正：結算結束後，先釋放鎖，再執行進關或換人邏輯，避免遞歸死鎖
	_is_currently_resolving = false
	_active_resolution_faction = null
	
	# 物理結算靜止後的邏輯分歧
	if prev_state == State.LOOT_PHASE:
		# 搜刮結束：前往下一個房間 (連動 DungeonManager)
		if DungeonManager:
			DungeonManager.advance_to_next_room()
	elif prev_state == State.PLAYER_TURN or prev_state == State.DEPLOYMENT:
		# 戰鬥結束檢查：如果沒敵人了進入 handle_battle_cleared (連動 DungeonManager)
		var has_enemies = false
		if DungeonManager:
			has_enemies = DungeonManager.has_active_enemies()
			
		if not has_enemies:
			DungeonManager.handle_battle_cleared()
		else:
			# 還有敵人：鎖定實體並跳轉下一回合 (敵人回合)
			lock_all_entities()
			advance_turn()
	else:
		lock_all_entities()
		advance_turn()

func trigger_loot_phase() -> void:
	print("[TurnManager] Entering LOOT_PHASE")
	_set_state(State.LOOT_PHASE)
	unlock_all_players()
	loot_unlocked.emit() # 進入搜刮階段也要解鎖
	# 移除重複的 Combo 重置，統一由物理靜止觸發
	turn_started.emit(current_faction) # 確保 UI 更新

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

## UI 呼叫此方法通知動畫結束
func report_turn_visuals_finished() -> void:
	turn_visuals_finished.emit()

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
	if is_free_roam_mode: return true
	if current_state == State.PLAYER_TURN or current_state == State.LOOT_PHASE:
		return true
	if current_state == State.RESOLVING and _active_resolution_faction:
		return _active_resolution_faction.is_controllable
	return false

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

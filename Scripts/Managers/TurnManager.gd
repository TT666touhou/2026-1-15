extends Node

const TraitServiceScript = preload("res://Scripts/Managers/TraitService.gd")

signal turn_changed(current_faction: FactionDefinition)
signal turn_count_changed(count: int)
signal turn_started(faction: FactionDefinition)
signal turn_ended(faction: FactionDefinition)
signal state_changed(new_state: State)
signal free_roam_mode_changed(enabled: bool)

enum State {
	DEPLOYMENT,
	PLAYER_TURN,
	ENEMY_TURN,
	WAITING,
	FREE_ROAM # 新增狀態，雖然可以用 flag 控制，但明確狀態可能更好
}

var current_state: State = State.WAITING

# 回合順序設定
var factions_order: Array[FactionDefinition] = []
var current_faction_index: int = 0
var current_faction: FactionDefinition = null
var turn_count: int = 1

var is_free_roam_mode: bool = false
var _is_input_locked: bool = false

func _ready() -> void:
	pass

## 全域輸入鎖定
func lock_input() -> void:
	_is_input_locked = true
	# print("[TurnManager] Input LOCKED")

func unlock_input() -> void:
	_is_input_locked = false
	# print("[TurnManager] Input UNLOCKED")

## 綜合忙碌狀態判定
func is_busy() -> bool:
	# 1. 內部手動鎖定
	if _is_input_locked: return true
	
	# 2. 目前不是玩家回合 (除非在自由漫遊模式下，會由 _ensure_player_control 強制設為 PLAYER_TURN)
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
	is_free_roam_mode = false # Reset free roam
	
	# Enter Deployment Phase
	_set_state(State.DEPLOYMENT)
	if PartyManager:
		PartyManager.start_deployment()
	else:
		push_warning("[TurnManager] PartyManager not found, skipping deployment")
		end_deployment()

## 結束部署，開始第一回合
func end_deployment() -> void:
	# Determine initial state based on first faction
	if current_faction.is_controllable:
		_set_state(State.PLAYER_TURN)
	else:
		_set_state(State.ENEMY_TURN)
		
	start_turn()

## 開始當前回合
func start_turn() -> void:
	if current_faction == null:
		return
		
	# 如果在 Free Roam 模式，強制保持玩家狀態，不觸發回合開始邏輯
	if is_free_roam_mode:
		_ensure_player_control()
		return
		
	# 核心：重置所有單位的技能冷卻與移動標記 (不分陣營，確保所有人都能在下一輪行動)
	_decrement_all_skill_cooldowns()
	
	if current_faction.is_controllable:
		_set_state(State.PLAYER_TURN)
	else:
		_set_state(State.ENEMY_TURN)
		_run_enemy_ai_sequence()
	
	# Trait: TURN_START 事件
	TraitServiceScript.apply_trigger(TraitEffect.TriggerType.TURN_START, {"faction": current_faction})
	
	turn_started.emit(current_faction)
	turn_changed.emit(current_faction)
	turn_count_changed.emit(turn_count)

func _run_enemy_ai_sequence() -> void:
	# 1. 稍微延遲一點讓 UI 顯示「敵人回合」
	await get_tree().create_timer(0.4).timeout
	
	# 2. 計算最佳單一移動方案 (Greedy Single Move)
	var move_data = EnemyAIController.calculate_best_move(get_tree(), current_faction)
	
	# 3. 執行移動
	if not move_data.is_empty():
		var unit = move_data.unit
		var target_cell = move_data.cell
		
		if unit.grid_position != target_cell:
			print("[TurnManager] AI moving single unit ", unit.name, " to ", target_cell)
			var mover = unit.get_node_or_null("GridMover")
			if mover:
				lock_input() # AI 移動期間也鎖定，防止玩家誤操作
				await mover.move_to(target_cell)
				unlock_input()
				# 移動完畢後稍微停頓
				await get_tree().create_timer(0.2).timeout
			else:
				unit.set_grid_position(target_cell)
		else:
			print("[TurnManager] AI decided to stay still.")
			await get_tree().create_timer(0.4).timeout
	else:
		print("[TurnManager] No valid move found for AI.")
		await get_tree().create_timer(0.4).timeout
	
	# 4. 進入結算階段 (執行攻擊)
	await advance_turn()

func _decrement_all_skill_cooldowns() -> void:
	var entities = get_tree().get_nodes_in_group("grid_entities")
	for e in entities:
		if e is GridEntity and e.character_data:
			e.character_data.decrement_cooldowns()

## 結束當前回合並進入下一回合
func advance_turn() -> void:
	if current_faction == null:
		return
		
	# 執行攻擊結算 (Attack Phase)
	lock_input()
	await resolve_attacks()
	unlock_input()
	
	# 如果在結算過程中觸發了 Free Roam (例如最後一個敵人死亡)，則停止回合推進
	if is_free_roam_mode:
		_ensure_player_control()
		return
		
	turn_ended.emit(current_faction)
	
	# 切換到下一個陣營
	current_faction_index = (current_faction_index + 1) % factions_order.size()
	current_faction = factions_order[current_faction_index]
	
	# 如果回到第一個陣營，回合數 +1
	if current_faction_index == 0:
		turn_count += 1
		
	start_turn()

## 設置自由探索模式
func set_free_roam_mode(enabled: bool) -> void:
	if is_free_roam_mode == enabled:
		return
		
	is_free_roam_mode = enabled
	free_roam_mode_changed.emit(enabled)
	
	if enabled:
		# 啟用時，確保玩家獲得控制權
		_ensure_player_control()
	else:
		# 停用時，可能需要重置回合或恢復狀態 (視需求而定)
		# 目前假設停用通常發生在進入新房間，start_combat 會被調用，那裡會重置
		pass

func _ensure_player_control() -> void:
	# 尋找玩家陣營
	var player_faction = null
	var index = 0
	for f in factions_order:
		if f.is_controllable:
			player_faction = f
			current_faction_index = index
			break
		index += 1
	
	if player_faction:
		current_faction = player_faction
		_set_state(State.PLAYER_TURN) # 保持在 PLAYER_TURN 狀態以便 GridSelector 運作
	else:
		push_error("[TurnManager] No controllable faction found for Free Roam")

## 檢查是否是玩家回合
func is_player_turn() -> bool:
	# 在 Free Roam 模式下，視為玩家回合
	if is_free_roam_mode:
		return true
	return current_state == State.PLAYER_TURN

## 獲取當前階段名稱
func get_phase_name() -> String:
	if is_free_roam_mode:
		return "Free Roam"
		
	match current_state:
		State.DEPLOYMENT: return "Deployment"
		State.PLAYER_TURN: return "Player Turn"
		State.ENEMY_TURN: return "Enemy Turn"
		State.WAITING: return "Waiting"
	return "None"

func _set_state(new_state: State) -> void:
	current_state = new_state
	state_changed.emit(new_state)

func resolve_attacks() -> void:
	"""結算當前陣營的攻擊 (序列化異步執行)"""
	if AttackManager == null:
		return
		
	# 1. 獲取戰鬥計畫
	var combat_plan = AttackManager.get_combat_actions(current_faction)
	
	if combat_plan.is_empty():
		return
		
	# 2. 依序執行每個攻擊事件
	for event in combat_plan:
		# --- 關鍵檢查：如果房間已經清空 (例如 BOSS 死亡進入 Free Roam)，立即停止所有後續攻擊 ---
		if is_free_roam_mode:
			print("[TurnManager] Room cleared (Free Roam), stopping remaining attack events.")
			break

		var target = event.target
		if target == null or not is_instance_valid(target):
			continue
			
		# 確保目標還活著 (如果連鎖反應導致死亡)
		if target.character_data and target.character_data.current_health <= 0:
			continue
			
		# 初始化 Combo 顯示 (0)
		if target.has_method("update_combo_display"):
			target.update_combo_display(0)
			
		# --- 階段一：序列化蓄力與統計 Hits ---
		var current_total_hits = 0
		var resolved_damage = 0
		
		# 用於暫存每個攻擊者的基礎數值，供 Phase 2 使用
		var attacker_stats: Dictionary = {} # { Attacker: { "base_damage": int, "hits": int } }
		
		for attacker in event.attackers:
			if is_free_roam_mode: break
			if not is_instance_valid(attacker):
				continue
				
			# 1. 播放蓄力動畫 (Tick)
			var visuals = attacker.get_node_or_null("UnitVisuals")
			if visuals and visuals.has_method("play_tick_animation"):
				visuals.play_tick_animation()
				
			# 2. 計算該攻擊者的實際 Hits (含機率)
			var hits = 0
			# 從 Event 獲取正確的 Hits 數 (由 AttackManager 計算)
			if event.attacker_hit_counts.has(attacker):
				var arrow_count = event.attacker_hit_counts[attacker]
				# 使用新方法：每個箭頭獨立計算機率
				hits = AttackManager.resolve_total_hits(attacker, arrow_count)
			else:
				# 數據異常：直接報錯，不進行模糊推測
				push_error("[TurnManager] Critical Error: Missing hit count data for attacker " + str(attacker))
				hits = 0

				
			current_total_hits += hits
			
			# 3. 計算該攻擊者的傷害 (含暴擊)
			var damage = 0
			if attacker.character_data:
				# 使用 Effective Attack (已包含 Passive Traits)
				damage = attacker.character_data.get_effective_attack()
				# 暴擊判定
				var crit_rate = attacker.character_data.crit_rate
				var crit_bonus = 1.0
				if randf() < crit_rate:
					# 基礎 200% + 額外加成 (CDM)
					var extra_crit = attacker.character_data.get_effective_crit_dmg()
					crit_bonus = 2.0 + extra_crit
					print("[TurnManager] CRITICAL HIT! Bonus: %.2f (Base 2.0 + Extra %.2f)" % [crit_bonus, extra_crit])
				damage = int(damage * crit_bonus)
			
			# 暫存數據
			attacker_stats[attacker] = {
				"base_damage": damage,
				"hits": hits
			}
			
			# 4. 更新目標 UI
			if is_instance_valid(target) and target.has_method("update_combo_display"):
				target.update_combo_display(current_total_hits)
				
			# 5. 顯示攻擊預告數值 (基礎值)
			if attacker.has_method("show_attack_number"):
				attacker.show_attack_number(damage)
				
			# 6. 等待動畫時間 (約 0.3s - 0.4s)
			await get_tree().create_timer(0.4).timeout
			
		# --- 階段一.五：Trait 判定與數值刷新 ---
		# 在所有 Hits 統計完畢後，檢查 Leader Skill
		
		var trait_applied = false
		
		for attacker in event.attackers:
			if not is_instance_valid(attacker) or not attacker_stats.has(attacker):
				continue
				
			var stats = attacker_stats[attacker]
			var base_dmg = stats["base_damage"]
			
			# 計算 Trait 加成
			if not is_instance_valid(target): continue
			var trait_bonus = AttackManager.calculate_trait_bonus(attacker, target, current_total_hits)
			
			if trait_bonus > 1.001: # 浮點數容差
				trait_applied = true
				var new_dmg = int(base_dmg * trait_bonus)
				stats["base_damage"] = new_dmg # 更新暫存傷害
				
				# 刷新 UI 顯示
				if attacker.has_method("show_attack_number"):
					attacker.show_attack_number(new_dmg)
					
				# 當傷害因為 Trait 改變時，播放 Tick 動畫 (永久性規則)
				var visuals = attacker.get_node_or_null("UnitVisuals")
				if visuals and visuals.has_method("play_tick_animation"):
					visuals.play_tick_animation()
					
		if trait_applied:
			# 若有數值更新，稍微停頓讓玩家看清
			await get_tree().create_timer(0.3).timeout

		if is_free_roam_mode: break

		# --- 階段二：執行攻擊與結算 ---
		
		# 重新計算總傷害 (基於更新後的 attacker_stats)
		resolved_damage = 0
		for attacker in event.attackers:
			if attacker_stats.has(attacker):
				resolved_damage += attacker_stats[attacker]["base_damage"] * attacker_stats[attacker]["hits"]
		
		# 計算合擊倍率
		var combo_multiplier = 1.0
		if current_total_hits >= 2:
			# 檢查是否有 >= 2 個不同的攻擊者
			var unique_attackers = {}
			for att in event.attackers:
				unique_attackers[att] = true
			if unique_attackers.size() >= 2:
				combo_multiplier = 1.0 + (current_total_hits * 0.125)
				
		var final_damage = int(resolved_damage * combo_multiplier)
		
		# 播放攻擊動畫 (齊發)
		for attacker in event.attackers:
			if is_instance_valid(attacker):
				# 清除攻擊預告文字
				if attacker.has_method("dismiss_attack_number"):
					attacker.dismiss_attack_number()
					
				var directions = event.attack_directions[attacker] # 預期是 Array
				
				if directions is Array:
					# 播放第一個方向的動畫 (或者根據需求播放多個)
					# 目前只播放第一個以保持簡單
					if not directions.is_empty():
						attacker.play_attack_animation_towards(directions[0])
				elif directions is Vector2i:
					# 兼容舊代碼
					attacker.play_attack_animation_towards(directions)
		
		# 等待攻擊前搖 (Windup)
		await get_tree().create_timer(0.2).timeout
		
		# --- 鎖定死亡 ---
		if is_instance_valid(target) and target.has_method("start_combo_sequence"):
			target.start_combo_sequence()
		elif not is_instance_valid(target):
			continue # 如果目標已經在蓄力期間死亡（例如 BOSS 觸發的全滅），則跳過執行
		
		# --- 分段造成傷害 (Multi-Hit) 與 追擊 (Pursuit) ---
		# 將總傷害按比例分配給每個攻擊者的每一擊
		if current_total_hits > 0:
			for attacker in event.attackers:
				if is_free_roam_mode: break
				if not is_instance_valid(attacker) or not attacker_stats.has(attacker):
					continue
					
				var hits = attacker_stats[attacker]["hits"]
				if hits <= 0: continue
				
				# 該攻擊者貢獻的原始總傷 (已含暴擊與 Trait)
				var attacker_base_total = attacker_stats[attacker]["base_damage"] * hits
				# 套用合擊倍率後的最終總傷
				var attacker_final_total = int(attacker_base_total * combo_multiplier)
				
				var dmg_per_hit = int(float(attacker_final_total) / hits)
				var remainder = attacker_final_total % hits
				
				for i in range(hits):
					if is_free_roam_mode: break
					if not is_instance_valid(target): break
					if target.character_data and target.character_data.current_health <= 0: break
					
					# 命中判定
					var hit_success = true
					if AttackManager.has_method("check_hit"):
						hit_success = AttackManager.check_hit(attacker, target)
					
					if hit_success:
						var dmg = dmg_per_hit
						if i < remainder: dmg += 1
						
						if dmg > 0:
							# 1. 先造成基礎傷害
							if is_instance_valid(target):
								target.apply_damage(dmg, false, false, attacker)
							
							# 2. 觸發吸血 (Drain)
							if attacker.character_data:
								var drain_rate = attacker.character_data.get_effective_drain()
								if drain_rate > 0:
									var heal_amount = int(dmg * drain_rate)
									if heal_amount > 0:
										attacker.character_data.heal(heal_amount)
										if attacker.has_method("show_heal_number"):
											attacker.show_heal_number(heal_amount)
							
							# 3. 加入極短延遲 (0.05s)，確保追擊文字與基礎傷害文字在視覺上分離
							await get_tree().create_timer(0.05).timeout
							
							# 4. 觸發追擊 (套用攻擊者的貫穿效果)
							if attacker.character_data:
								var pur_dmg = attacker.character_data.get_effective_pursuit()
								if pur_dmg > 0 and is_instance_valid(target):
									target.apply_damage(pur_dmg, false, false, attacker, true)
							
							# 原有的連發感延遲 (扣除已等待的 0.05s)
							await get_tree().create_timer(0.05).timeout
					else:
						# 觸發閃避視覺效果
						if target.has_method("show_avoid_text"):
							target.show_avoid_text()
						await get_tree().create_timer(0.1).timeout
				
				if is_free_roam_mode: break
		else:
			# Fallback (should not happen if hits > 0)
			if is_instance_valid(target):
				target.apply_damage(final_damage)
			
		if is_free_roam_mode: break
			
		# 等待受傷動畫與恢復
		await get_tree().create_timer(0.6).timeout

		# --- 解鎖死亡 ---
		# 在所有視覺效果 (含受傷硬直) 結束後，才允許單位死亡
		if is_instance_valid(target) and target.has_method("end_combo_sequence"):
			target.end_combo_sequence()
			
		# 隱藏 Combo UI
		if is_instance_valid(target) and target.has_method("update_combo_display"):
			# 這裡可以選擇讓 UI 停留久一點，或直接隱藏
			# 目前選擇保留最後的數字，或歸零。通常受傷後 UI 會消失或重置。
			target.update_combo_display(0)
			# 確保隱藏
			if target.combo_indicator:
				target.combo_indicator.hide_combo()

extends Node
class_name EnemyMoveAIComponent

## 敵人移動 AI 組件
## 負責讓單位與玩家對齊並保持理想距離

@export var enabled: bool = false
@export var move_interval: float = 3.0
@export var ideal_distance: int = 3

@onready var parent_entity: GridEntity = get_parent()
var _timer: float = 0.0

func _ready() -> void:
	if not enabled:
		set_process(false)
		return
	if not parent_entity:
		print("[EnemyMoveAI] Error: Parent is not a GridEntity!")
		set_process(false)
		return
	
	print("[EnemyMoveAI] Initialized for ", parent_entity.name, " at ", parent_entity.grid_position)
	# 隨機化初始計時，避免同步移動
	_timer = randf_range(0, move_interval * 0.5)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= move_interval:
		_timer = 0.0
		# print("[EnemyMoveAI] %s: Ticking AI..." % parent_entity.name)
		await _execute_move_logic()

func _execute_move_logic() -> void:
	# print("[EnemyMoveAI] %s: Executing move logic..." % parent_entity.name)
	# 1. 尋找玩家 (優先尋找 GridEntity 類型的玩家)
	var player = get_tree().get_first_node_in_group("player") as GridEntity
	
	# 備案：如果群組找不到，從 BoardManager 找 Player 陣營
	if not player or not is_instance_valid(player):
		var player_faction = load("res://Resources/Factions/Faction_Player.tres")
		if player_faction and BoardManager:
			var players = BoardManager.get_entities_by_faction(player_faction)
			if not players.is_empty():
				player = players[0]
	
	if not player:
		print("[EnemyMoveAI] %s: Player NOT found in scene or BoardManager!" % parent_entity.name)
		return
	
	if not is_instance_valid(player):
		print("[EnemyMoveAI] %s: Found player but it is NOT valid!" % parent_entity.name)
		return

	var p_pos = player.grid_position
	var e_pos = parent_entity.grid_position
	
	# print("[EnemyMoveAI] %s: Found player %s at %s. My pos: %s" % [parent_entity.name, player.name, p_pos, e_pos])
	
	var dx = p_pos.x - e_pos.x
	var dy = p_pos.y - e_pos.y
	
	var move_dir = Vector2i.ZERO
	var _reason = ""
	
	# 1. 檢查是否已經對齊 (僅限 4 方向對齊：同一列或同一行)
	var is_aligned = (dx == 0 or dy == 0)
	
	if is_aligned:
		# 已經對齊，執行「保持距離」邏輯
		var dist = abs(dx) + abs(dy) # 曼哈頓距離
		var target_axis = Vector2i(sign(dx), sign(dy))
		
		# Ram-Only 邏輯：接近到距離 1 格，然後等待攻擊組件觸發撞擊
		if dist > 1:
			# 距離大於 1，靠近一格
			move_dir = target_axis
			_reason = "Aligned but too far (%d > 1), moving closer for ram." % dist
		else:
			# 距離等於 1 (或更小)，保持不動，讓 EnemyAttackComponent 發動撞擊
			_reason = "In ramming position (dist=%d), waiting for attack." % dist
			move_dir = Vector2i.ZERO
	else:
		# 2. 未對齊，選擇一條軸線來移動 (優先填補較大的差距)
		if abs(dx) >= abs(dy):
			move_dir = Vector2i(sign(dx), 0)
			_reason = "Not aligned, moving on X-axis to close gap."
		else:
			move_dir = Vector2i(0, sign(dy))
			_reason = "Not aligned, moving on Y-axis to close gap."
	
	# 3. 執行移動
	if move_dir != Vector2i.ZERO:
		var mover = parent_entity.get_node_or_null("GridMover") as GridMover
		if mover:
			var target_cell = e_pos + move_dir
			# AI 現在非常簡化：直接嘗試移動。Mover 會處理所有碰撞與預約邏輯。
			await mover.move_to(target_cell)
	
	# 4. 同步更新攻擊方向
	_update_attack_direction(p_pos, parent_entity.grid_position)

func _update_attack_direction(p_pos: Vector2i, e_pos: Vector2i) -> void:
	var attack_comp = parent_entity.get_node_or_null("EnemyAttackComponent") as EnemyAttackComponent
	if not attack_comp:
		return
		
	var dx = p_pos.x - e_pos.x
	var dy = p_pos.y - e_pos.y
	
	# 決定 4 方向中最接近玩家的一個
	var new_dir = Vector2i.ZERO
	
	# 優先判定軸向對齊
	if dx == 0 and dy != 0:
		new_dir = Vector2i(0, sign(dy))
	elif dy == 0 and dx != 0:
		new_dir = Vector2i(sign(dx), 0)
	else:
		# 如果完全沒對齊，選擇主導軸 (僅限 4 方向)
		if abs(dx) >= abs(dy):
			new_dir = Vector2i(sign(dx), 0)
		else:
			new_dir = Vector2i(0, sign(dy))
			
	if new_dir != Vector2i.ZERO:
		attack_comp.current_attack_dir = new_dir

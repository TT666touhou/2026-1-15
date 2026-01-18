extends CharacterBody2D
class_name GridEntity

# 預載入 FootprintData 以確保類型可被找到
const FootprintDataScript = preload("res://Footprints/FootprintData.gd")
const TraitServiceScript = preload("res://Scripts/Managers/TraitService.gd")

## 網格實體基類
## 所有可放置在網格上的實體的基類

var grid: Node  # Grid 類型（使用 Node 避免循環依賴）
var grid_position: Vector2i = Vector2i.ZERO  # 左上角位置
@export var footprint_data: Resource  # 實體大小（佔用的格子），類型為 FootprintData
@export var faction: FactionDefinition # 陣營定義
var is_selected: bool = false
var character_data: CharacterData
var movement_range_data: MovementRangeData # 運行時移動數據實例
var move_limit: int = -1 # 移動距離限制 (-1 為無限制)
var attack_range_depth: int = 1 # 攻擊範圍深度
var is_boss: bool = false # 是否為 BOSS (死亡後通關)
var combo_indicator: ComboIndicatorUI # Combo 顯示組件
var health_bar: Node = null

signal movement_data_changed # 通知 UI 更新移動範圍
signal entry_animation_finished # 進場動畫結束

func _ready() -> void:
	# Debug Camera: Add a camera if running this scene standalone
	if get_tree().current_scene == self:
		var cam = Camera2D.new()
		cam.zoom = Vector2(4, 4)
		add_child(cam)
		print("[GridEntity] Debug Camera Added for standalone scene execution")

	# 初始化 Combo Indicator
	var combo_ui_scene = preload("res://Scenes/UI/ComboIndicatorUI.tscn")
	if combo_ui_scene:
		combo_indicator = combo_ui_scene.instantiate()
		add_child(combo_indicator)
		# 調整位置到頭頂上方 (假設單位大小約 16x16)
		combo_indicator.position = Vector2(0, -12) 
		combo_indicator.z_index = 20 # 確保在最上層
	else:
		push_error("[GridEntity] Failed to preload ComboIndicatorUI.tscn")

	# 預設 Z Index (單位/敵人較高，陷阱/裝飾較低)
	z_index = 5
	
	# 註冊到 BoardManager
	if BoardManager:
		BoardManager.register_entity(self)
	
	# 加入群組以便 TurnManager 檢索
	add_to_group("grid_entities")

	grid = get_tree().get_first_node_in_group("grid")
	if grid == null or not grid.has_method("world_to_grid"):
		push_warning("[GridEntity] Grid not found")
		return
	
	# 如果沒有 footprint_data，報錯（所有實體都必須有）
	if footprint_data == null:
		push_error("[GridEntity] FootprintData is null for " + name + " (" + get_path().get_concatenated_names() + ")! Entity must have footprint_data assigned in Inspector or by CardProvider.")
		return
	
	if BoardManager:
		if not BoardManager.is_inside_tree():
			push_warning("[GridEntity] BoardManager is not in tree")
	# 否則從 global_position 計算 grid_position
	if grid_position == Vector2i(-1, -1) or grid_position == Vector2i.ZERO:
		var bounds = footprint_data.get_bounds()
		if bounds.size.x > 1 or bounds.size.y > 1:
			# 多格實體：從中心位置計算左上角
			var center_cell = grid.world_to_grid(global_position)
			grid_position = center_cell - Vector2i(bounds.position.x + bounds.size.x / 2, bounds.position.y + bounds.size.y / 2)
		else:
			# 單格實體：直接使用
			grid_position = grid.world_to_grid(global_position)
	
	# 註冊所有佔用的格子 (移至 set_grid_position 或由 MapLoader 觸發，避免預設 (0,0) 幽靈佔用)
	# _register_cells()
	_init_health_bar_from_footprint()
	_update_ui_positions()

func _update_ui_positions() -> void:
	if combo_indicator:
		# 由於 GridEntity 的 global_position 已經是單位的世界中心點 (由 grid_to_world_center_footprint 決定)
		# 所以本地座標的 X = 0 就已經是單位的 X 軸中心。
		combo_indicator.position = Vector2(0, -12)

func get_attack_results(at_cell: Vector2i) -> Dictionary:
	"""
	獲取指定位置的攻擊結果 (Hitbox Logic)
	返回: { TargetEntity: { "hits": int, "directions": Array[Vector2i] } }
	"""
	var results = {}
	if grid == null:
		# 嘗試獲取 grid (針對預覽模式)
		grid = get_tree().get_first_node_in_group("grid")
		
	if grid == null:
		return results
		
	# 如果沒有 movement_range_data，無法判斷攻擊方向
	if movement_range_data == null:
		return results
		
	var directions = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]
	
	for dir in directions:
		# 檢查該方向是否有箭頭 (非 BLOCKED)
		if movement_range_data.get_movement_type(dir) == MovementRangeData.MovementType.BLOCKED:
			continue
			
		# 1. 獲取該方向的 Hitbox 格子集合
		var hitbox_cells = _get_hitbox_cells(dir, at_cell)
		
		# 用於記錄此 Hitbox 中已經判定過的實體 (避免同一實體佔多格被重複計算)
		var hit_entities_in_this_box = {}
		
		# 2. 檢查 Hitbox 內的每個格子
		for cell in hitbox_cells:
			# 邊界檢查
			if not grid.has_method("is_in_bounds") or not grid.is_in_bounds(cell):
				continue
				
			var occupant = grid.get_occupant(cell) as GridEntity
			
			if occupant and occupant != self:
				# 陣營檢查 (Faction 資源不同即為敵對)
				if faction and occupant.faction and faction != occupant.faction:
					
					# 每個 Hitbox 內，每個實體只算一次
					if hit_entities_in_this_box.has(occupant):
						continue
					
					hit_entities_in_this_box[occupant] = true
					
					# 初始化結果結構
					if not results.has(occupant):
						results[occupant] = { "hits": 0, "directions": [] }
					
					# 累加 Hits 並記錄方向
					results[occupant]["hits"] += 1
					if not results[occupant]["directions"].has(dir):
						results[occupant]["directions"].append(dir)
				
	return results

func _get_hitbox_cells(direction: Vector2i, at_grid_pos: Vector2i) -> Array[Vector2i]:
	"""
	根據方向和攻擊深度計算 Hitbox 格子
	"""
	var cells: Array[Vector2i] = []
	if footprint_data == null:
		return cells
		
	# 判斷是否為斜向 (x和y都不為0)
	var is_diagonal = direction.x != 0 and direction.y != 0
	var depth = attack_range_depth
	
	if is_diagonal:
		# --- 斜向 (Diagonal) ---
		# 1. 找到對應的角落 (Corner)
		var bounds = footprint_data.get_bounds() # relative to (0,0)
		var corner_offset = Vector2i.ZERO
		
		# 根據方向決定使用哪個角落
		if direction.x < 0: # West
			corner_offset.x = bounds.position.x
		else: # East
			corner_offset.x = bounds.end.x - 1
			
		if direction.y < 0: # North
			corner_offset.y = bounds.position.y
		else: # South
			corner_offset.y = bounds.end.y - 1
			
		var corner_pos = at_grid_pos + corner_offset
		
		# 2. 從角落向外延伸 N x N
		for x in range(1, depth + 1):
			for y in range(1, depth + 1):
				var offset = Vector2i(x * direction.x, y * direction.y)
				cells.append(corner_pos + offset)
				
	else:
		# --- 直線 (Orthogonal) ---
		# 1. 找到對應的邊緣 (Edge)
		var bounds = footprint_data.get_bounds()
		var edge_cells_relative: Array[Vector2i] = []
		
		if direction.y == -1: # North
			for x in range(bounds.position.x, bounds.end.x):
				edge_cells_relative.append(Vector2i(x, bounds.position.y))
		elif direction.y == 1: # South
			for x in range(bounds.position.x, bounds.end.x):
				edge_cells_relative.append(Vector2i(x, bounds.end.y - 1))
		elif direction.x == -1: # West
			for y in range(bounds.position.y, bounds.end.y):
				edge_cells_relative.append(Vector2i(bounds.position.x, y))
		elif direction.x == 1: # East
			for y in range(bounds.position.y, bounds.end.y):
				edge_cells_relative.append(Vector2i(bounds.end.x - 1, y))
				
		# 2. 從邊緣向外延伸 N 層
		for rel_pos in edge_cells_relative:
			var start_pos = at_grid_pos + rel_pos
			for d in range(1, depth + 1):
				cells.append(start_pos + (direction * d))
				
	return cells

func execute_attack() -> void:
	"""[已棄用] 由 TurnManager 的序列化攻擊取代"""
	pass

func play_attack_animation_towards(direction: Vector2i) -> void:
	"""播放攻擊動畫 (不造成傷害)"""
	var visuals = get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_attack_animation"):
		visuals.play_attack_animation(direction)

func apply_damage(amount: int, ignore_barrier: bool = false, ignore_shield: bool = false, attacker: GridEntity = null, is_pursuit: bool = false) -> int:
	"""直接造成傷害 (不處理動畫，動畫由 take_damage 觸發)"""
	var attacker_data = attacker.character_data if attacker != null else null
	return take_damage(amount, ignore_barrier, ignore_shield, attacker_data, is_pursuit)

func show_damage_number(amount: int) -> void:
	"""顯示受傷浮動文字"""
	var scene = load("res://Scenes/UI/FloatingText.tscn")
	if scene:
		var text_instance = scene.instantiate()
		add_child(text_instance)
		# 調整位置到頭頂上方
		text_instance.position = Vector2(0, -16)
		text_instance.popup_damage(amount)

func show_pursuit_number(amount: int) -> void:
	"""顯示追擊浮動文字"""
	var scene = load("res://Scenes/UI/FloatingText.tscn")
	if scene:
		var instance = scene.instantiate()
		add_child(instance)
		instance.position = Vector2(0, -16)
		if instance.has_method("popup_pursuit"):
			instance.popup_pursuit(amount)
		else:
			instance.popup_damage(amount)

func show_heal_number(amount: int) -> void:
	"""顯示治療浮動文字"""
	var scene = load("res://Scenes/UI/FloatingText.tscn")
	if scene:
		var instance = scene.instantiate()
		add_child(instance)
		# 調整位置到頭頂上方
		instance.position = Vector2(0, -16)
		# 傳入負值，FloatingText 會自動切換為治療樣式並加上 "+"
		instance.popup_damage(-amount)

func show_avoid_text() -> void:
	"""顯示閃避浮動文字"""
	var scene = load("res://Scenes/UI/FloatingText.tscn")
	if scene:
		var instance = scene.instantiate()
		add_child(instance)
		instance.position = Vector2(0, -16)
		# 假設 FloatingText 有支援文字彈出
		if instance.has_method("popup_text"):
			instance.popup_text("AVOID", Color.PURPLE)
		else:
			# 回退：使用受傷樣式但傳入 0 (如果支援)
			instance.popup_damage(0)

func show_resisted_text() -> void:
	"""顯示抵抗浮動文字"""
	var scene = load("res://Scenes/UI/FloatingText.tscn")
	if scene:
		var instance = scene.instantiate()
		add_child(instance)
		instance.position = Vector2(0, -16)
		if instance.has_method("popup_text"):
			instance.popup_text("RESISTED", Color.BLUE_VIOLET)
		else:
			instance.popup_damage(0)

func show_parry_text() -> void:
	"""顯示格擋浮動文字"""
	var scene = load("res://Scenes/UI/FloatingText.tscn")
	if scene:
		var instance = scene.instantiate()
		add_child(instance)
		instance.position = Vector2(0, -16)
		if instance.has_method("popup_parry"):
			instance.popup_parry()
		else:
			instance.popup_text("PARRY", Color.PURPLE)

func show_barrier_text() -> void:
	"""顯示防護罩抵擋浮動文字"""
	var scene = load("res://Scenes/UI/FloatingText.tscn")
	if scene:
		var instance = scene.instantiate()
		add_child(instance)
		instance.position = Vector2(0, -16)
		if instance.has_method("popup_barrier"):
			instance.popup_barrier()
		else:
			instance.popup_text("防護罩", Color.GOLD)

var current_attack_text: FloatingText = null

func show_attack_number(amount: int) -> void:
	"""顯示攻擊預告浮動文字"""
	# 清除舊的 (如果存在)
	dismiss_attack_number()
	
	var scene = load("res://Scenes/UI/FloatingText.tscn")
	if scene:
		var text_instance = scene.instantiate()
		add_child(text_instance)
		# 調整位置到頭頂上方
		text_instance.position = Vector2(0, -16)
		text_instance.popup_attack(amount)
		current_attack_text = text_instance

func dismiss_attack_number() -> void:
	"""隱藏攻擊預告文字"""
	if is_instance_valid(current_attack_text):
		current_attack_text.dismiss()
	current_attack_text = null

func update_combo_display(count: int) -> void:
	"""更新 Combo 顯示"""
	if combo_indicator:
		combo_indicator.show_combo(count)

func set_movement_data(data: MovementRangeData) -> void:
	"""設置移動數據（通常由 CardProvider 調用）"""
	movement_range_data = data
	movement_data_changed.emit()

func modify_movement(direction: Vector2i, type: int) -> void:
	"""動態修改移動規則（供 Buff/Debuff 使用）"""
	if movement_range_data:
		movement_range_data.set_movement_type(direction, type)
		movement_data_changed.emit()

func _init_health_bar_from_footprint() -> void:
	if health_bar == null:
		health_bar = get_node_or_null("StatBar")
	if health_bar == null:
		health_bar = get_node_or_null("HealthBar")
	
	# --- 自動為敵方配置血條，並隱藏我方血條 ---
	if faction:
		if faction.is_controllable:
			# 我方單位：隱藏血條
			if health_bar:
				health_bar.visible = false
		else:
			# 敵方單位：確保有血條，若無則自動添加
			if health_bar == null:
				var bar_scene = load("res://Scenes/UI/StatBar.tscn")
				if bar_scene:
					health_bar = bar_scene.instantiate()
					# 使用 call_deferred 避免 "Parent node is busy" 錯誤
					call_deferred("add_child", health_bar)
					# 等待準備好後執行配置
					health_bar.ready.connect(func():
						move_child(health_bar, 0)
						_configure_health_bar()
					)
					print("[GridEntity] Automatically added StatBar to enemy: ", name)
			
			if health_bar:
				health_bar.visible = true
	
	if health_bar == null:
		return
	
	_configure_health_bar()

func _configure_health_bar() -> void:
	if health_bar == null or not health_bar.is_inside_tree():
		return
		
	# 取得格子尺寸，若 grid 未初始化則使用預設 16x16
	var cell_size: Vector2i = Vector2i(16, 16)
	if grid and ("cell_size" in grid):
		cell_size = grid.cell_size
	
	var width_cells := 1
	var height_cells := 1
	if footprint_data and footprint_data.has_method("get_bounds"):
		var bounds = footprint_data.get_bounds()
		width_cells = max(1, bounds.size.x)
		height_cells = max(1, bounds.size.y)
	
	if health_bar.has_method("configure_from_grid"):
		health_bar.configure_from_grid(cell_size, width_cells, height_cells)
	
	if character_data:
		var eff = character_data.get_effective_max_health()
		if health_bar.has_method("set_health"):
			health_bar.set_health(character_data.current_health, eff)
		elif health_bar.has_method("update_bar"):
			health_bar.update_bar(character_data.current_health, eff)

func setup_character(data: CharacterData) -> void:
	character_data = data
	
	if data.unit_def:
		if "attack_depth" in data.unit_def:
			attack_range_depth = data.unit_def.attack_depth
			
	if not character_data.health_changed.is_connected(_on_health_changed):
		character_data.health_changed.connect(_on_health_changed)
	if not character_data.died.is_connected(_on_died):
		character_data.died.connect(_on_died)
	if not character_data.reflect_triggered.is_connected(_on_reflect_triggered):
		character_data.reflect_triggered.connect(_on_reflect_triggered)
	if not character_data.parry_triggered.is_connected(_on_parry_triggered):
		character_data.parry_triggered.connect(_on_parry_triggered)
	if not character_data.barrier_triggered.is_connected(_on_barrier_triggered):
		character_data.barrier_triggered.connect(_on_barrier_triggered)
	
	var status_mgr = get_node_or_null("StatusManager")
	if status_mgr:
		character_data.set_status_manager(status_mgr)
		if not status_mgr.status_applied.is_connected(_on_status_changed):
			status_mgr.status_applied.connect(_on_status_changed.unbind(2))
		if not status_mgr.status_removed.is_connected(_on_status_changed):
			status_mgr.status_removed.connect(_on_status_changed.unbind(1))
		if not status_mgr.status_updated.is_connected(_on_status_changed):
			status_mgr.status_updated.connect(_on_status_changed.unbind(2))
			
		if not data.saved_status_data.is_empty():
			status_mgr.load_save_data(data.saved_status_data)
	
	# 確保在設置角色後重新檢查血條顯示狀態
	_init_health_bar_from_footprint()
	_on_health_changed(data.current_health, data.get_effective_max_health())

func apply_overrides(overrides: Dictionary) -> void:
	"""應用來自編輯器的數值覆蓋"""
	if overrides.is_empty():
		return
		
	if overrides.has("move_limit"):
		move_limit = int(overrides["move_limit"])
		
	if overrides.has("movement") and movement_range_data:
		var move_dict = overrides["movement"]
		var new_data = movement_range_data.duplicate()
		for key in move_dict:
			new_data.set(key, int(move_dict[key]))
		movement_range_data = new_data
		movement_data_changed.emit()
	elif overrides.has("move_limit"):
		movement_data_changed.emit()
		
	if character_data:
		if overrides.has("max_health"):
			character_data.max_health = int(overrides["max_health"])
			character_data.current_health = character_data.max_health # 重置血量
			
		if overrides.has("attack_damage"):
			character_data.attack_damage = int(overrides["attack_damage"])

		# 新增：支援護盾與防護罩的覆蓋
		if overrides.has("base_shield"):
			character_data.shield = int(overrides["base_shield"])
			print("[GridEntity] Override applied: shield = ", character_data.shield)
		if overrides.has("base_barriers"):
			character_data.barriers = int(overrides["base_barriers"])
			print("[GridEntity] Override applied: barriers = ", character_data.barriers)
		if overrides.has("base_dr"):
			character_data.base_dr = float(overrides["base_dr"])
			print("[GridEntity] Override applied: base_dr = ", character_data.base_dr)
		
		# Boss 標記
		if overrides.has("is_boss"):
			is_boss = bool(overrides["is_boss"])
			print("[GridEntity] Override applied: is_boss = ", is_boss)
		
		character_data.recalculate_stats()
		# 強制發送信號更新 UI
		character_data.stats_changed.emit()

func save_runtime_data() -> void:
	"""保存執行時數據到 CharacterData (過場前調用)"""
	if character_data and has_node("StatusManager"):
		var sm = get_node("StatusManager")
		if sm.has_method("get_save_data"):
			character_data.saved_status_data = sm.get_save_data()
			print("[GridEntity] Saved runtime status data for ", name)

func prepare_for_entry() -> void:
	"""準備進場（隱藏實體）"""
	var visuals = get_node_or_null("UnitVisuals")
	if visuals:
		if visuals.sprite:
			visuals.sprite.modulate.a = 0.0

func play_entry_animation(delay: float = 0.0) -> void:
	var visuals = get_node_or_null("UnitVisuals")
	if not visuals: 
		# 如果沒有視覺組件，確保 Sprite 直接顯示並發送信號
		var sprite = get_node_or_null("Sprite2D")
		if sprite:
			sprite.modulate.a = 1.0
		entry_animation_finished.emit.call_deferred()
		return
	
	# 嘗試從多個來源獲取動畫類型 (UnitCard, PropCard, TrapCard)
	var anim_type = 0 # 預設 DROP
	var source_name = "DEFAULT_FALLBACK"
	
	if character_data and character_data.unit_def:
		anim_type = character_data.unit_def.spawn_animation
		source_name = "CharacterData.unit_def"
	else:
		# 如果沒有角色資料，嘗試從 CardProvider 獲取
		var card_provider = get_node_or_null("CardProvider")
		if card_provider:
			var card = card_provider.get("card")
			if card and "spawn_animation" in card:
				anim_type = card.spawn_animation
				source_name = "CardProvider.card"
			else:
				source_name = "CardProvider (NO_CARD_OR_NO_ANIM_FIELD)"
		else:
			source_name = "NO_CARD_PROVIDER"
	
	print("[GridEntity] play_entry_animation for ", name, " | anim_type: ", anim_type, " | Source: ", source_name)
	
	if delay > 0:
		await get_tree().create_timer(delay).timeout
		
	if visuals.has_signal("spawn_animation_finished"):
		if not visuals.spawn_animation_finished.is_connected(_on_entry_animation_finished):
			visuals.spawn_animation_finished.connect(_on_entry_animation_finished, CONNECT_ONE_SHOT)
		
	if visuals.has_method("play_spawn_animation"):
		visuals.play_spawn_animation(anim_type)
	else:
		entry_animation_finished.emit.call_deferred()

func _on_entry_animation_finished() -> void:
	entry_animation_finished.emit()

func _on_status_changed() -> void:
	if character_data:
		character_data.recalculate_stats()

func set_editor_highlight(enabled: bool) -> void:
	var sprite = get_node_or_null("Sprite2D")
	if enabled:
		# 選取時：變亮（Self Modulate 不會影響子節點）並提到最上層
		if sprite:
			sprite.self_modulate = Color(2.0, 2.0, 2.0, 1.0)
		z_index = 100
	else:
		# 取消選取：恢復原狀
		if sprite:
			sprite.self_modulate = Color.WHITE
		z_index = 5

func take_damage(amount: int, ignore_barrier: bool = false, ignore_shield: bool = false, attacker: CharacterData = null, is_pursuit: bool = false) -> int:
	var status_mgr = get_node_or_null("StatusManager")
	var final_amount = float(amount)
	
	if status_mgr and status_mgr.has_method("get_damage_received_multiplier"):
		var multiplier = status_mgr.get_damage_received_multiplier()
		final_amount *= multiplier
	
	var damage_int = int(final_amount)

	if character_data:
		# 只有在「沒被格擋或防護罩抵擋」的情況下才執行後續視覺邏輯
		var actual_damage = character_data.take_damage(damage_int, ignore_barrier, ignore_shield, attacker)
		if actual_damage != -1:
			_apply_damage_visuals(actual_damage, is_pursuit)
		return actual_damage
		
	# 處理沒有 character_data 的對象 (如建築物)
	_apply_damage_visuals(damage_int, is_pursuit)
	
	var building_stat = get_node_or_null("BuildingStat")
	if building_stat:
		if building_stat.has_method("take_damage"):
			building_stat.take_damage(damage_int)
	
	return damage_int

func _apply_damage_visuals(damage_int: int, is_pursuit: bool) -> void:
	"""套用受傷相關的視覺與 UI 更新"""
	if health_bar and character_data:
		var eff = character_data.get_effective_max_health()
		# 使用目前 CharacterData 中的血量 (因為剛才已經由 take_damage 更新過)
		var current_hp = character_data.current_health
		if health_bar.has_method("on_damage"):
			health_bar.on_damage(damage_int, current_hp, eff)
		elif health_bar.has_method("update_bar"):
			health_bar.update_bar(current_hp, eff)

	if is_pursuit:
		show_pursuit_number(damage_int)
	else:
		show_damage_number(damage_int)
	
	var visuals = get_node_or_null("UnitVisuals")
	if visuals:
		if visuals.has_method("play_damage_animation"):
			visuals.play_damage_animation()
			
	if TraitServiceScript:
		TraitServiceScript.apply_trigger(TraitEffect.TriggerType.ON_DAMAGED, {
			"damaged_entity": self,
			"amount": damage_int
		})
		return

func heal(amount: int) -> void:
	if character_data:
		character_data.heal(amount)
		show_heal_number(amount)

func _on_health_changed(_current: int, _max_h: int) -> void:
	if health_bar:
		if health_bar.has_method("set_health"):
			health_bar.set_health(_current, _max_h)
		elif health_bar.has_method("update_bar"):
			health_bar.update_bar(_current, _max_h)

func _on_died() -> void:
	_handle_death()

func _on_reflect_triggered(attacker_data: CharacterData, amount: int, reflector_data: CharacterData) -> void:
	# 透過 attacker_data 的 status_manager_ref 找回攻擊者的 GridEntity 實體
	if attacker_data and attacker_data.status_manager_ref:
		var attacker_entity = attacker_data.status_manager_ref.get_parent() as GridEntity
		if attacker_entity and attacker_entity.has_method("apply_damage"):
			# 反射傷害無視防護罩與護盾 (ignore_barrier=true, ignore_shield=true)
			# 傳入反射者資料 (reflector_data) 以套用其貫穿效果
			attacker_entity.apply_damage(amount, true, true, reflector_data.status_manager_ref.get_parent() if reflector_data.status_manager_ref != null else null)

func _on_parry_triggered() -> void:
	show_parry_text()

func _on_barrier_triggered() -> void:
	show_barrier_text()

var _is_combo_locked: bool = false
var _death_pending: bool = false

func start_combo_sequence() -> void:
	_is_combo_locked = true
	_death_pending = false

func end_combo_sequence() -> void:
	_is_combo_locked = false
	if _death_pending:
		_handle_death()

func _handle_death() -> void:
	if _is_combo_locked:
		_death_pending = true
		return

	var scene = get_tree().current_scene
	if scene:
		var layer = scene.get_node_or_null("PathVisualizationLayer") as Node2D
		if layer:
			var node = layer.get_node_or_null("PathVisualization_%d" % get_instance_id())
			if node:
				node.queue_free()

	var bt_player = get_node_or_null("BTPlayer")
	if bt_player and bt_player.has_method("stop"):
		bt_player.stop()

	var search_area = get_node_or_null("SearchArea") as Area2D
	var attack_area = get_node_or_null("AttackArea") as Area2D
	if search_area: search_area.monitoring = false
	if attack_area: attack_area.monitoring = false

	for child in get_children():
		if child is FloatingText:
			child.reparent(get_tree().current_scene, true)

	await play_death_animation()

	if TraitServiceScript:
		TraitServiceScript.apply_trigger(TraitEffect.TriggerType.ON_KILL, {
			"killed_entity": self
		})
	call_deferred("queue_free")

func play_death_animation() -> void:
	var visuals = get_node_or_null("UnitVisuals")
	if not is_instance_valid(visuals) or not "sprite" in visuals or not is_instance_valid(visuals.sprite):
		await get_tree().process_frame
		return
		
	var tween = create_tween()
	if not tween:
		await get_tree().process_frame
		return

	tween.set_parallel(true)
	var target = visuals.sprite
	
	var tweener1 = tween.tween_property(target, "scale", Vector2(1.2, 1.2), 0.1)
	if tweener1:
		tweener1.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	
	tween.chain().set_parallel(true)
	var tweener2 = tween.tween_property(target, "scale", Vector2(0.0, 0.0), 0.3)
	if tweener2:
		tweener2.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	
	var tweener3 = tween.tween_property(target, "modulate:a", 0.0, 0.3)
	if tweener3:
		tweener3.set_ease(Tween.EASE_IN)
	
	await tween.finished

func set_grid_position(cell: Vector2i) -> void:
	if grid == null or footprint_data == null:
		return
	if not grid.has_method("clear_cell") or not grid.has_method("grid_to_world_center_footprint"):
		return
		
	# 無論座標是否相同，只要調用此函式就確保先清除舊佔用 (特別是針對初次設定從 (0,0) 移走的情況)
	_unregister_cells()
	
	grid_position = cell
	
	# 重新註冊新位置
	_register_cells()
	
	global_position = grid.grid_to_world_center_footprint(cell, footprint_data)

	var dm = get_node_or_null("/root/DungeonManager")
	if dm and dm.has_method("check_gate_trigger"):
		dm.check_gate_trigger(self, cell)

func get_grid_position() -> Vector2i:
	return grid_position

func get_footprint_size() -> Vector2i:
	if footprint_data != null:
		return footprint_data.get_size()
	return Vector2i(1, 1)

func get_occupied_cells() -> Array[Vector2i]:
	if footprint_data == null:
		return [grid_position]
	var result: Array[Vector2i] = []
	for offset in footprint_data.occupied_cells:
		result.append(grid_position + offset)
	return result

func get_reachable_cells() -> Array[Vector2i]:
	var reachable: Array[Vector2i] = []
	var start = grid_position
	if grid == null or movement_range_data == null:
		return reachable
	
	var directions = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]
	
	for dir in directions:
		if not movement_range_data.can_move_in_direction(dir, 1):
			continue
			
		var max_dist = movement_range_data.get_max_distance(dir)
		var dist = 0
		var current = start
		
		while true:
			var next_cell = current + dir
			dist += 1
			
			var is_blocked = false
			var cells_to_check = [next_cell]
			if footprint_data != null and grid.has_method("get_cells_in_footprint"):
				cells_to_check = grid.get_cells_in_footprint(next_cell, footprint_data)
			
			for check_cell in cells_to_check:
				if not grid.is_in_bounds(check_cell):
					is_blocked = true
					break
				if grid.is_cell_occupied(check_cell):
					var occupant = grid.get_occupant(check_cell)
					if occupant != self:
						is_blocked = true
						break
			
			if is_blocked:
				break
			if max_dist != -1 and dist > max_dist:
				break
			if move_limit != -1 and dist > move_limit:
				break
			
			reachable.append(next_cell)
				
			current = next_cell
			if max_dist != -1 and dist >= max_dist:
				break
		
	return reachable

func get_leading_edge_cells(target_cell: Vector2i, from_cell: Vector2i) -> Array[Vector2i]:
	if footprint_data == null or not grid:
		return [target_cell]
	var old_cells = grid.get_cells_in_footprint(from_cell, footprint_data)
	var new_cells = grid.get_cells_in_footprint(target_cell, footprint_data)
	var leading_edge: Array[Vector2i] = []
	for cell in new_cells:
		if not cell in old_cells:
			leading_edge.append(cell)
	if leading_edge.is_empty():
		return new_cells
	return leading_edge

func on_selected() -> void:
	is_selected = true

func on_deselected() -> void:
	is_selected = false

func _register_cells() -> void:
	if grid == null or footprint_data == null:
		return
	if not grid.has_method("get_cells_in_footprint"):
		return
	var cells = grid.get_cells_in_footprint(grid_position, footprint_data)
	for cell in cells:
		if grid.has_method("set_cell_occupied"):
			grid.set_cell_occupied(cell, self)

func _unregister_cells() -> void:
	if grid == null or footprint_data == null:
		return
	if grid.has_method("clear_cells_footprint"):
		grid.clear_cells_footprint(grid_position, footprint_data)
	elif grid.has_method("get_cells_in_footprint"):
		var cells = grid.get_cells_in_footprint(grid_position, footprint_data)
		for cell in cells:
			if grid.has_method("clear_cell"):
				grid.clear_cell(cell)

func _exit_tree() -> void:
	_unregister_cells()
	if BoardManager:
		BoardManager.unregister_entity(self)

func equip_item(item_data: Resource) -> bool:
	if not character_data: return false
	if not faction or not faction.is_controllable: return false
	
	character_data.equip(item_data)
	# 通知 UI 更新
	character_data.stats_changed.emit()
	return true

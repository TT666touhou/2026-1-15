extends Node

# 管理地圖載入與初始化
# 負責處理 RoomTemplate 並將其轉化為遊戲場景中的實體與地塊

@export_group("Layers")
@export var ground_layer_path: NodePath = "Ground"
@export var resources_layer_path: NodePath = "ResourcesLayer"

@export_group("Map Settings")
@export var map_width: int = 12
@export var map_height: int = 8

@export_group("Tile Assets")
## 基礎地塊 (4,5) 的視覺預覽 (AtlasTexture)
@export var base_tile_visual: AtlasTexture
## 隨機變體地塊列表
@export var variations: Array[TileVariation]

# 內部解析後的數據
var _base_source_id: int = -1
var _base_coords: Vector2i = Vector2i(4, 6) # 預設值
var _resolved_variations: Array[Dictionary] = [] # {source_id, coords, chance}

const FACTION_PLAYER = preload("res://Resources/Factions/Faction_Player.tres")
const FACTION_ENEMY = preload("res://Resources/Factions/Faction_Enemy.tres")
# const FACTION_NEUTRAL = preload("res://Resources/Factions/Faction_Neutral.tres")

# 額外地塊 (Gate Grids) 配置 - [暫時停用]
# var extra_cell_coords: Array[Vector2i] = [
# 	Vector2i(7, 1), # 上
# 	Vector2i(7, 3), # 中
# 	Vector2i(7, 5)  # 下
# ]
var _captured_tile_data: Dictionary = {} # { index (int): { source_id, atlas_coords, alternative_tile } }

func _ready() -> void:
	add_to_group("map_loader") # Register for DungeonManager
	
	var ground_layer = get_node_or_null(ground_layer_path)
	if ground_layer is TileMapLayer:
		_resolve_visual_tiles(ground_layer) # 解析視覺化地塊數據
		_initialize_ground(ground_layer)
		# _capture_and_hide_gate_grids(ground_layer) # [暫時停用舊有的門扉捕捉邏輯]
	elif ground_layer:
		push_error("[MapLoader] Ground layer found but is not a TileMapLayer!")
	
	var resources_layer = get_node_or_null(resources_layer_path)
	if resources_layer is TileMapLayer:
		_initialize_resources(resources_layer)
	elif resources_layer:
		print("[MapLoader] ResourcesLayer found but is not a TileMapLayer, skipping _initialize_resources")
		
	# 初始化回合系統
	if TurnManager:
		TurnManager.start_combat([FACTION_PLAYER, FACTION_ENEMY])

func _initialize_ground(_layer: TileMapLayer) -> void:
	# 初始啟動時，先清除可能殘留在右側的編輯器地塊
	clear_region(Rect2i(map_width, 0, 10, map_height))
	
	# 初始啟動時，也隨機填充一次主區域
	print("[MapLoader] Initializing ground with random tiles...")
	fill_random_ground(Rect2i(0, 0, map_width, map_height))

func _capture_and_hide_gate_grids(_layer: TileMapLayer) -> void:
	# [暫時停用]
	pass
	# for i in range(extra_cell_coords.size()):
	# 	var cell = extra_cell_coords[i]
	# 	var source_id = layer.get_cell_source_id(cell)
	# 	var atlas_coords = layer.get_cell_atlas_coords(cell)
	# 	var alternative_tile = layer.get_cell_alternative_tile(cell)
	# 	
	# 	_captured_tile_data[i] = {
	# 		"source_id": source_id,
	# 		"atlas_coords": atlas_coords,
	# 		"alternative_tile": alternative_tile
	# 	}
	# 	
	# 	# 隱藏它
	# 	layer.erase_cell(cell)

func get_gate_tile_data(index: int) -> Dictionary:
	return _captured_tile_data.get(index, {})

func _initialize_resources(_layer: TileMapLayer) -> void:
	# 這裡可以根據需要初始化資源層
	pass

# --- Dungeon Manager API ---

func clear_current_map(skip_ground_init: bool = false) -> void:
	print("[MapLoader] Clearing current map... skip_ground_init: ", skip_ground_init)
	var entities = get_tree().get_nodes_in_group("grid_entities")
	for entity in entities:
		if is_instance_valid(entity):
			entity.queue_free()
			
	# 同步清除 BoardManager 記錄 (如果有的話)
	if BoardManager:
		BoardManager.clear_all()
	
	# 始終清空所有可見地塊 (確保轉場起始是乾淨的)
	clear_region(Rect2i(-50, -50, 100, 100))
	
	# 如果不跳過初始化，則填充預設地圖
	if not skip_ground_init:
		var layer = get_node_or_null(ground_layer_path) as TileMapLayer
		if layer:
			_initialize_ground(layer)
	else:
		# 即使跳過填充，也要解析視覺地塊數據，確保後續 generate_column 正常
		var layer = get_node_or_null(ground_layer_path) as TileMapLayer
		if layer:
			_resolve_visual_tiles(layer)
			print("[MapLoader] Visual tiles resolved (ground cleared)")

func instantiate_room(template: RoomTemplate) -> Array[GridEntity]:
	print("[MapLoader] Instantiating room: ", template.room_name)
	
	# 更新地圖尺寸以符合模板
	if template.width > 0: map_width = template.width
	if template.height > 0: map_height = template.height
	
	var grid_node = get_tree().get_first_node_in_group("grid")
	if grid_node:
		grid_node.map_width = map_width
		grid_node.map_height = map_height
		if grid_node.has_signal("size_changed"):
			grid_node.size_changed.emit()
		
	print("[MapLoader] Map dimensions updated to: ", map_width, "x", map_height)
	
	var spawned_enemies: Array[GridEntity] = []
	
	for entity_data in template.entities:
		var grid_pos = entity_data.pos
		var card_path = entity_data.get("card_path", "")
		var scene_path = entity_data.get("scene_path", "")
		var overrides = entity_data.get("overrides", {})
		
		var card = null
		if card_path != "" and FileAccess.file_exists(card_path):
			card = load(card_path)
			
		var scene_to_spawn = null
		if scene_path != "" and FileAccess.file_exists(scene_path):
			scene_to_spawn = load(scene_path)
		elif card:
			if "unit_scene" in card: scene_to_spawn = card.get("unit_scene")
			elif "building_scene" in card: scene_to_spawn = card.get("building_scene")
			elif "prop_scene" in card: scene_to_spawn = card.get("prop_scene")
			elif "trap_scene" in card: scene_to_spawn = card.get("trap_scene")
			
		if scene_to_spawn is PackedScene:
			# 統一使用新的 spawn_entity API
			var entity = spawn_entity(scene_to_spawn, card, grid_pos, "enemy", overrides)
			if entity:
				spawned_enemies.append(entity)
				
	return spawned_enemies

## 統一實體生成 API
## is_dynamic: 如果為 true，則立即顯示實體（用於戰鬥中分裂/召喚）；否則隱藏等待進場動畫
func spawn_entity(scene: PackedScene, card: Resource, grid_pos: Vector2i, faction_group: String, overrides: Dictionary = {}, is_dynamic: bool = false) -> GridEntity:
	if not scene: return null
	
	# 1. 實例化
	var instance = scene.instantiate()
	if not instance is GridEntity:
		# 支援非 GridEntity 的基礎 Node (如單純的裝備)
		add_unit_to_scene(instance)
		if instance.has_method("set_grid_position"):
			instance.set_grid_position(grid_pos)
		return null
		
	var unit = instance as GridEntity
	
	# 2. 準備數據
	var char_data = null
	if card and card is UnitCard:
		var CharacterDataScript = load("res://Scripts/Entities/CharacterData.gd")
		char_data = CharacterDataScript.create(card)
	
	# 3. 統一初始化 (物理、群組、UI 偵測)
	var is_player_unit = (faction_group == "player")
	unit.initialize_runtime(char_data, faction_group, is_player_unit)
	
	# 4. 應用數值覆蓋
	if not overrides.is_empty() and unit.has_method("apply_overrides"):
		unit.apply_overrides(overrides)
		
	# 5. 加入場景樹 (UnitsLayer)
	add_unit_to_scene(unit)
	
	# 6. 網格定位與系統註冊
	unit.set_grid_position(grid_pos)
	
	if BoardManager:
		BoardManager.register_entity(unit)
		
	# 7. 視覺準備
	if is_dynamic:
		# 動態生成（如分裂）不隱藏，確保外觀可見
		unit.visible = true
		var sprite = unit.get_node_or_null("Sprite2D")
		if sprite: sprite.modulate.a = 1.0
		var visuals = unit.get_node_or_null("UnitVisuals")
		if visuals and "sprite" in visuals and visuals.sprite:
			visuals.sprite.modulate.a = 1.0
		
		# 核心修正：動態生成的單位需要立即解鎖物理，以便接收初始衝力
		if unit.has_method("unlock_physics"):
			unit.unlock_physics()
	elif unit.has_method("prepare_for_entry"):
		# 初始生成則隱藏，等待進場動畫
		unit.prepare_for_entry()
		
	print("[MapLoader] Successfully spawned entity: ", unit.name, " at grid ", grid_pos, " (Dynamic: ", is_dynamic, ")")
	return unit

## 統一投射物生成 API
## params: { "speed": float, "damage": int, "texture": Texture2D, "is_piercing": bool }
func spawn_projectile(scene: PackedScene, source: GridEntity, target_dir: Vector2, params: Dictionary = {}) -> Node:
	if not scene or not source: return null
	
	# 1. 實例化
	var projectile = scene.instantiate()
	
	# 2. 獲取基礎參數
	var spd = params.get("speed", 300.0)
	var dmg = params.get("damage", 1)
	if source.character_data and not params.has("damage"):
		dmg = source.character_data.get_effective_attack()
	
	# 3. 穿透屬性判定
	var is_piercing = params.get("is_piercing", false)
	if params.has("texture") and params["texture"].resource_path.contains("magicorb"):
		is_piercing = true
	
	if "is_piercing" in projectile:
		projectile.is_piercing = is_piercing
	
	# 4. 統一初始化
	if projectile.has_method("setup"):
		projectile.setup(source.global_position, target_dir, dmg, spd, source)
	
	# 5. 特殊外觀設置
	if params.has("texture") and projectile.has_method("set_texture"):
		projectile.set_texture(params["texture"])
	
	# 6. 加入場景樹
	add_child(projectile)
	
	# 6. 告知 TurnManager 追蹤此投射物，確保回合系統監控
	if TurnManager and TurnManager.has_method("on_unit_launched"):
		TurnManager.on_unit_launched(projectile, target_dir.normalized() * spd)
		
	# 7. 確保加入群組
	if not projectile.is_in_group("projectiles"):
		projectile.add_to_group("projectiles")
		
	print("[MapLoader] Projectile spawned: ", projectile.name, " from ", source.name, " Dir: ", target_dir)
	return projectile

func add_unit_to_scene(unit: Node) -> void:
	print("[MapLoader] add_unit_to_scene called for: ", unit.name)
	var units_layer = get_node_or_null("Entities/UnitsLayer")
	if units_layer:
		print("[MapLoader] Adding unit to UnitsLayer: ", units_layer.get_path())
		units_layer.add_child(unit)
		var parent_node = unit.get_parent()
		var parent_name = str(parent_node.name) if parent_node else "NULL"
		print("[MapLoader] Unit added, parent: ", parent_name, " | global_pos: ", unit.global_position)
	else:
		# Fallback: add as child of MapLoader if layer is missing
		print("[MapLoader] WARNING: UnitsLayer not found, adding unit as direct child of MapLoader")
		add_child(unit)
		push_warning("[MapLoader] UnitsLayer not found, adding unit as direct child")

## 根據單位位置生成隨機一列地塊 (可選動畫)
func generate_column(grid_x: int, animated: bool = false) -> void:
	var layers = []
	var ground = get_node_or_null(ground_layer_path)
	if ground: layers.append(ground)
	
	if get_parent():
		var bg = get_parent().get_node_or_null("BackgroundGround")
		if bg: layers.append(bg)
	
	for layer in layers:
		if not layer is TileMapLayer: continue
		for y in range(map_height):
			var cell = Vector2i(grid_x, y)
			var chosen_tile = _base_coords
			var chosen_source = _base_source_id
			
			var roll = randf()
			var cumulative_chance = 0.0
			for var_data in _resolved_variations:
				cumulative_chance += var_data.chance
				if roll < cumulative_chance:
					chosen_tile = var_data.coords
					chosen_source = var_data.source_id
					break
			
			if not animated:
				layer.set_cell(cell, chosen_source, chosen_tile)
			else:
				_animate_tile_appear(layer, cell, chosen_source, chosen_tile)

## 擦除指定 X 軸格位的所有地塊 (可選動畫)
func erase_column(grid_x: int, animated: bool = false) -> void:
	var layers = []
	var ground = get_node_or_null(ground_layer_path)
	if ground: layers.append(ground)
	
	if get_parent():
		var bg = get_parent().get_node_or_null("BackgroundGround")
		if bg: layers.append(bg)
	
	for layer in layers:
		if layer is TileMapLayer:
			for y in range(map_height):
				var cell = Vector2i(grid_x, y)
				if not animated:
					layer.erase_cell(cell)
				else:
					_animate_tile_disappear(layer, cell)

func _animate_tile_appear(layer: TileMapLayer, cell: Vector2i, source_id: int, atlas_coords: Vector2i) -> void:
	var proxy = _create_tile_proxy(layer, cell, source_id, atlas_coords)
	if not proxy:
		layer.set_cell(cell, source_id, atlas_coords)
		return
	
	# 增加位移距離，確保從螢幕底部之外升起
	var fall_distance = 200.0
	proxy.position.y += fall_distance
	
	var tween = create_tween()
	# 位移回原位
	tween.tween_property(proxy, "position:y", proxy.position.y - fall_distance, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	tween.tween_callback(func():
		layer.set_cell(cell, source_id, atlas_coords)
		proxy.queue_free()
	)

func _animate_tile_disappear(layer: TileMapLayer, cell: Vector2i) -> void:
	var source_id = layer.get_cell_source_id(cell)
	if source_id == -1: return # 空格不需要動畫
	
	var atlas_coords = layer.get_cell_atlas_coords(cell)
	var proxy = _create_tile_proxy(layer, cell, source_id, atlas_coords)
	
	# 立即移除實體地塊，由代理頂替
	layer.erase_cell(cell)
	
	if not proxy: return

	# 增加位移距離，確保沉到螢幕底部之外
	var fall_distance = 200.0
	
	var tween = create_tween()
	tween.tween_property(proxy, "position:y", proxy.position.y + fall_distance, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	tween.tween_callback(proxy.queue_free)

func _create_tile_proxy(layer: TileMapLayer, cell: Vector2i, source_id: int, atlas_coords: Vector2i) -> Sprite2D:
	var ts = layer.tile_set
	var source = ts.get_source(source_id) as TileSetAtlasSource
	if not source: return null
	
	var sprite = Sprite2D.new()
	sprite.texture = source.texture
	sprite.region_enabled = true
	
	var tile_size = ts.tile_size
	sprite.region_rect = Rect2(
		atlas_coords.x * tile_size.x, 
		atlas_coords.y * tile_size.y, 
		tile_size.x, 
		tile_size.y
	)
	
	# 取得 Grid 並轉換座標
	var grid = get_tree().get_first_node_in_group("grid")
	if grid and grid.has_method("grid_to_world_center"):
		sprite.global_position = grid.grid_to_world_center(cell)
	else:
		# 回退方案：簡單乘以尺寸
		sprite.position = Vector2(cell.x * tile_size.x + tile_size.x/2, cell.y * tile_size.y + tile_size.y/2)
		
	# 確保在 Ground 之下但高於背景 (或者跟隨 MapLoader)
	add_child(sprite)
	sprite.z_index = layer.z_index
	
	return sprite

## 擦除指定區域的地塊 (包含 Ground 與 BackgroundGround)
func clear_region(rect: Rect2i) -> void:
	var layers = []
	var ground = get_node_or_null(ground_layer_path)
	if ground: layers.append(ground)
	
	# 嘗試尋找兄弟節點中的 BackgroundGround
	if get_parent():
		var bg = get_parent().get_node_or_null("BackgroundGround")
		if bg: layers.append(bg)
	
	for layer in layers:
		if not layer is TileMapLayer: continue
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				layer.erase_cell(Vector2i(x, y))

## 在指定區域隨機填充地塊
func fill_random_ground(rect: Rect2i) -> void:
	var layers = []
	var ground = get_node_or_null(ground_layer_path)
	if ground: layers.append(ground)
	
	if get_parent():
		var bg = get_parent().get_node_or_null("BackgroundGround")
		if bg: layers.append(bg)
	
	for layer in layers:
		if not layer is TileMapLayer: continue
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				var chosen_tile = _base_coords
				var chosen_source = _base_source_id
				
				var roll = randf()
				var cumulative_chance = 0.0
				
				for var_data in _resolved_variations:
					cumulative_chance += var_data.chance
					if roll < cumulative_chance:
						chosen_tile = var_data.coords
						chosen_source = var_data.source_id
						break
				
				layer.set_cell(Vector2i(x, y), chosen_source, chosen_tile)

## 解析 AtlasTexture 為 TileSet 中的 ID 與座標
func _resolve_visual_tiles(layer: TileMapLayer) -> void:
	var ts = layer.tile_set
	if !ts: return
	
	# 1. 解析基礎地塊
	if base_tile_visual and base_tile_visual.atlas:
		var result = _find_tile_in_tileset(ts, base_tile_visual)
		_base_source_id = result.source_id
		_base_coords = result.coords
	else:
		# 如果沒選，預設使用目前的第一個 Source 和之前指定的 (4, 5)
		if ts.get_source_count() > 0:
			_base_source_id = ts.get_source_id(0)
		# _base_coords 已初始化為 (4, 5)
		print("[MapLoader] No base visual set, using default source %d and coords (4,6)" % _base_source_id)

	# 2. 解析變體
	_resolved_variations.clear()
	for v in variations:
		if v and v.tile_visual and v.tile_visual.atlas:
			var result = _find_tile_in_tileset(ts, v.tile_visual)
			if result.source_id != -1:
				_resolved_variations.append({
					"source_id": result.source_id,
					"coords": result.coords,
					"chance": v.chance
				})

func _find_tile_in_tileset(ts: TileSet, atlas_tex: AtlasTexture) -> Dictionary:
	var tex = atlas_tex.atlas
	var region = atlas_tex.region
	
	# 遍歷所有 Source 找到匹配該貼圖的 SourceID
	var source_id = -1
	for i in range(ts.get_source_count()):
		var sid = ts.get_source_id(i)
		var source = ts.get_source(sid)
		if source is TileSetAtlasSource and source.texture == tex:
			source_id = sid
			break
			
	if source_id == -1:
		push_warning("[MapLoader] Could not find Texture in TileSet: %s" % tex.resource_path)
		return {"source_id": -1, "coords": Vector2i.ZERO}
		
	# 計算座標 (Region Position / Tile Size)
	# 假設所有地塊都是一致的大小
	var tile_size = ts.tile_size
	var coords = Vector2i(
		int(round(region.position.x / tile_size.x)),
		int(round(region.position.y / tile_size.y))
	)
	
	return {"source_id": source_id, "coords": coords}

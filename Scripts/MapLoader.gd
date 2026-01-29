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

func _ready() -> void:
	add_to_group("map_loader") # Register for DungeonManager
	
	var ground_layer = get_node_or_null(ground_layer_path)
	if ground_layer is TileMapLayer:
		_resolve_visual_tiles(ground_layer) # 解析視覺化地塊數據
		_initialize_ground(ground_layer)
	elif ground_layer:
		push_error("[MapLoader] Ground layer found but is not a TileMapLayer!")
	
	var resources_layer = get_node_or_null(resources_layer_path)
	if resources_layer is TileMapLayer:
		_initialize_resources(resources_layer)
	elif resources_layer:
		print("[MapLoader] ResourcesLayer found but is not a TileMapLayer, skipping _initialize_resources")
		
	# 初始啟動時載入 T001.tres
	var t001 = load("res://Resources/Rooms/T001.tres")
	if t001:
		# 使用 call_deferred 確保在所有節點 ready 後才執行
		call_deferred("_initial_room_load", t001)
	
	# 初始化回合系統
	if TurnManager:
		TurnManager.start_combat([FACTION_PLAYER, FACTION_ENEMY])

func _initial_room_load(template: RoomTemplate) -> void:
	var spawned = instantiate_room(template)
	# 確保初始載入的單位也會播放進場動畫
	for entity in spawned:
		if entity.has_method("play_entry_animation"):
			entity.play_entry_animation(0.2)
	
	# 自動部署玩家隊伍成員
	_auto_deploy_party(template)

func _auto_deploy_party(template: RoomTemplate) -> void:
	if not PartyManager: return
	
	var members = PartyManager.get_members()
	var spawn_points = template.player_spawn_points
	
	for i in range(min(members.size(), spawn_points.size())):
		var member_data = members[i]
		var spawn_pos = spawn_points[i]
		
		var _success = PartyManager.spawn_party_member(member_data, spawn_pos)
	
	# 部署完成後，主動結束部署階段進入戰鬥
	if TurnManager and TurnManager.current_state == TurnManager.State.DEPLOYMENT:
		TurnManager.end_deployment()

func _initialize_ground(_layer: TileMapLayer) -> void:
	# 初始啟動時，先清除可能殘留在右側的編輯器地塊
	clear_region(Rect2i(map_width, 0, 10, map_height))
	
	# 初始啟動時，也隨機填充一次主區域
	print("[MapLoader] Initializing ground with random tiles...")
	fill_random_ground(Rect2i(0, 0, map_width, map_height))

func _initialize_resources(_layer: TileMapLayer) -> void:
	# 這裡可以根據需要初始化資源層
	pass

# --- Dungeon Manager API ---

func clear_current_map(skip_ground_init: bool = false) -> void:
	# 1. 重置網格佔用狀態
	var grid_node = get_tree().get_first_node_in_group("grid")
	if grid_node and grid_node.has_method("clear_all_occupancy"):
		grid_node.clear_all_occupancy()
	
	# 2. 移除敵人與非玩家實體
	var entities = get_tree().get_nodes_in_group("grid_entities")
	for entity in entities:
		if is_instance_valid(entity) and entity is GridEntity:
			# 核心修正：保留玩家單位，不予移除
			if entity.faction and entity.faction.is_controllable:
				continue
			
			# 移除其他單位 (敵人、障礙物等)
			if BoardManager:
				BoardManager.unregister_entity(entity)
			entity.queue_free()
			
	# 始終清空所有可見地塊 (確保轉場起始是乾淨的)
	clear_region(Rect2i(-50, -50, 100, 100))
	
	# 如果不跳過初始化，則填充預設地圖
	if not skip_ground_init:
		var layer = get_node_or_null(ground_layer_path) as TileMapLayer
		if layer:
			_initialize_ground(layer)
	else:
		# 即使跳過填充，也要解析視覺地塊數據
		var layer = get_node_or_null(ground_layer_path) as TileMapLayer
		if layer:
			_resolve_visual_tiles(layer)

func instantiate_room(template: RoomTemplate) -> Array[GridEntity]:
	print("[MapLoader] Instantiating room: ", template.room_name)
	
	# 0. 同步更新 DungeonManager 的當前房間狀態
	var dm = get_tree().root.get_node_or_null("DungeonManager")
	if dm and dm.has_method("register_current_room"):
		dm.register_current_room(template)
	
	# 1. 清理舊地圖與實體
	clear_current_map(true)
	
	# 2. 更新地圖尺寸以符合模板
	if template.width > 0: map_width = template.width
	if template.height > 0: map_height = template.height
	
	var grid_node = get_tree().get_first_node_in_group("grid")
	if grid_node:
		grid_node.map_width = map_width
		grid_node.map_height = map_height
		if grid_node.has_signal("size_changed"):
			grid_node.size_changed.emit()
	
	# 3. 重新生成地面地塊 (球桌)
	var ground_layer = get_node_or_null(ground_layer_path) as TileMapLayer
	if ground_layer:
		_resolve_visual_tiles(ground_layer)
		fill_random_ground(Rect2i(0, 0, map_width, map_height))
		print("[MapLoader] Ground tiles (table) regenerated for room: ", map_width, "x", map_height)
	
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
func spawn_entity(scene: PackedScene, card: Resource, grid_pos: Vector2i, faction_group: String, overrides: Dictionary = {}, is_dynamic: bool = false) -> GridEntity:
	if not scene: return null
	
	# 1. 實例化
	var instance = scene.instantiate()
	if not instance is GridEntity:
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
	
	# 3. 統一初始化
	var is_player_unit = (faction_group == "player")
	unit.initialize_runtime(char_data, faction_group, is_player_unit)
	
	# 4. 應用數值覆蓋
	if not overrides.is_empty() and unit.has_method("apply_overrides"):
		unit.apply_overrides(overrides)
		
	# 5. 加入場景樹
	add_unit_to_scene(unit)
	
	# 6. 網格定位與系統註冊
	unit.set_grid_position(grid_pos)
	
	if BoardManager:
		BoardManager.register_entity(unit)
		
	# 7. 視覺準備
	if is_dynamic or is_player_unit:
		unit.visible = true
		unit.modulate.a = 1.0
		var sprite = unit.get_node_or_null("Sprite2D")
		if sprite: 
			sprite.visible = true
			sprite.modulate.a = 1.0
		var visuals = unit.get_node_or_null("UnitVisuals")
		if visuals and "sprite" in visuals and visuals.sprite:
			visuals.sprite.visible = true
			visuals.sprite.modulate.a = 1.0
		
		if unit.has_method("unlock_physics"):
			unit.unlock_physics()
	elif unit.has_method("prepare_for_entry"):
		unit.prepare_for_entry()
		
	return unit

## 統一投射物生成 API
func spawn_projectile(scene: PackedScene, source: GridEntity, target_dir: Vector2, params: Dictionary = {}) -> Node:
	if not scene or not source: return null
	
	var projectile = scene.instantiate()
	var spd = params.get("speed", 300.0)
	var dmg = params.get("damage", 1)
	if source.character_data and not params.has("damage"):
		dmg = source.character_data.get_effective_attack()
	
	var is_piercing = params.get("is_piercing", false)
	if params.has("texture") and params["texture"].resource_path.contains("magicorb"):
		is_piercing = true
	
	if "is_piercing" in projectile:
		projectile.is_piercing = is_piercing
	
	if projectile.has_method("setup"):
		projectile.setup(source.global_position, target_dir, dmg, spd, source)
	
	if params.has("texture") and projectile.has_method("set_texture"):
		projectile.set_texture(params["texture"])
	
	add_child(projectile)
	
	if TurnManager and TurnManager.has_method("on_unit_launched"):
		TurnManager.on_unit_launched(projectile, target_dir.normalized() * spd)
		
	if not projectile.is_in_group("projectiles"):
		projectile.add_to_group("projectiles")
		
	return projectile

func add_unit_to_scene(unit: Node) -> void:
	var units_layer = get_node_or_null("Entities/UnitsLayer")
	if units_layer:
		units_layer.add_child(unit)
	else:
		add_child(unit)

## 擦除指定區域的地塊
func clear_region(rect: Rect2i) -> void:
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
	
	if base_tile_visual and base_tile_visual.atlas:
		var result = _find_tile_in_tileset(ts, base_tile_visual)
		_base_source_id = result.source_id
		_base_coords = result.coords
	else:
		if ts.get_source_count() > 0:
			_base_source_id = ts.get_source_id(0)
		print("[MapLoader] No base visual set, using default source %d and coords (4,6)" % _base_source_id)

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
	var source_id = -1
	for i in range(ts.get_source_count()):
		var sid = ts.get_source_id(i)
		var source = ts.get_source(sid)
		if source is TileSetAtlasSource and source.texture == tex:
			source_id = sid
			break
			
	if source_id == -1:
		return {"source_id": -1, "coords": Vector2i.ZERO}
		
	var tile_size = ts.tile_size
	var coords = Vector2i(
		int(round(region.position.x / tile_size.x)),
		int(round(region.position.y / tile_size.y))
	)
	
	return {"source_id": source_id, "coords": coords}

extends GridEntity
class_name TreasureChestEnemy

## 寶箱敵人：被擊敗後會掉落隨機裝備
## 繼承 GridEntity 以複用所有受擊與死亡特效

var _last_burst_threshold: int = 500
const BURST_INTERVAL: int = 100
const COINS_PER_BURST: int = 20

func _ready() -> void:
	super._ready()
	# 初始血量設定 (如果沒有被 override)
	if character_data:
		_last_burst_threshold = int(character_data.max_health)
		# 監聽血量變化來觸發爆金幣
		if not character_data.health_changed.is_connected(_on_chest_health_changed):
			character_data.health_changed.connect(_on_chest_health_changed)

func _on_chest_health_changed(current: int, _max_hp: int) -> void:
	if is_dying: return
	
	# 檢查是否跨越了爆金幣門檻
	while _last_burst_threshold - current >= BURST_INTERVAL:
		_spawn_coin_burst(COINS_PER_BURST)
		_last_burst_threshold -= BURST_INTERVAL

func _spawn_coin_burst(amount: int) -> void:
	var coin_scene = load("res://Scenes/Shared/PhysicalCoin.tscn")
	if not coin_scene: return
	
	print("[TreasureChest] Bursting %d coins!" % amount)
	for i in range(amount):
		# 使用 call_deferred 避開物理查詢期間的狀態變更錯誤
		call_deferred("_do_spawn_single_coin", coin_scene)

func _do_spawn_single_coin(coin_scene: PackedScene) -> void:
	var coin = coin_scene.instantiate()
	var offset = Vector2(randf_range(-16, 16), randf_range(-16, 16))
	get_parent().add_child(coin)
	coin.global_position = global_position + offset

func _handle_death() -> void:
	if is_dying: return
	
	# 使用 call_deferred 確保在物理查詢結束後才生成裝備，避開 flushing_queries 錯誤
	call_deferred("_drop_equipment")
	
	# 呼叫父類執行現有的死亡動畫、粒子與清理邏輯
	super._handle_death()

func _drop_equipment() -> void:
	# 獲取生成器與地圖載入器
	var generator = get_node_or_null("/root/EquipmentGenerator")
	var map_loader_node = get_tree().get_first_node_in_group("map_loader")
	
	if generator and map_loader_node:
		# 1. 獲取當前層數以決定裝備強度
		var current_floor_lvl = 1
		var dungeon_manager = get_node_or_null("/root/DungeonManager")
		if dungeon_manager and "current_floor" in dungeon_manager:
			current_floor_lvl = dungeon_manager.current_floor
		
		# 2. 生成隨機裝備數據
		var random_data = generator.generate_random_item(current_floor_lvl)
		if not random_data:
			print("[TreasureChest] ERROR: EquipmentGenerator returned null!")
			return
			
		print("[TreasureChest] Generated item: %s" % random_data.item_name)
		
		# 3. 生成裝備實體
		var equip_scene = load("res://Scenes/Entities/EquipmentEntity.tscn")
		var equip_instance = equip_scene.instantiate()
		equip_instance.name = "DroppedEquipment_" + random_data.item_name
		
		# 使用 set() 賦值，確保在加入場景樹前數據已到位
		# 這裡我們使用 Object.set 避開潛在的型別檢查衝突
		equip_instance.set("equipment_data", random_data)
		
		# 加入場景層級
		var units_layer = map_loader_node.get_node_or_null("Entities/UnitsLayer")
		if units_layer:
			units_layer.add_child(equip_instance)
		else:
			get_parent().add_child(equip_instance)
			
		# 初始化實體狀態 (核心修正：移除會覆寫物理層級的 initialize_runtime 呼叫)
		
		# 設定座標
		equip_instance.global_position = global_position
		
		# 給予初始衝量噴出
		var random_dir = Vector2.UP.rotated(randf_range(-1.0, 1.0))
		var force = randf_range(200.0, 400.0)
		equip_instance.apply_central_impulse(random_dir * force)
			
		# 強制更新視覺
		if equip_instance.has_method("_update_sprite_from_data"):
			equip_instance.call("_update_sprite_from_data")
			
		equip_instance.visible = true
		equip_instance.modulate.a = 1.0
		
		print("[TreasureChest] Dropped %s via physics" % random_data.item_name)
	else:
		print("[TreasureChest] ERROR: Generator or MapLoader missing!")

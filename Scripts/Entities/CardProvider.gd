extends Node
class_name CardProvider

# 預載入 FootprintData 以確保類型可被找到
const FootprintDataScript = preload("res://Footprints/FootprintData.gd")

signal components_applied(entity: GridEntity)

# 使用 Variant 或 Object 類型以支持 RuntimeCardData 和 BaseCard
@export var card: Resource

var _parent: Node = null

func _ready() -> void:
	_parent = get_parent()
	if _parent == null:
		return
	# 只有在 card 已設置時才應用（避免在 set_card_and_apply 之前執行）
	if card != null:
		_apply_to_components()

func get_card() -> Resource:
	return card

## 設置卡片並應用所有配置（用於運行時設置）
# card_data 可是 BaseCard (Resource) 或 RuntimeCardData (RefCounted)
func set_card_and_apply(card_data) -> void:
	card = card_data
	if _parent == null:
		_parent = get_parent()
	_apply_to_components()
	# 通知其他組件重新同步（確保參數正確應用）
	_notify_components_updated()

func _apply_to_components() -> void:
	if card == null:
		return
	
	# GridEntity footprint_data 和 faction 同步
	var grid_entity = _parent as GridEntity
	if grid_entity != null:
		if card.has_method("get"):
			# 1. Faction 同步
			var faction_res = card.get("faction")
			if faction_res != null and faction_res is FactionDefinition:
				grid_entity.faction = faction_res
			
			# 2. FootprintData 同步
			var fp_data = card.get("footprint_data")
			if fp_data != null and fp_data is FootprintDataScript:
				var new_footprint_data = fp_data
				# 只有當 footprint_data 改變時才更新
				if grid_entity.footprint_data != new_footprint_data:
					grid_entity.footprint_data = new_footprint_data
					# 如果位置已經設置，需要重新註冊格子並更新位置
					if grid_entity.grid_position != Vector2i(-1, -1) and grid_entity.grid != null:
						grid_entity._unregister_cells()
						# 重新計算左上角位置（從中心計算）
						var center_cell = grid_entity.grid.world_to_grid(grid_entity.global_position)
						var bounds = new_footprint_data.get_bounds()
						grid_entity.grid_position = center_cell - Vector2i(bounds.position.x + bounds.size.x / 2, bounds.position.y + bounds.size.y / 2)
						grid_entity._register_cells()
						# 重新計算世界座標
						grid_entity.global_position = grid_entity.grid.grid_to_world_center_footprint(grid_entity.grid_position, new_footprint_data)
		
			# 4. MovementRangeData 初始化 (支援動態修改)
			var mv_data = card.get("movement_range_data")
			if mv_data != null and mv_data is MovementRangeData:
				# 關鍵：複製資源以支援獨立修改（Buff/Debuff）
				var runtime_data = mv_data.duplicate()
				if grid_entity.has_method("set_movement_data"):
					grid_entity.set_movement_data(runtime_data)
		
		# 3. CharacterData 初始化 (Unit Only)
		# 檢查是否為 UnitCard 或包裝了 UnitCard 的 RuntimeCardData
		var is_unit_card = card is UnitCard
		if not is_unit_card and card.has_method("get_base_data"): # RuntimeCardData check
			is_unit_card = card.get_base_data() is UnitCard
			
		if is_unit_card and grid_entity.has_method("setup_character"):
			# 如果是 RuntimeCardData，我們需要獲取原始 UnitCard 才能創建 CharacterData
			# 或者 CharacterData.create 應該支援 RuntimeCardData? 
			# 目前 create 接受 UnitCard。
			var unit_card_res = card
			if card.has_method("get_base_data"):
				unit_card_res = card.get_base_data()
				
			if unit_card_res is UnitCard:
				var char_data = CharacterData.create(unit_card_res as UnitCard)
				grid_entity.setup_character(char_data)
	
	# BuildingStat 支援（建築血量管理）
	var building_stat = _parent.get_node_or_null("BuildingStat") as BuildingStat
	if building_stat != null and card.has_method("get"):
		# 使用 get 來兼容 RuntimeCardData 和 BaseCard
		var max_hp = card.get("max_health")
		if max_hp != null:
			building_stat.max_health = int(max_hp)
			# 如果建築是滿血狀態，則初始化為新的 max_health
			if building_stat.current_health >= building_stat.max_health:
				building_stat.current_health = int(max_hp)
	
	# 發出信號通知組件已應用
	if grid_entity != null:
		components_applied.emit(grid_entity)

## 通知其他組件參數已更新（用於運行時設置後重新同步）
func _notify_components_updated() -> void:
	# 預留接口，供未來擴展使用
	pass

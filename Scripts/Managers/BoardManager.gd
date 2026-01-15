extends Node

# 記錄所有在場上的實體： { FactionDefinition: [GridEntity, GridEntity, ...] }
var _entities_by_faction: Dictionary = {}

signal entity_registered(entity: GridEntity)
signal entity_unregistered(entity: GridEntity)

func _ready() -> void:
	print("[BoardManager] Initialized")

## 註冊實體
func register_entity(entity: GridEntity) -> void:
	if entity == null or entity.faction == null:
		return
	
	if not _entities_by_faction.has(entity.faction):
		_entities_by_faction[entity.faction] = []
	
	var list = _entities_by_faction[entity.faction]
	if not list.has(entity):
		list.append(entity)
		entity_registered.emit(entity)
		# print("[BoardManager] Registered entity: ", entity.name, " for faction: ", entity.faction.faction_name)

## 註銷實體
func unregister_entity(entity: GridEntity) -> void:
	if entity == null or entity.faction == null:
		return
	
	if _entities_by_faction.has(entity.faction):
		var list = _entities_by_faction[entity.faction]
		if list.has(entity):
			list.erase(entity)
			entity_unregistered.emit(entity)
			# print("[BoardManager] Unregistered entity: ", entity.name, " from faction: ", entity.faction.faction_name)

## 獲取某陣營的所有實體
func get_entities_by_faction(faction: FactionDefinition) -> Array:
	if _entities_by_faction.has(faction):
		return _entities_by_faction[faction].duplicate() # 返回副本以防遍歷時修改
	return []

## 獲取所有實體 (扁平化列表)
func get_all_entities() -> Array:
	var all_entities = []
	for faction in _entities_by_faction:
		all_entities.append_array(_entities_by_faction[faction])
	return all_entities

## 清除所有實體記錄 (用於地圖切換)
func clear_all() -> void:
	_entities_by_faction.clear()
	print("[BoardManager] All entities cleared")

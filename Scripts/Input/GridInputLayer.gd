extends Control
class_name GridInputLayer

# 覆蓋在 Grid 上方，用於接收 UI 拖曳

var grid: Node
var skill_preview_controller: Node

func _ready() -> void:
	# ... (尋找 Grid 等邏輯)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# 1. 檢查數據類型
	# Hand.gd 傳遞的可能是 RuntimeCardData
	if data is RuntimeCardData:
		if data.is_skill_card():
			return _can_drop_skill(data.get_skill_card())
		elif data.get_base_data() is UnitCard: # 假設 UnitCard 也是一種 Resource
			# 目前部署邏輯是用 CharacterData，如果 Hand 傳遞 RuntimeCardData，需要能轉為 CharacterData 或直接從 UnitCard 部署
			# 為了相容現有邏輯，這裡假設 data 可能是 RuntimeCardData 但包含單位訊息
			# 但原始代碼是 check (data is CharacterData)
			# 如果 Hand 傳遞的是 RuntimeCardData，那麼舊邏輯可能已經失效，或是 Hand 傳遞的是 card.card_data (這是 RuntimeCardData)
			
			# TODO: 適配 UnitCard 部署流程
			return false 
			
	if data is CharacterData:
		return _can_drop_unit(data)
	elif data is SkillCard:
		return _can_drop_skill(data)
	
	return false

func _can_drop_unit(data: CharacterData) -> bool:
	if not PartyManager:
		return false
		
	if grid == null:
		grid = get_tree().get_first_node_in_group("grid")
	if grid == null or not grid.has_method("world_to_grid"):
		return false
		
	var cell = _get_grid_cell_from_mouse()
	
	# 詢問 PartyManager 是否可放置
	return PartyManager.can_place_member(data, cell)

func _can_drop_skill(card: SkillCard) -> bool:
	var skill_manager = get_node_or_null("/root/SkillManager")
	if not skill_manager:
		return false
	
	# 檢查 Soul 是否足夠 (這裡做預檢查，實際扣除在 cast_skill)
	if PlayerResourceLedger:
		if not PlayerResourceLedger.can_afford({"soul": card.soul_cost}):
			return false
	
	var cell = _get_grid_cell_from_mouse()
	
	# 更新技能預覽
	if skill_preview_controller:
		skill_preview_controller.update_preview(card, cell)
	
	# 檢查是否有有效目標 (SkillManager 提供預覽檢查)
	var targets = skill_manager.get_valid_targets(card.targeting, cell, null) # source=null 暫時
	if targets.is_empty() and not card.targeting.can_target_empty:
		return false
		
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is CharacterData:
		_drop_unit(data)
	elif data is SkillCard:
		_drop_skill(data)
	elif data is RuntimeCardData:
		if data.is_skill_card():
			_drop_skill(data.get_skill_card())

func _drop_unit(data: CharacterData) -> void:
	if grid == null: return
	var cell = _get_grid_cell_from_mouse()
	
	var success = PartyManager.spawn_party_member(data, cell)
	if success:
		# Optional: Play sound or effect
		pass

func _drop_skill(card: SkillCard) -> void:
	var skill_manager = get_node_or_null("/root/SkillManager")
	if not skill_manager: return
	
	var cell = _get_grid_cell_from_mouse()
	
	# 嘗試施放
	# TODO: 傳入施法來源 (目前假設無來源或全域)
	skill_manager.cast_skill(card, cell, null)

func _get_grid_cell_from_mouse() -> Vector2i:
	if grid == null:
		grid = get_tree().get_first_node_in_group("grid")
		
	var camera = get_viewport().get_camera_2d()
	var mouse_world_pos = get_global_mouse_position()
	if camera:
		mouse_world_pos = camera.get_global_mouse_position()
		
	if grid and grid.has_method("world_to_grid"):
		return grid.world_to_grid(mouse_world_pos)
		
	return Vector2i.ZERO

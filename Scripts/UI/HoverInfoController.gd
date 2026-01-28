extends Control

@export var offset_from_mouse: Vector2 = Vector2(20, -20)

var _card_instance: Control = null
var _trap_card_instance: Control = null
var _equip_panel_instance: Control = null
var _skill_tooltip_instance: Control = null
var _grid: Node = null
var _last_hovered_entity_id: int = -1 # Track instance ID to force updates
var _current_entity: GridEntity = null # 目前懸停的實體
var _is_ui_hovering: bool = false # 標記目前是否由 UI 元素觸發懸停顯示

const EnemyInfoCardScene = preload("res://Scenes/UI/EnemyInfoCard.tscn")
const TrapInfoCardScene = preload("res://Scenes/UI/TrapInfoCard.tscn")
const SkillTooltipScene = preload("res://Scenes/UI/Skills/SkillTooltipUI.tscn")
var EquipmentInfoPanelScene = null

func _ready() -> void:
	add_to_group("hover_info_controller")
	# Load instead of preload to avoid blocking compilation
	EquipmentInfoPanelScene = load("res://Scenes/UI/EquipmentInfoPanel.tscn")
	if EquipmentInfoPanelScene == null:
		push_error("[HoverInfoController] Failed to load EquipmentInfoPanel.tscn!")
		
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 直接尋找 Grid
	_grid = get_tree().get_first_node_in_group("grid")
	if not _grid:
		push_warning("[HoverInfoController] Grid not found!")
		
	if EnemyInfoCardScene:
		_card_instance = EnemyInfoCardScene.instantiate()
		add_child(_card_instance)
		_card_instance.visible = false
		_card_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	if TrapInfoCardScene:
		_trap_card_instance = TrapInfoCardScene.instantiate()
		add_child(_trap_card_instance)
		_trap_card_instance.visible = false
		_trap_card_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	if EquipmentInfoPanelScene:
		_equip_panel_instance = EquipmentInfoPanelScene.instantiate()
		add_child(_equip_panel_instance)
		_equip_panel_instance.visible = false
		_equip_panel_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	if SkillTooltipScene:
		_skill_tooltip_instance = SkillTooltipScene.instantiate()
		add_child(_skill_tooltip_instance)
		_skill_tooltip_instance.visible = false
		_skill_tooltip_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	# 將面板移至頂層 CanvasLayer 確保不會被遮擋
	call_deferred("_reparent_to_top_layer")

func _reparent_to_top_layer() -> void:
	# 建立一個專用的高層級 CanvasLayer，確保面板永遠在最上層
	var layer = CanvasLayer.new()
	layer.layer = 100 # 足夠高以覆蓋所有 UI
	layer.name = "HoverInfoLayer"
	add_child(layer)
	
	if _card_instance:
		_card_instance.reparent(layer)
	if _trap_card_instance:
		_trap_card_instance.reparent(layer)
	if _equip_panel_instance:
		_equip_panel_instance.reparent(layer)
	if _skill_tooltip_instance:
		_skill_tooltip_instance.reparent(layer)
		
	print("[HoverInfoController] Panels reparented to new top-level CanvasLayer (layer 100)")

func _process(_delta: float) -> void:
	# 0. 如果目前是由 UI (如裝備欄) 觸發的懸停，我們只更新位置，不執行地圖偵測邏輯
	if _is_ui_hovering:
		_update_position()
		return

	# 1. 拖拽中強制隱藏
	if get_viewport().gui_is_dragging():
		_hide_all()
		return

	# 2. 獲取滑鼠下的實體
	var entity = _get_entity_under_mouse()
	
	# 3. 更新顯示
	if entity:
		_update_display_logic(entity)
		_update_position()
	else:
		_hide_all()

func _get_entity_under_mouse() -> GridEntity:
	# 關鍵修正：改用物理查詢而非網格佔用，以支援移動中的實體偵測
	var mouse_pos = get_global_mouse_position()
	var camera = get_viewport().get_camera_2d()
	if camera:
		mouse_pos = camera.get_global_mouse_position()
		
	var space_state = get_viewport().get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	query.collision_mask = 1 | 4 # 偵測 Unit Layer (1) 與 Prop/Trap Layer (4)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var results = space_state.intersect_point(query)
	if results.is_empty():
		return null
		
	for res in results:
		var collider = res.collider
		if collider is GridEntity:
			return collider
			
	return null

func _update_display_logic(entity: GridEntity) -> void:
	if not _card_instance or not _trap_card_instance or not _equip_panel_instance: 
		print("[HoverInfoController] ERROR: Card instances missing!")
		return
	
	_current_entity = entity
	var current_id = entity.get_instance_id()
	var is_new_entity = (current_id != _last_hovered_entity_id)
	
	if is_new_entity:
		pass
	
	# 1. 檢查是否為裝備實體
	if entity is EquipmentEntity:
		var data = entity.get_equipment_data()
		if is_new_entity or not _equip_panel_instance.visible:
			print("[HoverInfoController] Showing Equipment Card")
			_last_hovered_entity_id = current_id
			show_data_info(data, false) # 地圖實體不鎖定，讓 _process 持續偵測
		return
		
	# 2. 檢查是否為敵對單位或陷阱
	if entity is TrapEntity or entity.is_in_group("traps"):
		if is_new_entity or not _trap_card_instance.visible:
			print("[HoverInfoController] Showing Trap Card for: ", entity.name)
			_last_hovered_entity_id = current_id
			if _trap_card_instance.has_method("update_info"):
				_trap_card_instance.update_info(entity)
			_trap_card_instance.visible = true
			_card_instance.visible = false
			_equip_panel_instance.visible = false
		return

	var show_enemy_info = false
	if entity.is_in_group("enemy"):
		show_enemy_info = true
	elif entity.faction:
		if entity.faction.resource_path.to_lower().contains("enemy"):
			show_enemy_info = true
		elif not entity.faction.resource_path.to_lower().contains("player"):
			show_enemy_info = true
			
	if show_enemy_info:
		if is_new_entity or not _card_instance.visible:
			# print("[HoverInfoController] Showing Enemy Card for: ", entity.name)
			_last_hovered_entity_id = current_id
			if _card_instance.has_method("update_info"):
				_card_instance.update_info(entity)
			_card_instance.visible = true
			_trap_card_instance.visible = false
			_equip_panel_instance.visible = false
	else:
		_hide_all()

func _update_position() -> void:
	var active_panel = null
	if _card_instance and _card_instance.visible:
		active_panel = _card_instance
	elif _trap_card_instance and _trap_card_instance.visible:
		active_panel = _trap_card_instance
	elif _equip_panel_instance and _equip_panel_instance.visible:
		active_panel = _equip_panel_instance
	elif _skill_tooltip_instance and _skill_tooltip_instance.visible:
		active_panel = _skill_tooltip_instance
		
	if active_panel:
		# 決定錨點位置 (Anchor Position)
		# 如果有正在懸停的實體，錨點為實體位置；否則為滑鼠位置
		var anchor_pos = get_viewport().get_mouse_position()
		
		if not _is_ui_hovering and is_instance_valid(_current_entity):
			# 獲取實體在螢幕上的位置
			anchor_pos = _current_entity.get_global_transform_with_canvas().origin
		
		var target_pos = anchor_pos + offset_from_mouse
		
		var viewport_rect = get_viewport_rect()
		# Use combined minimum size to ensure we handle adaptive containers correctly
		var panel_size = active_panel.get_combined_minimum_size()
			
		if target_pos.x + panel_size.x > viewport_rect.size.x:
			target_pos.x = anchor_pos.x - panel_size.x - offset_from_mouse.x
			
		if target_pos.y + panel_size.y > viewport_rect.size.y:
			target_pos.y = anchor_pos.y - panel_size.y - offset_from_mouse.y
			
		active_panel.global_position = target_pos

func _hide_all() -> void:
	_is_ui_hovering = false
	_last_hovered_entity_id = -1
	_current_entity = null
	if _card_instance: _card_instance.visible = false
	if _trap_card_instance: _trap_card_instance.visible = false
	if _equip_panel_instance: _equip_panel_instance.visible = false
	if _skill_tooltip_instance: _skill_tooltip_instance.visible = false

# 公開 API：讓 UI 元素直接顯示資料
func show_data_info(data: Resource, from_ui: bool = false) -> void:
	if data == null:
		_hide_all()
		return
		
	print("[HoverInfoController] Showing data info for: %s (From UI: %s)" % [data.get("item_name"), "YES" if from_ui else "NO"])
	
	# 只有來自 UI 的請求才需要鎖定，地圖實體由 _process 自動隱藏
	if from_ui:
		_is_ui_hovering = true
	else:
		_is_ui_hovering = false
	
	# 目前只支援 EquipmentData
	if data.get("modifiers") != null: # 鴨子類型判斷是否為裝備
		if _equip_panel_instance and _equip_panel_instance.has_method("display_equipment"):
			_equip_panel_instance.display_equipment(data)
			_equip_panel_instance.visible = true
			# 確保面板在最上層 (在新的父節點中)
			_equip_panel_instance.get_parent().move_child(_equip_panel_instance, -1)
			# 更新位置為目前滑鼠位置
			_update_position()

func show_skill_info(skill: Resource, from_ui: bool = false) -> void:
	if skill == null:
		_hide_all()
		return
		
	if from_ui:
		_is_ui_hovering = true
	else:
		_is_ui_hovering = false
		
	if _skill_tooltip_instance and _skill_tooltip_instance.has_method("setup"):
		_skill_tooltip_instance.setup(skill)
		_skill_tooltip_instance.visible = true
		_skill_tooltip_instance.get_parent().move_child(_skill_tooltip_instance, -1)
		_update_position()

extends Control

@export var offset_from_mouse: Vector2 = Vector2(20, -20)
@export var synergy_tooltip_offset: Vector2 = Vector2(100, -20)

var _card_instance: Control = null
var _trap_card_instance: Control = null
var _equip_panel_instance: Control = null
var _skill_tooltip_instance: Control = null
var _synergy_tooltip_instance: Control = null
var _grid: Node = null
var _last_hovered_entity_id: int = -1 # Track instance ID to force updates
var _current_entity: Node = null # 目前懸停的實體
var _is_ui_hovering: bool = false # 標記目前是否由 UI 元素觸發懸停顯示

const EnemyInfoCardScene = preload("res://Scenes/UI/EnemyInfoCard.tscn")
const TrapInfoCardScene = preload("res://Scenes/UI/TrapInfoCard.tscn")
const SkillTooltipScene = preload("res://Scenes/UI/Skills/SkillTooltipUI.tscn")
const SynergyTooltipScene = preload("res://Scenes/UI/Synergy/SynergyTooltipUI.tscn")
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

	if SynergyTooltipScene:
		_synergy_tooltip_instance = SynergyTooltipScene.instantiate()
		add_child(_synergy_tooltip_instance)
		_synergy_tooltip_instance.visible = false
		_synergy_tooltip_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
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
	if _synergy_tooltip_instance:
		_synergy_tooltip_instance.reparent(layer)
		
	print("[HoverInfoController] Panels reparented to new top-level CanvasLayer (layer 100)")

func _process(_delta: float) -> void:
	# 0. 如果目前是由 UI (如裝備欄) 觸發的懸停，我們只更新位置，不執行地圖偵測邏輯
	if _is_ui_hovering:
		_update_position()
		return

	# 1. 拖拽中強制隱藏
	if get_viewport().gui_is_dragging():
		if _equip_panel_instance.visible or _card_instance.visible or _skill_tooltip_instance.visible or (_synergy_tooltip_instance and _synergy_tooltip_instance.visible):
			_hide_all()
		return

	# 2. 獲取滑鼠下的實體
	var entity = _get_entity_under_mouse()
	
	# 3. 更新顯示
	if entity:
		_update_display_logic(entity)
		# 核心修正：如果顯示了面板，就更新位置
		if _equip_panel_instance.visible or _card_instance.visible or _trap_card_instance.visible or (_synergy_tooltip_instance and _synergy_tooltip_instance.visible):
			_update_position()
	else:
		_hide_all()

func _get_entity_under_mouse() -> Node:
	# 關鍵修正：改用物理查詢而非網格佔用，以支援移動中的實體偵測
	var mouse_pos = get_global_mouse_position()
	var camera = get_viewport().get_camera_2d()
	if camera:
		mouse_pos = camera.get_global_mouse_position()
		
	var space_state = get_viewport().get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	# 核心修正：增加偵測半徑 (使用 intersect_point 的預設行為，但確保我們能抓到微小的金幣/裝備)
	query.collision_mask = 1 | 4 | 128 # 偵測 Unit (1), Prop (4), Coin (128)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var results = space_state.intersect_point(query)
	
	if results.is_empty():
		# 備援方案：如果點查詢失敗，嘗試在滑鼠周圍做一個微小的圓形查詢
		var circle_query = PhysicsShapeQueryParameters2D.new()
		var circle = CircleShape2D.new()
		circle.radius = 8.0 # 擴大偵測範圍到 16 像素直徑
		circle_query.shape = circle
		circle_query.transform = Transform2D(0, mouse_pos)
		circle_query.collision_mask = 1 | 4 | 128
		circle_query.collide_with_areas = true
		circle_query.collide_with_bodies = true
		results = space_state.intersect_shape(circle_query)

	if results.is_empty():
		return null
		
	for res in results:
		var collider = res.collider
		# 額外檢查：確保實體仍然有效且未被標記為刪除
		if not is_instance_valid(collider) or collider.is_queued_for_deletion():
			continue
			
		if collider is GridEntity or collider is EquipmentEntity:
			return collider
			
	return null

func _update_display_logic(entity: Node) -> void:
	if not _card_instance or not _trap_card_instance or not _equip_panel_instance: 
		print("[HoverInfoController] ERROR: Card instances missing!")
		return
	
	_current_entity = entity
	var current_id = entity.get_instance_id()
	var is_new_entity = (current_id != _last_hovered_entity_id)
	
	# 1. 檢查是否為裝備實體 (增加更多判定方式)
	var is_equip = entity.is_in_group("equipment_entities") or entity is EquipmentEntity
	if is_equip:
		var data = null
		if entity.has_method("get_equipment_data"):
			data = entity.get_equipment_data()
		elif "equipment_data" in entity:
			data = entity.equipment_data
			
		if data:
			if is_new_entity or not _equip_panel_instance.visible:
				print("[HoverInfoController] DETECTED Equipment: ", data.item_name)
				_last_hovered_entity_id = current_id
				show_data_info(data, false)
			return
		else:
			print("[HoverInfoController] DETECTED Equipment but DATA IS NULL")
		
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

	if not entity is GridEntity:
		_hide_all()
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
	elif _synergy_tooltip_instance and _synergy_tooltip_instance.visible:
		active_panel = _synergy_tooltip_instance
		
	if active_panel:
		# 決定錨點位置 (Anchor Position)
		var mouse_pos = get_viewport().get_mouse_position()
		var anchor_pos = mouse_pos
		
		# 如果是地圖實體，錨點使用實體的螢幕座標，避免面板擋住實體
		if not _is_ui_hovering and is_instance_valid(_current_entity):
			anchor_pos = _current_entity.get_global_transform_with_canvas().origin
			# print("[HoverInfoController] Using Entity Anchor: ", anchor_pos)
		
		var offset = offset_from_mouse
		if active_panel == _synergy_tooltip_instance:
			offset = synergy_tooltip_offset
		# 計算目標位置
		var target_pos = anchor_pos + offset
		
		# 邊界檢查
		var viewport_rect = get_viewport_rect()
		var panel_size = active_panel.get_combined_minimum_size()
		
		# 防止超出右邊界
		if target_pos.x + panel_size.x > viewport_rect.size.x:
			target_pos.x = anchor_pos.x - panel_size.x - offset.x
		# 防止超出下邊界
		if target_pos.y + panel_size.y > viewport_rect.size.y:
			target_pos.y = anchor_pos.y - panel_size.y - offset.y
			
		# 確保不會超出左上邊界
		target_pos.x = max(0, target_pos.x)
		target_pos.y = max(0, target_pos.y)
			
		active_panel.global_position = target_pos
		# 強制顯示 (備援)
		active_panel.show()
		# print("[HoverInfoController] Panel Position Updated to: ", target_pos, " | Visible: ", active_panel.visible)

func _hide_all() -> void:
	_is_ui_hovering = false
	_last_hovered_entity_id = -1
	_current_entity = null
	if _card_instance: _card_instance.visible = false
	if _trap_card_instance: _trap_card_instance.visible = false
	if _equip_panel_instance: _equip_panel_instance.visible = false
	if _skill_tooltip_instance: _skill_tooltip_instance.visible = false
	if _synergy_tooltip_instance: _synergy_tooltip_instance.visible = false

# 公開 API：讓 UI 元素直接顯示資料
func show_data_info(data: Resource, from_ui: bool = false) -> void:
	if data == null:
		_hide_all()
		return
		
	# 只有來自 UI 的請求才需要鎖定，地圖實體由 _process 自動隱藏
	if from_ui:
		_is_ui_hovering = true
	else:
		_is_ui_hovering = false
	
	# 目前只支援 EquipmentData
	var has_mods = data.get("modifiers") != null
	
	if has_mods: # 鴨子類型判斷是否為裝備
		if _equip_panel_instance and _equip_panel_instance.has_method("display_equipment"):
			_equip_panel_instance.display_equipment(data)
			_equip_panel_instance.visible = true
			# 核心修正：確保面板在顯示時其父容器（CanvasLayer）也是可見的
			var parent_layer = _equip_panel_instance.get_parent()
			if parent_layer is CanvasLayer:
				parent_layer.visible = true
				
			_equip_panel_instance.get_parent().move_child(_equip_panel_instance, -1)
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

func show_synergy_info(trait_id: String, from_ui: bool = false) -> void:
	print("[HoverInfoController] show_synergy_info trait_id=%s from_ui=%s" % [trait_id, from_ui])
	if trait_id.is_empty():
		_hide_all()
		return
	if from_ui:
		_is_ui_hovering = true
	else:
		_is_ui_hovering = false
	if _synergy_tooltip_instance and _synergy_tooltip_instance.has_method("setup_by_trait_id"):
		_synergy_tooltip_instance.setup_by_trait_id(trait_id)
		_synergy_tooltip_instance.visible = true
		_synergy_tooltip_instance.get_parent().move_child(_synergy_tooltip_instance, -1)
		_update_position()
		print("[HoverInfoController] Synergy tooltip shown")
	else:
		print("[HoverInfoController] SKIP: no _synergy_tooltip_instance or setup_by_trait_id")

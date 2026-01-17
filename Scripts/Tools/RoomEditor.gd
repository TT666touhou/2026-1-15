extends Node2D

# 編輯器主腳本

@onready var grid = $Grid
@onready var selector = $EditorGridSelector

# UI References - Left Panel
@onready var save_name_edit = $UI/HBoxContainer/LeftPanel/VBoxContainer/SaveNameEdit
@onready var difficulty_option = $UI/HBoxContainer/LeftPanel/VBoxContainer/DifficultyOption
@onready var edit_mode_option = $UI/HBoxContainer/LeftPanel/VBoxContainer/EditModeOption

# UI References - Inspector Panel (Center-Left)
@onready var inspector_panel = $UI/HBoxContainer/InspectorPanel
@onready var entity_list = $UI/HBoxContainer/InspectorPanel/VBoxContainer/EntityList
@onready var properties_panel = $UI/HBoxContainer/InspectorPanel/VBoxContainer/PropertiesPanel

# UI References - Right Panel
@onready var right_panel = $UI/HBoxContainer/RightPanel
@onready var ui_card_list = $UI/HBoxContainer/RightPanel/CardListScroll/CardList

# UI References - Inspector Properties
@onready var sb_hp = properties_panel.get_node("HBox_HP/SpinBox_HP")
@onready var sb_atk = properties_panel.get_node("HBox_ATK/SpinBox_ATK")
@onready var cb_boss = properties_panel.get_node("HBox_Boss/Check_IsBoss")
@onready var btn_reset = properties_panel.get_node("Btn_Reset")

# Movement SpinBoxes (3x3 Grid)
@onready var sb_nw = properties_panel.get_node("Grid_Move/Spin_NW")
@onready var sb_n = properties_panel.get_node("Grid_Move/Spin_N")
@onready var sb_ne = properties_panel.get_node("Grid_Move/Spin_NE")
@onready var sb_w = properties_panel.get_node("Grid_Move/Spin_W")
@onready var sb_e = properties_panel.get_node("Grid_Move/Spin_E")
@onready var sb_sw = properties_panel.get_node("Grid_Move/Spin_SW")
@onready var sb_s = properties_panel.get_node("Grid_Move/Spin_S")
@onready var sb_se = properties_panel.get_node("Grid_Move/Spin_SE")

var move_spinboxes: Dictionary = {}

enum EditMode {
	ENTITY,
	SPAWN
}

var current_mode: EditMode = EditMode.ENTITY
var active_card: Resource = null # 當前選中的 UnitCard (for placement)
var selected_instance: Node = null # 當前選中的實體 (for inspection)

var placed_entities: Dictionary = {} # { Node(Instance): Dictionary }
# Dictionary struct:
# {
#   "pos": Vector2i,
#   "card": UnitCard,
#   "footprint": FootprintData,
#   "instance": Node,
#   "overrides": Dictionary { "max_health": int, "attack_damage": int, "movement": Dictionary }
# }

var spawn_markers: Dictionary = {} # { Vector2i: Control(Marker) } - Key is cell coordinate
var spawn_points: Array[Vector2i] = [] # 存儲有序的 Spawn Points

const CARDS_DIR = "res://Resources/Cards/"
const ROOMS_DIR = "res://Resources/Rooms/"

func _ready() -> void:
	_load_card_list()
	_setup_ui()
	
	selector.cell_clicked.connect(_on_cell_clicked)
	
	# 初始化難度選項
	difficulty_option.clear()
	for key in RoomTemplate.RoomDifficulty.keys():
		difficulty_option.add_item(key)
		
	# 初始化編輯模式選項
	edit_mode_option.clear()
	edit_mode_option.add_item("Place Entities", EditMode.ENTITY)
	edit_mode_option.add_item("Set Spawns", EditMode.SPAWN)
	edit_mode_option.item_selected.connect(_on_mode_changed)
	
	# 初始化 Entity List
	entity_list.item_selected.connect(_on_entity_list_selected)
	
	# 初始化 Properties
	sb_hp.value_changed.connect(_on_prop_changed)
	sb_atk.value_changed.connect(_on_prop_changed)
	cb_boss.toggled.connect(_on_prop_changed)
	btn_reset.pressed.connect(_on_reset_props)
	
	# Map spinboxes to direction keys
	move_spinboxes = {
		"northwest": sb_nw,
		"north": sb_n,
		"northeast": sb_ne,
		"west": sb_w,
		"east": sb_e,
		"southwest": sb_sw,
		"south": sb_s,
		"southeast": sb_se
	}
	
	for key in move_spinboxes:
		move_spinboxes[key].value_changed.connect(_on_prop_changed)
	
	_update_ui_visibility()
	_update_inspector_visibility()

func _setup_ui() -> void:
	var save_btn = $UI/HBoxContainer/LeftPanel/VBoxContainer/SaveButton
	save_btn.pressed.connect(_on_save_pressed)
	
	var load_btn = $UI/HBoxContainer/LeftPanel/VBoxContainer/LoadButton
	load_btn.pressed.connect(_on_load_pressed)
	
	var clear_btn = $UI/HBoxContainer/LeftPanel/VBoxContainer/ClearButton
	clear_btn.pressed.connect(_clear_all)

func _on_mode_changed(index: int) -> void:
	current_mode = index as EditMode
	_update_ui_visibility()
	
	# 切換模式時清除預覽與選取
	selector.set_preview_card(null)
	active_card = null
	_deselect_entity()
	
	print("Switched to mode: ", EditMode.keys()[current_mode])

func _update_ui_visibility() -> void:
	if current_mode == EditMode.ENTITY:
		right_panel.visible = true
		inspector_panel.visible = true
	else:
		right_panel.visible = false
		inspector_panel.visible = false

func _load_card_list() -> void:
	var dir = DirAccess.open(CARDS_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if !dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
				var card_res = load(CARDS_DIR + file_name)
				if card_res is BaseCard: # 確保是 BaseCard 或其子類
					_create_card_button(card_res)
			file_name = dir.get_next()
	else:
		push_error("Failed to open cards directory: " + CARDS_DIR)

func _create_card_button(card: BaseCard) -> void:
	var btn = Button.new()
	btn.text = card.display_name if card.display_name else card.card_name
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.pressed.connect(func(): _select_card(card))
	ui_card_list.add_child(btn)

func _select_card(card: BaseCard) -> void:
	active_card = card
	selector.set_preview_card(card)
	_deselect_entity()
	print("Selected card: ", card.card_name)

func _on_cell_clicked(cell: Vector2i, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_LEFT:
		match current_mode:
			EditMode.ENTITY:
				var clicked_instance = _get_instance_at(cell)
				if clicked_instance:
					_select_entity(clicked_instance)
				else:
					if active_card:
						_place_entity(cell, active_card)
					else:
						_deselect_entity()
						
			EditMode.SPAWN:
				_add_spawn_point(cell)
				
	elif button_index == MOUSE_BUTTON_RIGHT:
		match current_mode:
			EditMode.ENTITY:
				_remove_entity_at(cell)
			EditMode.SPAWN:
				_remove_spawn_point_at(cell)

# --- Spawn Logic ---

func _add_spawn_point(cell: Vector2i) -> void:
	if cell in spawn_points:
		return
	if !grid.is_in_bounds(cell):
		return
		
	spawn_points.append(cell)
	
	# Visual Marker
	var marker = ColorRect.new()
	marker.custom_minimum_size = Vector2(16, 16)
	marker.size = Vector2(16, 16)
	marker.color = Color(0, 1, 0, 0.5) # Semi-transparent Green
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Entities.add_child(marker)
	
	if grid.has_method("grid_to_world"):
		marker.global_position = grid.grid_to_world(cell)
	else:
		marker.global_position = Vector2(cell) * 16
		
	spawn_markers[cell] = marker
	print("Added spawn point at ", cell)

func _remove_spawn_point_at(cell: Vector2i) -> void:
	if cell in spawn_points:
		spawn_points.erase(cell)
		if spawn_markers.has(cell):
			spawn_markers[cell].queue_free()
			spawn_markers.erase(cell)
		print("Removed spawn point at ", cell)
	
func _clear_spawns() -> void:
	spawn_points.clear()
	for cell in spawn_markers:
		spawn_markers[cell].queue_free()
	spawn_markers.clear()

# --- Entity Logic ---

func _place_entity(cell: Vector2i, card: BaseCard, overrides: Dictionary = {}) -> void:
	var footprint = card.get("footprint_data")
	var cells_to_check = [cell]
	if footprint:
		cells_to_check.clear()
		for offset in footprint.occupied_cells:
			cells_to_check.append(cell + offset)
			
	for c in cells_to_check:
		if c in spawn_points:
			print("Cannot place entity: Overlaps with spawn point")
			return
		if !grid.is_in_bounds(c):
			print("Out of bounds!")
			return
		if _is_cell_occupied(c):
			print("Cell occupied: ", c)
			return
	
	# Determine scene to instantiate
	var scene_to_spawn = null
	if "unit_scene" in card: scene_to_spawn = card.get("unit_scene")
	elif "building_scene" in card: scene_to_spawn = card.get("building_scene")
	elif "prop_scene" in card: scene_to_spawn = card.get("prop_scene")
	elif "trap_scene" in card: scene_to_spawn = card.get("trap_scene")

	if scene_to_spawn:
		var instance = scene_to_spawn.instantiate()
		$Entities.add_child(instance)
		
		if instance.has_method("set_grid_position"):
			instance.grid = grid
			instance.grid_position = cell
			
			if instance.has_method("setup_trap"):
				instance.setup_trap(card)
			
			instance.global_position = grid.grid_to_world_center_footprint(cell, footprint)
			
			placed_entities[instance] = {
				"pos": cell,
				"card": card,
				"footprint": footprint,
				"instance": instance,
				"overrides": overrides.duplicate()
			}
			
			if instance.has_method("apply_overrides") and not overrides.is_empty():
				instance.apply_overrides(overrides)
			
			_refresh_entity_list()
			_select_entity(instance)
			
		print("Placed ", card.card_name, " at ", cell)

func _remove_entity_at(cell: Vector2i) -> void:
	var target_instance = _get_instance_at(cell)
	if target_instance:
		if target_instance == selected_instance:
			_deselect_entity()
		
		# 如果該實體正在高亮，也一併處理 (安全起見)
		if target_instance.has_method("set_editor_highlight"):
			target_instance.set_editor_highlight(false)
			
		target_instance.queue_free()
		placed_entities.erase(target_instance)
		_refresh_entity_list()
		print("Removed entity at ", cell)

func _is_cell_occupied(cell: Vector2i) -> bool:
	return _get_instance_at(cell) != null

func _get_instance_at(cell: Vector2i) -> Node:
	for instance in placed_entities:
		var data = placed_entities[instance]
		var pos = data.pos
		var fp = data.footprint
		
		var cells = []
		if fp:
			for offset in fp.occupied_cells:
				cells.append(pos + offset)
		else:
			cells.append(pos)
			
		if cell in cells:
			return instance
	return null

func _clear_all() -> void:
	for instance in placed_entities:
		instance.queue_free()
	placed_entities.clear()
	_clear_spawns()
	_refresh_entity_list()
	_deselect_entity()

# --- Selection & Inspector Logic ---

func _refresh_entity_list() -> void:
	entity_list.clear()
	var instances = placed_entities.keys()
	instances.sort_custom(func(a, b):
		var pos_a = placed_entities[a].pos
		var pos_b = placed_entities[b].pos
		if pos_a.y != pos_b.y: return pos_a.y < pos_b.y
		return pos_a.x < pos_b.x
	)
	
	for instance in instances:
		var data = placed_entities[instance]
		var card_name = data.card.card_name
		var pos_str = str(data.pos)
		var text = "%s %s" % [card_name, pos_str]
		var idx = entity_list.add_item(text)
		entity_list.set_item_metadata(idx, instance)
		
		if instance == selected_instance:
			entity_list.select(idx)

func _on_entity_list_selected(index: int) -> void:
	var instance = entity_list.get_item_metadata(index)
	_select_entity(instance)

func _select_entity(instance: Node) -> void:
	# 先清除舊選取的高亮
	if selected_instance and is_instance_valid(selected_instance):
		if selected_instance.has_method("set_editor_highlight"):
			selected_instance.set_editor_highlight(false)

	selected_instance = instance
	active_card = null
	selector.set_preview_card(null)
	
	# 執行新選取的高亮
	if selected_instance and is_instance_valid(selected_instance):
		if selected_instance.has_method("set_editor_highlight"):
			selected_instance.set_editor_highlight(true)
	
	for i in range(entity_list.item_count):
		if entity_list.get_item_metadata(i) == instance:
			if not entity_list.is_selected(i):
				entity_list.select(i)
			break
	
	_update_inspector_visibility()
	_populate_inspector()

func _deselect_entity() -> void:
	if selected_instance and is_instance_valid(selected_instance):
		if selected_instance.has_method("set_editor_highlight"):
			selected_instance.set_editor_highlight(false)
			
	selected_instance = null
	entity_list.deselect_all()
	_update_inspector_visibility()

func _update_inspector_visibility() -> void:
	properties_panel.visible = (selected_instance != null)

func _populate_inspector() -> void:
	if !selected_instance: return
	
	var data = placed_entities[selected_instance]
	var card = data.card
	var overrides = data.overrides
	
	_block_prop_signals(true)
	
	# HP
	var card_hp = card.get("max_health")
	if overrides.has("max_health"):
		sb_hp.value = overrides["max_health"]
	else:
		sb_hp.value = float(card_hp) if card_hp != null else 100.0
		
	# ATK
	var card_atk = card.get("attack_damage")
	if overrides.has("attack_damage"):
		sb_atk.value = overrides["attack_damage"]
	else:
		sb_atk.value = float(card_atk) if card_atk != null else 0.0
		
	# Boss
	cb_boss.button_pressed = overrides.get("is_boss", false)
		
	# Movement
	var move_data = overrides.get("movement", {})
	var base_move_data = card.get("movement_range_data")
	
	for key in move_spinboxes:
		if move_data.has(key):
			move_spinboxes[key].value = move_data[key]
		elif base_move_data:
			# Read from resource
			move_spinboxes[key].value = base_move_data.get(key)
		else:
			move_spinboxes[key].value = 2 # Default Unlimited
		
	_block_prop_signals(false)

func _block_prop_signals(block: bool) -> void:
	sb_hp.set_block_signals(block)
	sb_atk.set_block_signals(block)
	cb_boss.set_block_signals(block)
	for key in move_spinboxes:
		move_spinboxes[key].set_block_signals(block)

func _on_prop_changed(_val: float) -> void:
	if !selected_instance: return
	
	var data = placed_entities[selected_instance]
	var overrides = data.overrides
	var card = data.card
	
	var new_hp = int(sb_hp.value)
	var new_atk = int(sb_atk.value)
	
	# HP
	var card_hp = card.get("max_health")
	var base_hp = int(float(card_hp) if card_hp != null else 100.0)
	if new_hp != base_hp:
		overrides["max_health"] = new_hp
	else:
		overrides.erase("max_health")
		
	# ATK
	var card_atk = card.get("attack_damage")
	var base_atk = int(float(card_atk) if card_atk != null else 0.0)
	if new_atk != base_atk:
		overrides["attack_damage"] = new_atk
	else:
		overrides.erase("attack_damage")
		
	# Boss
	var is_boss_enabled = cb_boss.button_pressed
	if is_boss_enabled:
		overrides["is_boss"] = true
	else:
		overrides.erase("is_boss")
		
	# Movement
	var current_move_dict = {}
	var base_data = card.get("movement_range_data")
	var has_diff = false
	
	for key in move_spinboxes:
		var val = int(move_spinboxes[key].value)
		current_move_dict[key] = val
		
		# Check difference from base
		var base_val = 2 # Default unlimited
		if base_data:
			base_val = base_data.get(key)
		
		if val != base_val:
			has_diff = true
			
	if has_diff:
		overrides["movement"] = current_move_dict
	else:
		overrides.erase("movement")
		
	if selected_instance.has_method("apply_overrides"):
		selected_instance.apply_overrides(overrides)

func _on_reset_props() -> void:
	if !selected_instance: return
	var data = placed_entities[selected_instance]
	data.overrides.clear()
	_populate_inspector()
	
	var cd = CharacterData.create(data.card)
	if selected_instance.has_method("setup_character"):
		selected_instance.setup_character(cd)
	# Re-apply empty overrides to reset everything
	if selected_instance.has_method("apply_overrides"):
		selected_instance.apply_overrides({})

# --- Save / Load ---

func _on_save_pressed() -> void:
	var file_name = save_name_edit.text
	if file_name.strip_edges() == "":
		print("Please enter a file name")
		return
		
	if !file_name.ends_with(".tres"):
		file_name += ".tres"
		
	var template = RoomTemplate.new()
	template.room_name = file_name.get_basename()
	template.difficulty = difficulty_option.selected
	
	# Save Entities
	for instance in placed_entities:
		var data = placed_entities[instance]
		template.add_room_entity(data.pos, data.card.resource_path, data.overrides)
		
	# Save Spawns
	template.player_spawn_points = spawn_points.duplicate()
		
	var err = ResourceSaver.save(template, ROOMS_DIR + file_name)
	if err == OK:
		print("Saved room to ", ROOMS_DIR + file_name)
	else:
		push_error("Failed to save room: " + str(err))

func _on_load_pressed() -> void:
	var file_name = save_name_edit.text
	if file_name.strip_edges() == "":
		print("Please enter a file name to load")
		return
		
	if !file_name.ends_with(".tres"):
		file_name += ".tres"
		
	var path = ROOMS_DIR + file_name
	if !FileAccess.file_exists(path):
		print("File not found: ", path)
		return
		
	var template = load(path) as RoomTemplate
	if !template:
		print("Failed to load template")
		return
		
	_clear_all()
	
	difficulty_option.selected = template.difficulty
	
	for entity_data in template.entities:
		var pos = entity_data.pos
		var card_path = entity_data.get("card_path", "")
		var scene_path = entity_data.get("scene_path", "")
		var overrides = entity_data.get("overrides", {})
			
		if card_path != "":
			var card = load(card_path)
			if card:
				_place_entity(pos, card, overrides)
		elif scene_path != "":
			print("[RoomEditor] Found entity with scene_path but no card: ", scene_path, " at ", pos, ". Skipping editor placement.")
			
	if template.player_spawn_points:
		for pt in template.player_spawn_points:
			_add_spawn_point(pt)
			
	print("Loaded room: ", template.room_name)

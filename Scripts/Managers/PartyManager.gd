extends Node

# Autoload name: PartyManager

signal party_updated

const MAX_PARTY_SIZE: int = 3

var party_members: Array[CharacterData] = []
var leaders: Array[CharacterData] = [] # Current logic: leaders[0] is party_members[0]

var deployment_ui_scene: PackedScene = preload("res://Scenes/UI/DeploymentUI.tscn")
var _deployment_ui_instance: DeploymentUI = null

func _ready() -> void:
	# Initial recruitment for testing (Phase 1)
	_recruit_starters()

func _recruit_starters() -> void:
	if party_members.is_empty():
		# Load starter units
		var u1 = load("res://Resources/Cards/Unit_001.tres")
		if u1: recruit_member(u1)
		
		var u2 = load("res://Resources/Cards/Unit_002.tres")
		if u2: recruit_member(u2)
		
		var u3 = load("res://Resources/Cards/Unit_003.tres")
		if u3: recruit_member(u3)

func recruit_member(unit_card: UnitCard) -> bool:
	if party_members.size() >= MAX_PARTY_SIZE:
		return false
	
	var data = CharacterData.create(unit_card)
	party_members.append(data)
	
	_update_leaders()
	
	party_updated.emit()
	print("[PartyManager] Recruited: ", unit_card.display_name)
	return true

func _update_leaders() -> void:
	leaders.clear()
	if not party_members.is_empty():
		# Default: The first member is the leader
		leaders.append(party_members[0])
		
	# Trigger stat recalculation for ALL party members
	_recalculate_party_stats()

func _recalculate_party_stats() -> void:
	for member in party_members:
		member.recalculate_stats()

func get_members() -> Array[CharacterData]:
	return party_members

func get_leaders() -> Array[CharacterData]:
	return leaders

func get_active_traits() -> Array[TraitData]:
	var traits: Array[TraitData] = []
	for leader in leaders:
		if leader.character_trait != null:
			traits.append(leader.character_trait)
	return traits

# Move member to specific index (Insert)
func move_member(member: CharacterData, to_index: int) -> void:
	var current_idx = party_members.find(member)
	if current_idx == -1:
		return
		
	if to_index < 0: to_index = 0
	if to_index > party_members.size(): to_index = party_members.size()
	
	# Remove first
	var removed = party_members.pop_at(current_idx)
	
	# Adjust index if needed (if removed item was before insertion point)
	if current_idx < to_index:
		to_index -= 1
		
	# Insert
	party_members.insert(to_index, removed)
	
	_update_leaders() # This will trigger recalculation
	party_updated.emit()
	print("[PartyManager] Moved member: %d -> %d" % [current_idx, to_index])

# --- Deployment Logic ---

func start_deployment() -> void:
	print("[PartyManager] Starting Deployment Phase")
	if _deployment_ui_instance == null or not is_instance_valid(_deployment_ui_instance):
		# Try to find existing UI layer
		var ui_layer = get_tree().current_scene.get_node_or_null("UI")
		if ui_layer == null:
			# If no UI layer, look for any CanvasLayer
			for child in get_tree().current_scene.get_children():
				if child is CanvasLayer:
					ui_layer = child
					break
		
		if ui_layer == null:
			# Create one if totally missing
			ui_layer = CanvasLayer.new()
			ui_layer.name = "UI"
			get_tree().current_scene.add_child(ui_layer)
			
		_deployment_ui_instance = deployment_ui_scene.instantiate()
		ui_layer.add_child(_deployment_ui_instance)
	
	_deployment_ui_instance.visible = true
	_deployment_ui_instance.initialize_party(party_members)

	# Hide global top bar if it exists to avoid overlap
	var top_bar = get_tree().current_scene.find_child("MainTopBar", true, false)
	if top_bar:
		top_bar.visible = false

func end_deployment() -> void:
	print("[PartyManager] Ending Deployment Phase")
	if _deployment_ui_instance and is_instance_valid(_deployment_ui_instance):
		_deployment_ui_instance.visible = false
	
	# Restore global top bar
	var top_bar = get_tree().current_scene.find_child("MainTopBar", true, false)
	if top_bar:
		top_bar.visible = true
	
	if TurnManager:
		TurnManager.end_deployment()

func can_place_member(data: CharacterData, cell: Vector2i) -> bool:
	var grid = get_tree().get_first_node_in_group("grid")
	if grid == null: return false
	
	var footprint = data.unit_def.footprint_data
	if footprint == null: return false
	
	if not grid.has_method("is_footprint_occupied") or not grid.has_method("is_in_bounds"):
		return false
		
	if not grid.is_in_bounds(cell):
		return false
		
	# Check all cells in footprint for bounds
	var cells = grid.get_cells_in_footprint(cell, footprint)
	for c in cells:
		if not grid.is_in_bounds(c):
			return false
	
	if grid.is_footprint_occupied(cell, footprint):
		return false
		
	return true

func spawn_party_member(data: CharacterData, cell: Vector2i) -> bool:
	if not can_place_member(data, cell):
		return false
		
	var grid = get_tree().get_first_node_in_group("grid")
	var scene_root = get_tree().current_scene
	
	# Instantiate
	var instance = data.unit_def.unit_scene.instantiate()
	var grid_entity = instance as GridEntity
	if grid_entity == null: return false
	
	# Setup GridEntity
	grid_entity.footprint_data = data.unit_def.footprint_data
	grid_entity.grid_position = cell
	
	# Add to Scene
	var units_layer = scene_root.get_node_or_null("Entities/UnitsLayer")
	if units_layer == null:
		units_layer = scene_root.get_node_or_null("UnitsLayer")
		
	if units_layer:
		units_layer.add_child(instance)
	else:
		scene_root.add_child(instance)
		
	# Set Position
	instance.global_position = grid.grid_to_world_center_footprint(cell, grid_entity.footprint_data)
	
	# Apply Data (Static then Runtime)
	var card_provider = instance.get_node_or_null("CardProvider")
	if card_provider:
		# CardProvider.set_card_and_apply supports Resource (UnitCard)
		card_provider.set_card_and_apply(data.unit_def)
	
	# Inject Runtime Data (HP, Combo, etc)
	grid_entity.setup_character(data)
	
	print("[PartyManager] Deployed ", data.unit_def.display_name, " at ", cell)
	
	# Update UI to show deployed status
	if _deployment_ui_instance and is_instance_valid(_deployment_ui_instance):
		# TODO: update specific card status
		pass
		
	return true

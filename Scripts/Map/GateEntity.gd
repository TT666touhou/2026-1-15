extends Node2D
class_name GateEntity

@export var grid_position: Vector2i = Vector2i.ZERO
@export var is_open: bool = true
@export var next_room_name: String = ""

func _ready() -> void:
	add_to_group("gates")
	
	# Register to DungeonManager
	var dm = get_node_or_null("/root/DungeonManager")
	if dm and dm.has_method("register_gate"):
		dm.register_gate(self)
	
	# Initial Position Update
	var grid = get_tree().get_first_node_in_group("grid")
	if grid:
		position = grid.grid_to_world_center(grid_position)

func _exit_tree() -> void:
	# Unregister
	var dm = get_node_or_null("/root/DungeonManager")
	if dm and dm.has_method("unregister_gate"):
		dm.unregister_gate(self)

func set_grid_position(pos: Vector2i) -> void:
	# Update old registration if tracking by pos (DungeonManager handles this via object reference usually)
	# But if we key by pos, we might need to update.
	# For now, let's assume we just update visual position.
	grid_position = pos
	var grid = get_tree().get_first_node_in_group("grid")
	if grid:
		position = grid.grid_to_world_center(pos)

func on_entity_entered(entity: Node) -> void:
	if not is_open:
		return
		
	print("[GateEntity] Triggered by ", entity.name)
	# Call DungeonManager to handle room switch
	var dm = get_node_or_null("/root/DungeonManager")
	if dm and dm.has_method("on_gate_entered"):
		dm.on_gate_entered(self)

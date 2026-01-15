extends Button
class_name DebugStatusButton

@export var status_resource: StatusDefinition

func _ready() -> void:
	pressed.connect(_on_pressed)
	focus_mode = Control.FOCUS_NONE
	if status_resource:
		text = "+ " + status_resource.id
	
func _on_pressed() -> void:
	if not status_resource:
		push_warning("No status resource assigned to DebugStatusButton")
		return
		
	var entities = get_tree().get_nodes_in_group("grid_entities")
	var count = 0
	
	for entity in entities:
		if entity is GridEntity:
			var status_mgr = entity.get_node_or_null("StatusManager")
			if status_mgr and status_mgr.has_method("apply_status"):
				status_mgr.apply_status(status_resource)
				count += 1
				
	print("[Debug] Applied status '%s' to %d entities." % [status_resource.id, count])


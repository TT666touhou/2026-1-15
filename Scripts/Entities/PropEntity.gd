extends GridEntity
class_name PropEntity

func _ready() -> void:
	# GridEntity handles grid registration in its _ready()
	super._ready()
	
	# Props typically don't show combat UI elements
	if combo_indicator:
		combo_indicator.visible = false
		
	# Ensure props are recognizable by group if needed
	add_to_group("props")
	
	print("[PropEntity] Initialized at ", grid_position)

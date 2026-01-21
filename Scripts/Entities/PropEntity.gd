extends GridEntity
class_name PropEntity

func _ready() -> void:
	# GridEntity handles grid registration in its _ready()
	super._ready()
	z_index = 1
	
	# Ensure props are recognizable by group if needed
	add_to_group("props")
	
	print("[PropEntity] Initialized at ", grid_position)

func should_register_combo() -> bool:
	"""裝飾物/障礙物不列入連擊計數"""
	return false

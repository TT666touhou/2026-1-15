extends HBoxContainer

@onready var room_name_edit: LineEdit = $LineEdit
@onready var load_button: Button = $Button

func _ready() -> void:
	load_button.pressed.connect(_on_load_pressed)
	room_name_edit.text_submitted.connect(_on_text_submitted)

func _on_text_submitted(_new_text: String) -> void:
	_on_load_pressed()

func _on_load_pressed() -> void:
	var room_name = room_name_edit.text.strip_edges()
	if room_name.is_empty():
		print("[DebugRoomLoader] Please enter a room name")
		return
		
	if DungeonManager:
		await DungeonManager.load_room_by_name(room_name)
	else:
		push_error("[DebugRoomLoader] DungeonManager not found")


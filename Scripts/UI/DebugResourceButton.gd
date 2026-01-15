extends Button

func _ready() -> void:
	pressed.connect(_on_pressed)
	text = "+1000 Res"
	focus_mode = Control.FOCUS_NONE

func _on_pressed() -> void:
	var ledger = get_node_or_null("/root/PlayerResourceLedger")
	if ledger:
		ledger.add_resource("gold", 1000)
		ledger.add_resource("soul", 1000)
		print("[Debug] Added 1000 Gold and Soul")
	else:
		push_error("PlayerResourceLedger not found!")


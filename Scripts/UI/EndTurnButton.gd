extends Button

func _ready() -> void:
	pressed.connect(_on_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_on_pressed()

func _on_pressed() -> void:
	if TurnManager:
		TurnManager.advance_turn()


extends TextureButton

func _ready() -> void:
	pressed.connect(_on_pressed)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle()

func _on_pressed() -> void:
	_toggle()

func _toggle() -> void:
	# 使用絕對路徑存取 Autoload，避免編輯器識別問題
	var settings = get_node_or_null("/root/GlobalSettings")
	if settings:
		settings.toggle_pause()
	else:
		push_error("GlobalSettings not found!")


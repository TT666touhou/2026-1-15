extends CanvasLayer

@onready var resolution_opt = %ResolutionOption
@onready var fullscreen_check = %FullscreenCheck
@onready var vsync_check = %VSyncCheck
@onready var master_slider = %MasterSlider
@onready var music_slider = %MusicSlider
@onready var sfx_slider = %SFXSlider
@onready var resume_btn = %ResumeButton
@onready var quit_btn = %QuitButton

var _global_settings: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # 確保暫停時可以接收輸入
	_global_settings = get_node("/root/GlobalSettings")
	
	# 初始化 UI 狀態
	setup_ui()
	
	# 連接信號
	resolution_opt.item_selected.connect(_on_resolution_selected)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vsync_check.toggled.connect(_on_vsync_toggled)
	
	if _global_settings:
		master_slider.value_changed.connect(func(v): _global_settings.set_bus_volume("Master", v))
		music_slider.value_changed.connect(func(v): _global_settings.set_bus_volume("Music", v))
		sfx_slider.value_changed.connect(func(v): _global_settings.set_bus_volume("SFX", v))
	
	resume_btn.pressed.connect(_on_resume_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _global_settings:
			_global_settings.toggle_pause()
		get_viewport().set_input_as_handled()

func setup_ui() -> void:
	if not _global_settings: return
	
	var vid = _global_settings.get_current_video_settings()
	var aud = _global_settings.get_current_audio_settings()
	
	# 設定解析度選項
	resolution_opt.clear()
	var res_options = _global_settings.get_resolution_options()
	for i in range(res_options.size()):
		resolution_opt.add_item(res_options[i])
	resolution_opt.selected = vid["resolution_index"]
	
	# 設定其他 Video 控件
	fullscreen_check.button_pressed = vid["fullscreen"]
	vsync_check.button_pressed = vid["vsync"]
	
	# 設定 Audio 控件
	master_slider.value = aud.get("Master", 1.0)
	music_slider.value = aud.get("Music", 1.0)
	sfx_slider.value = aud.get("SFX", 1.0)

func _on_resolution_selected(index: int) -> void:
	if _global_settings:
		_global_settings.set_resolution_index(index)

func _on_fullscreen_toggled(toggled: bool) -> void:
	if _global_settings:
		_global_settings.set_fullscreen(toggled)

func _on_vsync_toggled(toggled: bool) -> void:
	if _global_settings:
		_global_settings.set_vsync(toggled)

func _on_resume_pressed() -> void:
	if _global_settings:
		_global_settings.toggle_pause()

func _on_quit_pressed() -> void:
	get_tree().quit()

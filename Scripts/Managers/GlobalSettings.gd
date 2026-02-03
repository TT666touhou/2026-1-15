extends Node

# 信號
signal settings_changed
signal game_paused(is_paused: bool)

# 常數
const SAVE_PATH = "user://settings.cfg"
const RESOLUTIONS = {
	"1280x720": Vector2i(1280, 720),
	"1920x1080": Vector2i(1920, 1080),
	"2560x1440": Vector2i(2560, 1440),
	"3840x2160": Vector2i(3840, 2160)
}

# 當前設定數據
var _config_data = {
	"video": {
		"resolution_index": 1, # 預設 1920x1080
		"fullscreen": false,
		"vsync": true
	},
	"audio": {
		"Master": 0.8,
		"Music": 1.0,
		"SFX": 1.0
	},
	"gameplay": {
		"use_keyboard_movement": true,
		"use_simplified_stats_ui": true,
		"auto_collect_coins": false
	}
}

# 暫停選單場景路徑
const PAUSE_MENU_PATH = "res://Scenes/UI/PauseMenu.tscn"
var _pause_menu_instance: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # 確保暫停時仍能運作
	load_settings()
	apply_settings()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("settings_open"):
		toggle_pause()

func toggle_pause() -> void:
	var tree = get_tree()
	tree.paused = not tree.paused
	
	if tree.paused:
		_open_pause_menu()
	else:
		_close_pause_menu()
	
	game_paused.emit(tree.paused)

func _open_pause_menu() -> void:
	if _pause_menu_instance == null:
		var scene = load(PAUSE_MENU_PATH)
		if scene:
			_pause_menu_instance = scene.instantiate()
			get_tree().root.add_child(_pause_menu_instance)
	
	if _pause_menu_instance:
		_pause_menu_instance.show()
		# 嘗試呼叫 UI 的 setup 方法以同步顯示
		if _pause_menu_instance.has_method("setup_ui"):
			_pause_menu_instance.setup_ui()

func _close_pause_menu() -> void:
	if _pause_menu_instance:
		_pause_menu_instance.hide()

# --- 設定操作 API ---

func set_resolution_index(index: int) -> void:
	_config_data["video"]["resolution_index"] = index
	apply_video_settings()
	save_settings()
	settings_changed.emit()

func set_fullscreen(is_fullscreen: bool) -> void:
	_config_data["video"]["fullscreen"] = is_fullscreen
	apply_video_settings()
	save_settings()
	settings_changed.emit()

func set_vsync(is_vsync: bool) -> void:
	_config_data["video"]["vsync"] = is_vsync
	apply_video_settings()
	save_settings()
	settings_changed.emit()

func set_bus_volume(bus_name: String, linear_value: float) -> void:
	if _config_data["audio"].has(bus_name):
		_config_data["audio"][bus_name] = clamp(linear_value, 0.0, 1.0)
		apply_audio_settings()
		save_settings()
		settings_changed.emit()

func set_use_simplified_stats_ui(value: bool) -> void:
	_config_data["gameplay"]["use_simplified_stats_ui"] = value
	save_settings()
	settings_changed.emit()

func get_use_simplified_stats_ui() -> bool:
	return _config_data["gameplay"].get("use_simplified_stats_ui", false)

func set_auto_collect_coins(value: bool) -> void:
	_config_data["gameplay"]["auto_collect_coins"] = value
	save_settings()
	settings_changed.emit()

func get_auto_collect_coins() -> bool:
	return _config_data["gameplay"].get("auto_collect_coins", true)

# --- 應用設定邏輯 ---

func apply_settings() -> void:
	apply_video_settings()
	apply_audio_settings()

func apply_video_settings() -> void:
	var res_keys = RESOLUTIONS.keys()
	var idx = _config_data["video"]["resolution_index"]
	if idx < 0 or idx >= res_keys.size():
		idx = 1 # Fallback to 1920x1080
	
	var res_key = res_keys[idx]
	var target_size = RESOLUTIONS[res_key]
	
	var win = get_window()
	if not win:
		return
	
	# 檢測是否在嵌入式環境 (例如 Godot 編輯器內)
	# 雖然沒有直接的 API，但我們可以檢查是否在編輯器中運行且沒有全螢幕
	# 為了安全起見，如果 OS 有 "editor" 特性，我們避免移動視窗位置，這能修復 "Embedded window can't be moved"
	var is_embedded = OS.has_feature("editor")

	# 設定全螢幕
	if _config_data["video"]["fullscreen"]:
		if win.mode != Window.MODE_FULLSCREEN:
			win.mode = Window.MODE_FULLSCREEN
	else:
		if win.mode != Window.MODE_WINDOWED:
			win.mode = Window.MODE_WINDOWED
		
		# 設定大小
		# 檢查是否已經是該大小，避免重複設定
		if win.size != target_size:
			win.size = target_size
		
		# 置中視窗 (僅在非嵌入式環境下執行)
		if not is_embedded:
			# 取得當前螢幕尺寸以計算置中位置
			var current_screen = win.current_screen
			var screen_size = DisplayServer.screen_get_size(current_screen)
			var target_pos = screen_size / 2 - target_size / 2
			
			# 嘗試設定位置 (如果位置不同)
			if win.position != target_pos:
				win.position = target_pos

	# 設定 VSync
	var vsync_mode = DisplayServer.VSYNC_ENABLED if _config_data["video"]["vsync"] else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)

func apply_audio_settings() -> void:
	for bus_name in _config_data["audio"].keys():
		var bus_idx = AudioServer.get_bus_index(bus_name)
		if bus_idx != -1:
			var linear_vol = _config_data["audio"][bus_name]
			var db_vol = linear_to_db(linear_vol)
			AudioServer.set_bus_volume_db(bus_idx, db_vol)
			AudioServer.set_bus_mute(bus_idx, linear_vol <= 0.001)

# --- 持久化邏輯 ---

func save_settings() -> void:
	var config = ConfigFile.new()
	
	for section in _config_data.keys():
		for key in _config_data[section].keys():
			config.set_value(section, key, _config_data[section][key])
	
	config.save(SAVE_PATH)

func load_settings() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return # 使用預設值
	
	for section in _config_data.keys():
		if config.has_section(section):
			for key in _config_data[section].keys():
				if config.has_section_key(section, key):
					_config_data[section][key] = config.get_value(section, key)

# --- Helper ---
func get_current_video_settings() -> Dictionary:
	return _config_data["video"]

func get_current_audio_settings() -> Dictionary:
	return _config_data["audio"]

func get_resolution_options() -> Array:
	return RESOLUTIONS.keys()

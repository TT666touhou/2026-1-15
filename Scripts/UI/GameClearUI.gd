extends Control

## 通關 UI 腳本
## 處理重新開始遊戲與退出邏輯

@onready var title_label: Label = %TitleLabel
@onready var content_label: Label = %ContentLabel
@onready var restart_button: Button = %RestartButton

func _ready() -> void:
	# 初始動畫：從透明漸顯
	modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	
	# 設定焦點以便鍵盤操作
	restart_button.grab_focus()

func _on_restart_button_pressed() -> void:
	print("[GameClearUI] Restarting game...")
	# 重新載入 T001
	var dm = get_node_or_null("/root/DungeonManager")
	if dm:
		dm.load_room_by_name("T001")
	
	# 清理 UI
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.finished.connect(queue_free)

func _on_quit_button_pressed() -> void:
	get_tree().quit()

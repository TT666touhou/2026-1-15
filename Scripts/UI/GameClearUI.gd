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
	
	# 1. 重置所有全域管理器狀態
	if PartyManager:
		PartyManager.reset_party()
	
	if TurnManager:
		TurnManager.reset_state()
	
	if DungeonManager:
		DungeonManager.reset_state()
	
	var ledger = get_tree().get_first_node_in_group("ledger")
	if ledger and ledger.has_method("reset"):
		ledger.reset()
	
	# 2. 重新載入當前場景 (World.tscn)
	get_tree().paused = false # 確保取消暫停
	get_tree().reload_current_scene()
	
	# 3. 銷毀自己
	queue_free()

func _on_quit_button_pressed() -> void:
	get_tree().quit()

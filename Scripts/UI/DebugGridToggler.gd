extends VBoxContainer

@onready var grid_buttons: Array[Button] = [
	$BtnGrid1,
	$BtnGrid2,
	$BtnGrid3
]
@onready var btn_kill_all: Button = $BtnKillAll

# 定義這三個額外格子的位置 (假設地圖寬度為7，索引0-6，則右側為 x=7)
# 位置設為右側的上、中、下
var extra_cells: Array[Vector2i] = [
	Vector2i(7, 1), # 上
	Vector2i(7, 3), # 中
	Vector2i(7, 5)  # 下
]

func _ready() -> void:
	# 初始隱藏工作現在交給 MapLoader 和 DungeonManager 處理
	# 我們只需要配置按鈕

	for i in range(grid_buttons.size()):
		var btn = grid_buttons[i]
		btn.toggled.connect(_on_grid_toggled.bind(i))
		btn.text = "Gate Grid %d (OFF)" % (i + 1)
		
		# 初始狀態假設為關閉，但不呼叫 update，避免覆蓋 DungeonManager 的初始化
		# 如果需要強制同步，可以呼叫，但這可能導致重複執行
		# 簡單起見，我們讓按鈕保持默認 OFF，而不觸發邏輯
	
	if btn_kill_all:
		btn_kill_all.pressed.connect(_on_kill_all_pressed)
		
	# Dynamically add Test Recycle Button
	var btn_recycle = Button.new()
	btn_recycle.text = "Test Recycle Anim"
	add_child(btn_recycle)
	btn_recycle.pressed.connect(_on_test_recycle_pressed)
	
	# Dynamically add Test Gate Button
	var btn_gate = Button.new()
	btn_gate.text = "Test Gate Anim"
	add_child(btn_gate)
	btn_gate.pressed.connect(_on_test_gate_pressed)

func _on_grid_toggled(toggled_on: bool, index: int) -> void:
	var btn = grid_buttons[index]
	btn.text = "Gate Grid %d (%s)" % [index + 1, "ON" if toggled_on else "OFF"]
	
	# 委託給 DungeonManager
	if DungeonManager:
		DungeonManager.set_gate_active(index, toggled_on)
	else:
		push_error("[DebugGridToggler] DungeonManager not found")

func _on_kill_all_pressed() -> void:
	print("[DebugGridToggler] Kill All Enemies pressed")
	if not BoardManager:
		push_error("[DebugGridToggler] BoardManager not found")
		return
		
	var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
	if not enemy_faction:
		push_error("[DebugGridToggler] Could not load Enemy faction")
		return
		
	var enemies = BoardManager.get_entities_by_faction(enemy_faction)
	print("[DebugGridToggler] Found %d enemies to kill" % enemies.size())
	
	for enemy in enemies:
		if is_instance_valid(enemy):
			if enemy.has_method("take_damage"):
				# 造成足以致死的傷害 (使用目前血量確保剛好致死，或直接給一個大數字)
				var damage = 9999
				if enemy.get("character_data") and enemy.character_data.get("current_health"):
					damage = enemy.character_data.current_health
				
				print("[DebugGridToggler] Killing enemy: ", enemy.name, " with damage: ", damage)
				enemy.take_damage(damage)

func _on_test_recycle_pressed() -> void:
	if DeckManager:
		DeckManager.debug_test_recycle_animation()

func _on_test_gate_pressed() -> void:
	if DungeonManager:
		DungeonManager.debug_test_gate_transition()

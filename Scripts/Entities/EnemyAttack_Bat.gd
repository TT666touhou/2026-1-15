extends "res://Scripts/Entities/EnemyAttackComponent.gd"

## Enemy 004: Bat - 【超音波混亂】
## 使隨機玩家單位進入混亂狀態 (瞄準線擺動)

func perform_attack() -> void:
	# 1. 播放發動演出
	var visuals = parent_entity.get_node_or_null("UnitVisuals")
	if visuals and visuals.has_method("play_skill_cast_visual"):
		visuals.play_skill_cast_visual()
		await get_tree().create_timer(0.2).timeout

	# 視覺效果：音波擴散
	await _play_sonic_visual()
	
	# 邏輯：隨機挑選一個玩家單位施加混亂
	var players = _get_all_players()
	if players.is_empty(): return
	
	var target = players.pick_random()
	print("[EnemyAttack_Bat] Target picked: ", target.name if target else "NULL")
	if target is GridEntity:
		var status_mgr = target.get_node_or_null("StatusManager")
		print("[EnemyAttack_Bat] StatusManager found on ", target.name, ": ", "YES" if status_mgr else "NO")
		if status_mgr:
			var confusion_res = load("res://Resources/Status/Status_Confusion.tres")
			print("[EnemyAttack_Bat] Confusion resource loaded: ", "YES" if confusion_res else "NO")
			if confusion_res:
				# 方案 B：增加初始持續時間為 2，確保在玩家回合開始結算後仍保留 1 回合
				status_mgr.apply_status(confusion_res, {"duration": 2})
				print("[EnemyAttack_Bat] Called apply_status on ", target.name, " with duration 2")
		
		# 視覺反饋：變紫色閃爍
		var t_visuals = target.get_node_or_null("UnitVisuals")
		if t_visuals and t_visuals.sprite:
			var tween = create_tween()
			tween.tween_property(t_visuals.sprite, "modulate", Color(0.8, 0.5, 1.0), 0.2)
			tween.tween_property(t_visuals.sprite, "modulate", Color.WHITE, 0.2)
			tween.set_loops(2)

func _spawn_confusion_indicator(_target: GridEntity) -> void:
	# 舊有的 Label 標記邏輯已由 StatusManager 接管，這裡保留空函式或直接刪除
	pass

func _play_sonic_visual() -> void:
	var circle = Line2D.new()
	get_tree().current_scene.add_child(circle)
	circle.width = 3.0 # 增加寬度
	circle.default_color = Color(0.9, 0.4, 1.0, 1.0) # 更亮的紫色
	
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments + 1):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * 10.0)
	circle.points = points
	circle.global_position = parent_entity.global_position
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(circle, "scale", Vector2(25, 25), 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT) # 增加範圍與動感
	tween.tween_property(circle, "modulate:a", 0.0, 0.6)
	await tween.finished
	circle.queue_free()

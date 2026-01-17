extends Node2D

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			spawn_explosion(get_global_mouse_position())

func spawn_explosion(pos: Vector2) -> void:
	var tex = load("res://Resources/Shared/RetroSquare.tres")
	
	# 2. 主體圓球層 (Puffs) -> 現在改為方形落地層
	var puffs = GPUParticles2D.new()
	puffs.amount = 26
	puffs.texture = tex
	puffs.process_material = load("res://Resources/Shared/LandingExplosionProcess.tres")
	
	puffs.lifetime = 0.5
	puffs.one_shot = true
	puffs.explosiveness = 1.0
	puffs.z_index = 100
	puffs.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	add_child(puffs)
	puffs.global_position = pos
	puffs.emitting = true
	
	# 自動清理
	get_tree().create_timer(1.0).timeout.connect(func():
		puffs.queue_free()
	)

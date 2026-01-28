extends Node

@export var auto_start: bool = true

func _ready() -> void:
	if not auto_start:
		return
	if not TurnManager:
		return
	
	var player_faction = load("res://Resources/Factions/Faction_Player.tres")
	var enemy_faction = load("res://Resources/Factions/Faction_Enemy.tres")
	if player_faction and enemy_faction:
		TurnManager.start_combat([player_faction, enemy_faction])

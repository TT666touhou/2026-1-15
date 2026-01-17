extends BaseCard
class_name TrapCard

@export var trap_scene: PackedScene
@export var faction: FactionDefinition
@export var footprint_data: FootprintData
@export var attack_damage: int = 10
@export_enum("DROP:0", "LEAP:1", "POP:2", "NONE:3") var spawn_animation: int = 2 # 預設 POP (2)
@export var icon: Texture2D

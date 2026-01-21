extends BaseCard
class_name TurretCard

@export var turret_scene: PackedScene
@export var footprint_data: FootprintData
@export var attack_damage: int = 15
@export_enum("DROP:0", "LEAP:1", "POP:2", "NONE:3") var spawn_animation: int = 2 # 預設 POP
@export var icon: Texture2D

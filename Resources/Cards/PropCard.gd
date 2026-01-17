extends BaseCard
class_name PropCard

@export var prop_scene: PackedScene
@export var footprint_data: FootprintData
@export_enum("DROP:0", "LEAP:1", "POP:2", "NONE:3") var spawn_animation: int = 2 # 預設 POP (2)
extends Resource
class_name SkillCard

@export var soul_cost: int = 1
@export var exclusive_unit_id: String = ""

@export_group("Targeting")
@export var scope_type: TargetingDefinition.ScopeType = TargetingDefinition.ScopeType.SINGLE
@export var aoe_radius: int = 0
@export var target_filter: TargetingDefinition.TargetFilter = TargetingDefinition.TargetFilter.ENEMY
@export var origin_is_self: bool = false
@export var can_target_empty: bool = false

@export_group("Effects")
@export var effects: Array[EffectDefinition] = []

@export_group("Special")
@export var is_move_skill: bool = false
@export var post_move_targeting: TargetingDefinition
@export var post_move_effects: Array[EffectDefinition] = []

@export_group("Metadata")
@export var card_id: String
@export var card_name: String
@export_multiline var description: String
@export var icon: Texture2D

extends BaseCard
class_name UnitCard

# Placement
@export var unit_scene: PackedScene
@export var faction: FactionDefinition
@export var icon: Texture2D # New icon property for UI display

# Core Mechanics: Movement & Footprint
@export var footprint_data: FootprintData
@export var movement_range_data: MovementRangeData
@export_enum("DROP:0", "LEAP:1", "POP:2", "NONE:3") var spawn_animation: int = 0

# Combat Stats
@export var base_speed: float = 1.0 # 1.0 相當於 600 最大力
@export var attack_damage: int = 10
@export var base_combo_count: float = 1.0

# New Stats (Crit & Luck)
@export var base_crit_rate: float = 0.0 # 預設 0%
@export var base_luck: int = 0          # 預設 0
@export var base_avoid: float = 0.0     # 基礎閃避率 (0.0 = 0%)
@export var base_accuracy: float = 1.0  # 基礎精準度 (1.0 = 100%)
@export var base_shield: int = 0        # 初始護盾
@export var base_barriers: int = 0      # 初始防護罩層數
@export var base_dr: float = 0.0          # 基礎減傷率 (0.0 = 0%)
@export var base_resistance: float = 0.0  # 基礎抗性 (0.0 = 0%)
@export var base_reflect: float = 0.0     # 基礎反射率 (0.0 = 0%)
@export var base_pursuit: int = 0         # 基礎追擊傷害 (定值)
@export var base_parry: float = 0.0       # 基礎格擋率 (0.0 = 0%)
@export var base_drain: float = 0.0       # 基礎吸血率 (0.0 = 0%)
@export var base_crit_dmg: float = 0.0    # 基礎額外暴擊傷害 (0.0 = 0%)
@export var base_penetration: float = 0.0 # 基礎貫穿率 (0.0 = 0%)

# Trait (Leader Skill)
@export var character_trait: TraitData
@export var default_skill: UnitSkillData

# Note: max_health is inherited from BaseCard (float)
# We use it as the source of truth for unit health.

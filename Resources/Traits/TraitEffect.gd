extends Resource
class_name TraitEffect

## 特性效果定義
## 定義單一效果的邏輯 (條件 + 數值)

# 觸發時機
# PASSIVE: 常駐加成 (初始化或狀態重算時應用)
# ON_ATTACK: 攻擊結算/計算時應用
# ON_KILL, TURN_START, ON_DAMAGED: 保留擴充，未來可在相關事件中調用
enum TriggerType { PASSIVE, ON_ATTACK, ON_KILL, TURN_START, ON_DAMAGED }
@export var trigger_type: TriggerType = TriggerType.PASSIVE

# 效果類型
enum EffectBehavior { MODIFY_STAT, GRANT_RESOURCE, APPLY_STATUS }
@export var effect_behavior: EffectBehavior = EffectBehavior.MODIFY_STAT

# 目標範圍
enum TargetFaction { SELF, ALLY, ENEMY, ALL }
@export var target_faction: TargetFaction = TargetFaction.ALLY
@export var target_unit_id: String = "" # 可選：特定單位 ID

# 觸發條件
enum ConditionType { 
	NONE,           # 無條件 (常駐)
	HP_THRESHOLD,   # HP 閾值 (比例)
	COMBO_COUNT,    # 連擊數
	FACTION_MATCH,  # 陣營匹配 (通常與 TargetFaction 搭配使用)
	UNIT_TYPE       # 單位類型 (例如：攻擊型、防禦型) - 暫留
}
@export var condition_type: ConditionType = ConditionType.NONE
@export var condition_value: float = 0.0 # 例如 0.7 (70%), 4 (4 Combo)

enum Comparison { GREATER, LESS, EQUAL, GREATER_EQUAL, LESS_EQUAL }
@export var comparison: Comparison = Comparison.GREATER_EQUAL

# 加成效果
enum StatType {
	ATTACK_MULTIPLIER,          # 攻擊力倍率 (1.5 = +50%)
	DAMAGE_RECEIVED_MULTIPLIER, # 受傷倍率 (0.8 = -20%)
	CRIT_RATE_FLAT,             # 爆擊率加值 (0.1 = +10%)
	HEAL_PER_TURN,              # 每回合回復 (數值或比例) - 暫留
	HP_MULTIPLIER,              # HP 倍率 (常駐)
	COMBO_ADDITIVE,             # 連擊數加值 (常駐)
	DR_ADDITIVE,                 # 減傷率加值 (0.1 = +10%)
	RES_ADDITIVE,                # 抗性加值 (0.1 = +10%)
	REF_ADDITIVE,                # 反射率加值 (0.1 = +10%)
	PUR_ADDITIVE,                # 追擊加值 (定值)
	PAR_ADDITIVE,                # 格擋率加值 (0.1 = +10%)
	DRA_ADDITIVE,                # 吸血率加值 (0.1 = +10%)
	CDM_ADDITIVE,                # 額外暴擊傷害加值 (0.1 = +10%)
	PEN_ADDITIVE                 # 貫穿率加值 (0.1 = +10%)
}
@export var stat_type: StatType = StatType.ATTACK_MULTIPLIER
@export var value: float = 1.0 # 效果數值

# GRANT_RESOURCE 專用
@export var resource_key: String = "soul"
@export var resource_amount: float = 0.0

# APPLY_STATUS 專用 (需搭配 StatusManager.apply_status)
@export var status_resource: Resource

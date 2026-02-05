extends Resource
class_name EquipmentTagDefinition

## 裝備標籤定義，供 SynergyManager 與書籤 UI 使用。
## 可透過 .get("trait_id") 等與 Dictionary 相容，供 SynergyManager.register_trait 使用。

@export var trait_id: String = ""
@export var trait_name: String = ""
@export var color: Color = Color.WHITE
@export var icon: Texture2D
@export var thresholds: Array = []  # 門檻數量，如 [1, 4, 7]
@export var effect_descriptions: Array = []  # 各門檻效果描述
@export var effect_script: GDScript  # 效果邏輯腳本

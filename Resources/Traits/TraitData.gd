extends Resource
class_name TraitData

## 角色特性資料
## 定義特性的描述與包含的效果列表

@export var trait_name: String = "New Trait"
@export_multiline var description: String = "Description of the trait."
@export var icon: Texture2D
@export var effects: Array[TraitEffect] = []


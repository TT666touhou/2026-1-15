extends Resource
class_name ResourceData

## 資源數據資源
## 定義資源的類型和屬性

@export var resource_type: String = "wood"  # "wood" 或 "gold"
@export var min_amount: int = 200
@export var max_amount: int = 400
@export var gather_time: float = 5.0
@export var gather_yield: int = 20


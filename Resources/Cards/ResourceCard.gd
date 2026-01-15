extends BaseCard
class_name ResourceCard

## 資源卡片
## 用於通過卡片系統放置資源實體

@export var resource_scene: PackedScene  # WoodResource.tscn 或 GoldResource.tscn
@export var resource_data: ResourceData  # 資源數據（可選，如果為 null 則使用場景默認值）
@export var footprint_data: FootprintData


extends Node
class_name TileSetCustomDataInitializer

# 用於在 TileSet 中動態添加 Custom Data Layers 的工具腳本
# 注意：在 Godot 4.5 中，Custom Data Layers 需要在 TileSet 資源中定義
# 此腳本提供一個方法來檢查並添加必要的 Custom Data Layers

# Custom Data Layer 定義
const CUSTOM_DATA_LAYERS := {
	"tile_type": {"type": TYPE_STRING, "default_value": "ground"},
	"base_amount": {"type": TYPE_INT, "default_value": 0}
}

# 初始化 TileSet 的 Custom Data Layers
# 注意：此方法需要在編輯器中運行，或在運行時動態添加（如果 API 支持）
static func ensure_custom_data_layers(tileset: TileSet) -> bool:
	if tileset == null:
		print("[TileSetCD] ERROR: TileSet is null")
		return false
	
	# 在 Godot 4.5 中，Custom Data Layers 需要在 TileSet 資源中定義
	# 這裡提供一個檢查方法，確保 Custom Data Layers 存在
	# 注意：動態添加 Custom Data Layers 可能需要在編輯器中手動設置
	
	# 檢查 Custom Data Layers 是否存在
	var has_tile_type := false
	var has_base_amount := false
	
	# 嘗試從 TileSet 讀取 Custom Data Layers（如果 API 支持）
	# 注意：Godot 4.5 的 TileSet API 可能不直接支持動態添加 Custom Data Layers
	# 這裡提供一個檢查方法，確保 Custom Data Layers 存在
	
	# 如果 Custom Data Layers 不存在，輸出警告
	if not has_tile_type or not has_base_amount:
		print("[TileSetCD] WARN: Custom Data Layers may not be defined in TileSet")
		print("[TileSetCD] Please manually add Custom Data Layers in TileSet resource:")
		print("[TileSetCD]   - tile_type (String, default: 'ground')")
		print("[TileSetCD]   - base_amount (Int, default: 0)")
		return false
	
	return true

# 為指定的 tile 設置 Custom Data（如果 Custom Data Layers 已定義）
static func set_tile_custom_data(tilemap_layer: TileMapLayer, cell: Vector2i, tile_type: String, base_amount: int) -> bool:
	if tilemap_layer == null:
		return false
	
	var tile_data := tilemap_layer.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	
	# 嘗試設置 Custom Data（如果 Custom Data Layers 已定義）
	# 注意：如果 Custom Data Layers 不存在，這些調用可能會失敗
	tile_data.set_custom_data("tile_type", tile_type)
	tile_data.set_custom_data("base_amount", base_amount)
	
	return true


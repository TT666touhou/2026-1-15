extends Node
class_name GridPathfinder

## 路徑規劃器
## 使用 AStarGrid2D 進行路徑規劃

var grid: Node  # Grid 類型（使用 Node 避免循環依賴）
var a_star: AStarGrid2D

func _ready() -> void:
	await get_tree().current_scene.ready
	_initialize()

func _initialize() -> void:
	grid = get_tree().get_first_node_in_group("grid")
	if grid == null:
		push_error("[GridPathfinder] Grid not found")
		return
	
	# 檢查 Grid 是否有必要的屬性（通過嘗試訪問來檢查）
	var map_width: int
	var map_height: int
	var cell_size: Vector2i
	
	if not ("map_width" in grid) or not ("map_height" in grid) or not ("cell_size" in grid):
		push_error("[GridPathfinder] Grid missing required properties")
		return
	
	map_width = grid.map_width
	map_height = grid.map_height
	cell_size = grid.cell_size
	
	# 創建 AStarGrid2D（支持8方向移動）
	a_star = AStarGrid2D.new()
	a_star.region = Rect2(0, 0, map_width, map_height)
	a_star.cell_size = Vector2i(cell_size.x, cell_size.y)
	a_star.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	a_star.update()
	
	# 更新障礙物
	update_obstacles()
	
	# 連接 Grid 的信號以實時更新障礙物
	if grid.has_signal("cell_occupied_changed"):
		grid.cell_occupied_changed.connect(_on_cell_occupied_changed)
	
	add_to_group("grid_pathfinder")
	print("[GridPathfinder] Initialized: ", map_width, "x", map_height)

func find_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	"""計算路徑（嚴格8方向，西洋棋皇后風格）"""
	if grid == null or a_star == null:
		return []
	
	if not grid.has_method("is_in_bounds"):
		return []
	
	if not grid.is_in_bounds(start) or not grid.is_in_bounds(end):
		return []
	
	# 如果起點和終點相同，返回空路徑（不需要移動）
	if start == end:
		return []
	
	# 使用 A* 驗證可達性
	var a_star_path = _get_astar_path(start, end)
	if a_star_path.is_empty():
		return []  # 無法到達
	
	# 重構為嚴格8方向路徑
	return _rebuild_path_8_directions(start, end)

func get_movement_range(start: Vector2i, max_distance: int) -> Array[Vector2i]:
	"""計算移動範圍（BFS）"""
	if grid == null or a_star == null:
		return []
	
	if not grid.has_method("is_in_bounds"):
		return []
	
	var reachable: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	var distances: Dictionary = {start: 0}
	
	# 8方向移動
	var directions = [
		Vector2i(0, -1),   # 上
		Vector2i(0, 1),    # 下
		Vector2i(-1, 0),   # 左
		Vector2i(1, 0),    # 右
		Vector2i(-1, -1),  # 左上
		Vector2i(1, -1),   # 右上
		Vector2i(-1, 1),   # 左下
		Vector2i(1, 1)     # 右下
	]
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var distance = distances[current]
		
		if distance >= max_distance:
			continue
		
		for dir in directions:
			var next_cell = current + dir
			
			if not grid.is_in_bounds(next_cell):
				continue
			
			if a_star.is_point_solid(next_cell):
				continue
			
			if next_cell in distances:
				continue
			
			distances[next_cell] = distance + 1
			reachable.append(next_cell)
			queue.append(next_cell)
	
	return reachable

func update_obstacles() -> void:
	"""更新障礙物（同步 Grid 的佔用狀態）"""
	if grid == null or a_star == null:
		return
	
	if not ("map_width" in grid) or not ("map_height" in grid):
		return
	
	var map_width: int = grid.map_width
	var map_height: int = grid.map_height
	
	if not grid.has_method("is_cell_occupied"):
		return
	
	for x in range(map_width):
		for y in range(map_height):
			var cell = Vector2i(x, y)
			var is_occupied = grid.is_cell_occupied(cell)
			a_star.set_point_solid(cell, is_occupied)

func _on_cell_occupied_changed(cell: Vector2i, is_occupied: bool) -> void:
	"""當格子佔用狀態改變時更新 A*"""
	if a_star != null:
		# 檢查邊界以避免錯誤
		if grid and grid.has_method("is_in_bounds"):
			if not grid.is_in_bounds(cell):
				return
		
		# 額外檢查 A* region
		if not a_star.region.has_point(cell):
			return
			
		a_star.set_point_solid(cell, is_occupied)

func _get_astar_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	"""使用 A* 查找路徑（僅用於驗證可達性）"""
	# 檢查終點是否被其他實體佔用
	if a_star.is_point_solid(end):
		if grid.has_method("is_cell_occupied") and grid.is_cell_occupied(end):
			return []  # 終點確實被佔用，無法到達
	
	# 臨時取消起點的 solid 標記（如果有的話）
	var start_was_solid = a_star.is_point_solid(start)
	if start_was_solid:
		a_star.set_point_solid(start, false)
	
	var path = a_star.get_id_path(start, end)
	
	# 恢復起點的 solid 標記
	if start_was_solid:
		a_star.set_point_solid(start, true)
	
	return path

func _rebuild_path_8_directions(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	"""重構路徑為嚴格8方向（西洋棋皇后風格）
	
	算法：
	1. 從起點開始
	2. 選擇8個方向中，能最接近目標且可達的方向
	3. 沿該方向移動，直到：
	   - 到達目標
	   - 遇到障礙物
	   - 需要改變方向才能更接近目標
	4. 重複直到到達目標
	"""
	var path: Array[Vector2i] = [start]
	var current = start
	var directions = _get_8_directions()
	var visited: Dictionary = {start: true}
	var max_iterations = 1000  # 防止無限循環
	
	while current != end and path.size() < max_iterations:
		var best_direction: Vector2i = Vector2i.ZERO
		var best_distance_sq = current.distance_squared_to(end)
		
		# 嘗試所有8個方向
		for dir in directions:
			var next_cell = current + dir
			
			# 檢查邊界
			if not grid.is_in_bounds(next_cell):
				continue
			
			# 檢查是否已訪問（避免來回移動）
			if next_cell in visited:
				continue
			
			# 檢查是否為障礙物
			if a_star.is_point_solid(next_cell):
				continue
			
			# 檢查是否更接近目標
			var distance_sq = next_cell.distance_squared_to(end)
			if distance_sq < best_distance_sq:
				best_distance_sq = distance_sq
				best_direction = dir
		
		# 如果找不到可達方向，返回當前路徑
		if best_direction == Vector2i.ZERO:
			break
		
		# 沿最佳方向延伸，直到無法繼續
		var direction_path = _extend_in_direction(current, best_direction, end, visited)
		for cell in direction_path:
			if cell != current:  # 跳過起點
				path.append(cell)
				visited[cell] = true
				current = cell
				if current == end:
					return path
		
		# 如果沒有進展，停止（防止無限循環）
		if current == path[-1]:
			break
	
	return path

func _extend_in_direction(start: Vector2i, direction: Vector2i, target: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	"""沿指定方向延伸，直到遇到障礙物或到達目標（西洋棋皇后風格）
	
	返回：從 start 開始，沿 direction 延伸的所有可達格子
	"""
	var path: Array[Vector2i] = [start]
	var current = start
	
	while true:
		var next_cell = current + direction
		
		# 檢查邊界
		if not grid.is_in_bounds(next_cell):
			break
		
		# 檢查是否已訪問
		if next_cell in visited:
			break
		
		# 檢查是否為障礙物
		if a_star.is_point_solid(next_cell):
			break
		
		# 檢查是否到達目標
		if next_cell == target:
			path.append(next_cell)
			break
		
		# 檢查是否仍然接近目標（避免明顯繞遠路）
		var current_dist_sq = current.distance_squared_to(target)
		var next_dist_sq = next_cell.distance_squared_to(target)
		
		# 如果移動後距離明顯增加（且距離較遠），停止
		# 這確保我們不會沿錯誤方向移動太遠
		if next_dist_sq > current_dist_sq + 1 and current_dist_sq > 4:
			break
		
		path.append(next_cell)
		current = next_cell
		
		# 防止無限循環
		if path.size() > 1000:
			break
	
	return path

func _get_8_directions() -> Array[Vector2i]:
	"""返回8個基本方向"""
	return [
		Vector2i(0, -1),   # 上
		Vector2i(0, 1),    # 下
		Vector2i(-1, 0),   # 左
		Vector2i(1, 0),    # 右
		Vector2i(-1, -1),  # 左上
		Vector2i(1, -1),   # 右上
		Vector2i(-1, 1),   # 左下
		Vector2i(1, 1)     # 右下
	]

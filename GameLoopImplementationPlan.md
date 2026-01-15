# 遊戲循環與關卡推進系統實作計畫 (Game Loop & Progression Implementation Plan) - v2

本計畫旨在實作核心的 Roguelike 循環系統，包含戰鬥結束偵測、出口生成、樓層推進與房間隨機選取機制。

**v2 變更**: 傳送門將改為「踩踏觸發」機制，而非滑鼠點擊。玩家需移動單位至傳送門上方以進入下一層。

## 1. 核心架構擴充 (Core Architecture Expansion)

### 1.1 `DungeonManager` 升級
*   **狀態管理**: `current_floor`, `current_stage`, `dungeon_state`。
*   **數據結構**: `RoomPool` 管理。

### 1.2 `BoardManager` 擴充 (已完成)
*   **信號**: `all_enemies_defeated` (需確認實作)。

## 2. 傳送門系統 (Gate System) - 重構

### 2.1 修改 `GateEntity`
這是一個放置在網格上的特殊物件。

*   **場景 (`GateEntity.tscn`)**:
    *   根節點: `Node2D` (移除 `Area2D` 的點擊邏輯)。
    *   視覺: 背景光圈 (Sprite) + 圖示 (Icon) + 文字 (Label)。
    *   層級: 確保 `z_index` 低於單位 (Unit)，讓單位看起來是「站」在傳送門上。
*   **腳本 (`GateEntity.gd`)**:
    *   移除 `_on_input_event` (如果有的話)。
    *   新增 `grid_position` 屬性，用於與網格系統同步。
    *   變數: `next_room_data`。

### 2.2 踩踏觸發邏輯
*   **位置**: 我們需要在單位移動結束時進行檢查。
*   **實作點**: `TurnManager` 或 `GridMover`。
    *   建議在 `TurnManager.start_turn` (玩家回合開始前) 或 `GridMover` 移動結束回調中檢查。
    *   **最佳方案**: 在 `Scripts/UI/GridSelector.gd` 或負責移動的邏輯中，當 `_on_unit_move_finished` 時檢查。
    *   或者，讓 `GateEntity` 註冊到 `Grid` 的某個特殊層，當 `GridEntity` 更新位置時，`DungeonManager` 檢查是否有重疊。
*   **偵測方式**:
    *   `DungeonManager` 維護一個 `active_gates` 列表。
    *   當單位移動到某個座標，檢查該座標是否匹配 `active_gates` 中的任何一個。
    *   若匹配，呼叫 `DungeonManager.advance_to_next_floor(gate.next_room_data)`。

### 2.3 生成邏輯調整
*   `DungeonManager.spawn_gates()`。
*   生成的門不會阻擋移動 (不像 Enemy 或 Obstacle)，它們允許重疊。

## 3. 房間池與樓層切換
*   `RoomPool` 結構與載入邏輯同 v1。
*   `advance_to_next_floor` 實作同 v1。

## 4. 執行步驟 (Execution Steps)

### Step 1: 戰鬥結束偵測
1.  修改 `BoardManager.gd`，實作敵人計數與 `all_enemies_defeated` 信號。
2.  `DungeonManager` 連接此信號。

### Step 2: 傳送門實體 (Gate Entity)
1.  製作 `GateEntity.tscn`，調整視覺層級 (Z-Index = -1 or 0，低於單位)。
2.  修改 `GateEntity.gd`，專注於資料儲存。

### Step 3: 實作踩踏偵測
1.  在 `DungeonManager` 中加入 `check_gate_trigger(pos: Vector2i)` 方法。
2.  找出負責移動單位的腳本 (可能是 `GridSelector.gd` 或 `GridEntity.gd` 內的移動邏輯)，在移動結束後呼叫檢查。

### Step 4: 樓層切換與重置
同 v1 Step 4。

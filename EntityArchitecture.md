# 實體架構總覽 (Entity Architecture Overview)

## 核心設計理念 (Core Concept)

目前系統採用 **數據驅動 (Data-Driven)** 與 **組件化 (Component-Based)** 的混合架構。
實體的所有行為參數（數值、外觀、移動規則）皆由 `Resource (.tres)` 定義，而運行時邏輯則由 `GridEntity` 及其子組件負責。

這種設計使得策劃人員可以在不修改代碼的情況下，通過編輯 `.tres` 文件來創建全新的單位類型。

---

## 1. 靜態數據層 (Static Data Layer - Resources)

所有的實體定義都始於 **`UnitCard (.tres)`**。它是實體的「藍圖」。

### **UnitCard (資源核心)**
*   **用途**: 定義單位的靜態屬性。
*   **腳本**: `Resources/Cards/UnitCard.gd`
*   **關鍵屬性**:
    *   `unit_scene`: `PackedScene` (.tscn) - 實體在場景中的視覺與組件模板。
    *   `faction`: `FactionDefinition` (.tres) - 陣營歸屬（Player/Enemy）。
    *   `footprint_data`: `FootprintData` (.tres) - 在網格上佔據的形狀與大小 (例如 1x1, 2x2)。
    *   `movement_range_data`: `MovementRangeData` (.tres) - 移動能力定義（方向、距離限制）。
    *   `max_health`: `float` - 生命值上限。
    *   `attack_damage`: `int` - 攻擊力。
    *   `base_combo_count`: `float` - 基礎連擊數。

### **輔助資源 (Sub-Resources)**
*   **FactionDefinition**: 定義陣營顏色、是否可控等。
    *   例如: `Faction_Player.tres`, `Faction_Enemy.tres`
*   **FootprintData**: 定義佔格形狀。
    *   例如: `Footprint_1x1.tres` (單格), `Footprint_2x2.tres` (大型單位)
*   **MovementRangeData**: 定義移動邏輯。
    *   例如: `MovementRange_Unlimited.tres` (全向無限移動), `MovementRange_Enemy001.tres` (自定義移動)

---

## 2. 運行時實例層 (Runtime Instance Layer - Scenes & Scripts)

當一張卡牌被打出時，`UnitCard` 的數據會被注入到實例化的場景中。

### **場景結構 (Scene Structure - e.g., Unit001.tscn)**

一個標準的實體場景包含以下節點：

1.  **Root Node (CharacterBody2D)**
    *   **Script**: `Scripts/Entities/GridEntity.gd`
    *   **職責**: 實體的核心大腦。
        *   管理 `Grid` 位置 (`grid_position`)。
        *   作為所有數據的 **Single Source of Truth**（移動範圍、CharacterData、Faction）。
        *   處理死亡 (`_handle_death`) 與資源釋放。
    *   **數據來源**: 被注入 `UnitCard` 的數據。

2.  **CardProvider (Node)**
    *   **Script**: `Scripts/Entities/CardProvider.gd`
    *   **職責**: **數據注入器 (The Injector)**。
    *   **運作**: 
        1. 接收 `UnitCard` 資源。
        2. 解析資源中的 `footprint_data`, `faction`, `movement_range_data`。
        3. 將這些數據「安裝」到父節點 (`GridEntity`) 上。
        4. 創建 `CharacterData` 實例並傳遞給 `GridEntity`。

3.  **GridMover (Node)**
    *   **Script**: `Scripts/Entities/GridMover.gd`
    *   **職責**: 處理平滑移動動畫。
    *   **運作**: 接收目標格子座標，執行 `Tween` 動畫將實體移過去。

4.  **UnitMovementController (Node)**
    *   **Script**: `Scripts/Entities/UnitMovementController.gd`
    *   **職責**: (目前較為輕量) 用於處理移動相關的邏輯判斷或狀態。

5.  **ArrowIndicators (Scene)**
    *   **Script**: `Scripts/Entities/MovementDirectionIndicator.gd`
    *   **職責**: 視覺化顯示可移動的方向箭頭。
    *   **運作**: 讀取 `GridEntity.movement_range_data` 來決定顯示哪些箭頭。

---

## 3. 數據流向 (Data Flow)

**創建流程 (Spawn Flow):**

1.  **卡牌打出**: 玩家拖曳卡牌，`Hand.gd` 實例化 `UnitCard.unit_scene` (例如 `Unit001.tscn`)。
2.  **數據注入**: `CardProvider.set_card_and_apply(card)` 被調用。
3.  **屬性分配**:
    *   `card.faction` -> `GridEntity.faction` (決定能否被選取)
    *   `card.footprint_data` -> `GridEntity.footprint_data` (決定佔格)
    *   `card.movement_range_data` -> **Duplicate()** -> `GridEntity.movement_range_data` (確保運行時可獨立修改)
    *   `card.max_health` -> `CharacterData` (創建運行時數值實例) -> `GridEntity.character_data`

**移動流程 (Movement Flow):**

1.  **選取**: 點擊單位 -> `GridSelector` 檢查 `GridEntity.faction` 是否匹配回合。
2.  **範圍計算**: `GridSelector` 調用 `GridEntity.get_reachable_cells()`。
    *   `GridEntity` 讀取自己的 `movement_range_data` 和 `grid` 狀態，返回可移動格子列表。
3.  **顯示**: `MovementRangeIndicator` 根據上述列表繪製高亮格子。
4.  **執行**: 玩家點擊目標格子 -> `GridSelector` 命令 `GridMover` 移動。

---

## 總結 (Summary)

您的實體現在是一個高度模組化的容器：
*   **外觀** 由 `.tscn` 決定。
*   **數值與規則** 由 `.tres` 決定。
*   **運行時狀態** 由 `GridEntity` 統一管理。

這意味著您可以隨時創建一個新的 `.tres` 文件，換上不同的圖片和數值，就能直接造出一個全新的敵人或單位，而不需要寫一行代碼。


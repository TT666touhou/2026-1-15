# 隊伍系統設計概念 (Party System Design Concept)

基於我們先前的討論與 Buriedbornes 的靈感，以下是我對「隊伍系統」的理解與設計藍圖。此文檔旨在確認我們對目標的一致性。

## 1. 核心概念 (Core Concepts)

我們正在構建一個 **Roguelike 生存 RPG**，而非傳統的卡牌召喚遊戲。

*   **角色永續性 (Persistence)**:
    *   角色不再是免洗的「召喚物」。
    *   一旦加入隊伍，角色數據 (`CharacterData`) 將在戰鬥之間持續存在。
    *   戰鬥中的 `GridEntity` 只是 `CharacterData` 在場景中的臨時容器（皮囊）。

*   **成長機制 (Growth System - Buriedbornes Style)**:
    *   **無等級制 (No Leveling)**: 角色不會透過經驗值升級。
    *   **裝備驅動 (Gear/Buff Driven)**: 角色的變強來自於獲取並堆疊「裝備」或「永久增益」。
    *   **動態數值**: 例如我們剛新增的 `combo_count`，以及 `attack_damage`, `max_health` 等，會在遊戲過程中不斷被外部來源（事件、戰利品）修改並累積。

*   **死亡與復活 (Death & Revival)**:
    *   **非永久死亡**: 角色在戰鬥中 HP 歸零不會永久消失。
    *   **戰後懲罰**: 戰鬥結束後，死亡的角色會以 **1 HP** 的狀態復活，迫使玩家在下一場戰鬥前進行治療或保護該角色。

*   **卡牌的角色 (Role of Cards)**:
    *   目前（過渡期）：卡牌用於「放置/部署」單位。
    *   **目標**：卡牌將轉變為 **「技能/指令 (Skills/Commands)」**。玩家打出卡牌來命令場上的角色行動（攻擊、移動、防禦），而非憑空召喚新單位。
    *   *註：這部分需要改變目前的 CardProvider 邏輯。*

## 2. 架構設計 (Architecture Design)

為了實現上述目標，我們將引入以下架構組件：

### **A. PartyManager (隊伍管理器)**
*   **類型**: Autoload (Singleton)
*   **職責**:
    *   持有玩家當前的隊伍名單：`Array[CharacterData]`。
    *   管理隊伍上限 (Max Party Size)。
    *   提供 API 來加入角色、移除角色。
    *   **戰鬥結算**: 在戰鬥結束時，遍歷隊伍，處理死亡角色的 1 HP 復活邏輯，並保存當前狀態。

### **B. CharacterData (角色數據實例)**
*   **類型**: RefCounted (Runtime Object)
*   **職責**:
    *   存儲單個角色的**實時**狀態（當前血量、當前攻擊力、連擊數、已裝備物品）。
    *   區別於 `UnitCard`（靜態模板）。`UnitCard` 只是創建 `CharacterData` 的模具。
    *   **信號**: 發出 `health_changed`, `died`, `combo_count_changed` 等信號供 UI 和實體監聽。

### **C. 部署流程 (Deployment Flow)**
這是從「召喚」轉向「RPG」的關鍵變化：

1.  **準備階段 (Prep Phase)**:
    *   玩家在進入戰鬥前（或戰鬥開始時的部署階段），從 `PartyManager` 中選擇角色。
2.  **實體化 (Materialization)**:
    *   系統根據 `CharacterData` 中的 `unit_def (UnitCard)` 實例化對應的 `.tscn`。
    *   調用 `grid_entity.setup_character(character_data)` 將數據注入實體。
3.  **回收 (Retrieval)**:
    *   戰鬥結束時，銷毀場景中的 `GridEntity`，但數據保留在 `PartyManager` 的 `CharacterData` 中。

## 3. 實作路徑 (Implementation Roadmap)

1.  **Phase 1: 基礎數據管理 (我們在這裡)**
    *   完善 `PartyManager`。
    *   實現角色的加入 (`recruit`) 與查詢。
    *   確保 `CharacterData` 能夠正確存儲並隨時間變化。

2.  **Phase 2: 部署邏輯**
    *   修改遊戲循環，從「手牌召喚」改為「隊伍部署」。
    *   可能需要一個「部署區」或「準備回合」。

3.  **Phase 3: 裝備與成長**
    *   實作裝備系統，讓其能動態修改 `CharacterData` 的數值（如連擊數）。

---
請確認這份文檔是否準確描述了您心中的「隊伍系統」？如果是，我們將開始執行 **Phase 1**。


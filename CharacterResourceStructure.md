# 角色資源結構與動態變化分析 (CharacterResourceStructure.md)

## 1. 單一角色的資源構成 (Resource Composition)

在目前的架構中，一個完整的角色 (Unit) 是由多個 **Resource (.tres)** 組合而成的。這種「組合優於繼承 (Composition over Inheritance)」的設計使得角色非常靈活。

以下是一個角色 (例如 `Unit_001`) 所擁有的資源層級圖：

### **核心定義 (Root)**
*   **`UnitCard.gd`** (`Unit_001.tres`)
    *   角色身分證，定義了所有基礎屬性與子資源的引用。
    *   **主要屬性**: `display_name`, `cost`, `attack_damage`, `base_crit_rate`, `base_luck`...

### **子資源 (Sub-Resources)**
這些資源被 `UnitCard` 引用，定義了角色的具體行為：

1.  **陣營定義 (`FactionDefinition`)**
    *   檔案範例：`Faction_Player.tres`, `Faction_Enemy.tres`
    *   **用途**：決定敵我識別、回合順序、AI 控制權。
    *   **可變性**：通常固定，但可透過更換資源實現「倒戈」或「魅惑」。

2.  **佔地數據 (`FootprintData`)**
    *   檔案範例：`Footprint_1x1.tres`, `Footprint_2x2.tres`
    *   **用途**：定義單位在棋盤上佔據的格子形狀與大小。
    *   **可變性**：通常固定。

3.  **移動/攻擊範圍 (`MovementRangeData`)**
    *   檔案範例：`MovementRange_Unlimited.tres`
    *   **用途**：定義箭頭方向、移動模式 (跳躍/滑行/步行)。同時也是**攻擊範圍**的依據。
    *   **可變性**：**高度動態**。遊戲中經常會有「封印箭頭」、「增加箭頭」的 Debuff/Buff。目前的架構支援在 `CardProvider` 中替換此資源。

4.  **角色特性/隊長技 (`TraitData`)**
    *   檔案範例：`Trait_ComboMaster.tres`
    *   **用途**：定義被動技能或隊長技能的容器。
    *   **結構**：
        *   `trait_name`: 名稱
        *   `effects`: `Array[TraitEffect]` (效果列表)
    *   **可變性**：**支援動態替換**。

5.  **特性效果 (`TraitEffect`)**
    *   檔案範例：`Effect_ComboAtkUp.tres` (或內嵌於 TraitData)
    *   **用途**：定義具體的邏輯 (條件 -> 數值)。
    *   **屬性**：`target_faction`, `condition_type`, `value` 等。

---

## 2. 架構靈活性分析 (Flexibility Analysis)

針對您提出的需求：「支援遊戲內變化（改變條件參數、直接替換）」：

### A. 直接替換 (Replacement) - **完全支援**
目前的 `CharacterData` (運行時數據) 持有 `character_trait` 的引用。
*   **實作方式**：在遊戲邏輯中 (例如進化、裝備道具)，直接將 `character_data.character_trait` 指派為一個新的 `TraitData` 資源。
*   **結果**：`AttackManager` 與 `PartyManager` 都是**即時讀取 (Live Query)** 的。下一次攻擊計算時，系統會自動讀取新的 Trait，無需額外刷新。

### B. 改變參數 (Parameter Modification) - **支援 (需注意實例化)**
如果您想實現「技能升級」，將原本的 "Combo > 2 增傷 1.5倍" 改為 "增傷 2.0倍"。
*   **潛在風險**：Resource 在 Godot 中預設是**共享的**。如果您直接修改 `Unit_001.tres` 中的 Trait 數值，所有場上的 Unit_001 都會同步改變 (這通常是好事，但也可能是副作用)。
*   **解決方案**：
    *   **全域升級**：直接修改資源，所有同名單位受益。
    *   **個體強化**：在修改前呼叫 `.duplicate()` 創建該單位的專屬副本。
    ```gdscript
    # 範例：只強化這隻角色的隊長技
    var new_trait = character_data.character_trait.duplicate(true) # deep copy
    new_trait.effects[0].value = 2.0
    character_data.character_trait = new_trait
    ```

### C. 條件變化 (Condition Change)
例如「HP < 50% 觸發」變為「HP < 80% 觸發」。
*   同樣透過修改 `TraitEffect` 的 `condition_value` 達成。
*   由於 `AttackManager` 的 `calculate_trait_bonus` 是每一波攻擊都重新計算的，任何條件數值的變動都會即時生效。

### 總結
目前的架構是一個 **Data-Driven (數據驅動)** 且 **Late-Binding (晚期綁定)** 的系統。邏輯代碼 (`Manager`) 不持有狀態，只讀取數據 (`Resource`)。這意味著只要數據變了，行為就會立刻跟著變，非常適合處理複雜的遊戲內變化。


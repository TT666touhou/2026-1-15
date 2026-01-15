# 遊戲機制分析與設計文檔 (Game Mechanics Design Document)

## 1. 攻擊基礎概念 (Attack Basics)

### 箭頭 (Arrows) 與 攻擊方向
*   每個角色（棋子）擁有特定的箭頭配置（最多 8 個方向）。
*   **移動**: 角色只能朝有「雙重箭頭」或「單箭頭」的方向移動。
*   **攻擊**: 角色可以朝「所有有箭頭」的方向進行攻擊。
*   **合擊 (Combo)**: 當多個我方角色同時對同一個敵人進行攻擊判定時（即該敵人在多個我方角色的攻擊箭頭範圍內），會觸發合擊。

### 攻擊流程
1.  **移動階段**: 玩家移動一個棋子。
2.  **攻擊判定**: 檢查所有我方棋子的箭頭，看是否有敵人在攻擊範圍內。
    *   **注意**: 不僅僅是剛剛移動的棋子，所有在場上的棋子只要箭頭對準了敵人，都會參與攻擊。
3.  **合擊計算**: 計算對每個敵人進行合擊的總次數（Combo Count）。
4.  **傷害結算**: 根據合擊數、攻擊力、屬性等計算傷害並扣除敵人 HP。

## 2. 傷害計算公式 (Damage Formula)

基本傷害公式如下：

```text
最終傷害 = (基礎攻擊力 × 合擊倍率 × 屬性倍率 × 技能/領袖倍率 × 暴擊倍率)
```

### A. 基礎攻擊力 (Base Attack)
*   角色的面板攻擊力。
*   在我們的專案中對應 `CharacterData.attack_damage`。

### B. 合擊倍率 (Combo Multiplier)
1.  **合擊觸發條件 (Trigger Condition)**:
    *   必須有 **2 個或以上** 的我方單位同時對同一目標進行攻擊判定。
    *   若只有 1 個單位攻擊，無論打出多少 Hits，倍率皆為 **1.0**。

2.  **總連擊數計算 (Total Hits Calculation)**:
    *   `Total Hits` = Σ (每個攻擊單位的 `連擊數(Combo Count)` × `有效箭頭數`)
    *   **浮點數 Combo**: 每個箭頭獨立計算。若連擊數為 1.5，則每個箭頭有 50% 機率造成 2 Hits。

3.  **倍率公式**:
    *   若滿足觸發條件: `倍率 = 1.0 + (Total Hits * 0.125)`
    *   若未滿足: `倍率 = 1.0`

### C. 屬性倍率 (Attribute Multiplier)
*   火 > 木 > 水 > 火 (優勢 1.5倍, 劣勢 0.8倍)
*   光 <> 暗 (優勢 1.5倍)

### D. 暴擊 (Critical)
*   **計算範圍**: 每個攻擊角色獨立計算。
*   **倍率公式**: `Crit Multiplier = 2.0 * ceil(crit_rate)`

### E. 特殊條件倍率 (Conditional Multipliers)
1.  **面板修正 (Panel Modifiers)**: 攻擊前直接改變面板攻擊力（如：HP>80% 攻擊力 x1.5）。
2.  **動態修正 (Dynamic Modifiers)**: 傷害計算末端，根據當下情境（如：觸發合擊時）額外乘算的倍率。

## 3. 綜合傷害公式 (Comprehensive Formula)

```text
Step 1: 面板攻擊力 (Effective Attack)
   = 基礎攻擊力 × 面板修正(領袖技/被動)

Step 2: 原始傷害 (Raw Damage)
   = 面板攻擊力 × 合擊倍率(1 + Hits*0.125) × 屬性倍率 × 暴擊倍率(2.0 * ceil(crit_rate))

Step 3: 最終傷害 (Final Damage)
   = 原始傷害 × 動態修正(條件式倍率)
```

## 4. 視覺表現 (Visuals)
*   **攻擊動畫**: 單位向攻擊方向「撞擊」一下。
*   **受擊動畫**: 敵人閃爍或震動。
*   **數字跳出**: 顯示傷害數值 (若暴擊則顯示 Critical!)。
*   **合擊顯示**: 在攻擊開始前，顯示連線或 Combo 預告。

---

## 5. 遊戲循環與樓層結構 (Game Loop & Structure)

此章節定義了遊戲的宏觀流程，採用「10層循環」機制。

### A. 樓層循環 (The 10-Floor Cycle)
遊戲以 10 層為一個「階段 (Stage)」或「世界 (World)」。
*   **Floor 1-9 (一般層/事件層)**: 隨機戰鬥、商店、寶箱、精英怪。
*   **Floor 5 (中BOSS)**: 固定出現較強的守門人（可選）。
*   **Floor 10 (BOSS層)**: 該階段的最終頭目，擊敗後進入下一個世界（World 2-1）或結算。

### B. 過關機制 (Room Clear & Transition)
當玩家擊敗當前地圖內所有敵人後，進入「過關狀態」：
1.  **獎勵結算**: 掉落 SOUL、GOLD 或卡牌。
2.  **出口生成**: 
    *   在 Grid 的最右側（例如 `x=6` 的位置，對應 `y` 軸的中間幾個格子）生成 **「門 (Gate)」** 實體。
    *   門的數量通常為 **1~3 個**，代表接下來的分歧路線。
    *   每個門上方會顯示下個房間的「預覽圖示」（如：戰鬥、商店、精英、未知）。
3.  **選擇路線**: 玩家點擊其中一扇門，觸發 `SceneTransition`，載入下一層的配置。

### C. 地圖重置
*   進入下一層時，不需要重新載入整個 `World.tscn`，而是：
    *   保留 `PlayerResourceLedger` (資源)、`PartyManager` (隊伍)、`Hand` (手牌)。
    *   清除 `Grid` 上所有的 `Enemy` 和 `Obstacle`。
    *   重置玩家位置（例如回到左側起始點）。
    *   根據下一層的資料，生成新的敵人和地形。

---

## 6. 隨機內容生成機制 (Content Generation - Isaac Style)

參考《The Binding of Isaac》的房間生成邏輯，我們採用 **「權重池 (Weight Pools)」** 與 **「預製佈局 (Prefabs)」** 結合的方式。

### A. 房間難度池 (Difficulty Pools)
我們不完全隨機生成每一個磚塊，而是設計多種「敵人配置模板 (Enemy Patterns)」，並依據難度分類：
*   **Pool T1 (Easy)**: 史萊姆、蝙蝠等弱怪。
*   **Pool T2 (Normal)**: 哥布林、獸人，少量搭配。
*   **Pool T3 (Hard)**: 複合兵種，數量多。
*   **Pool Elite**: 只有一隻強力精英怪。

### B. 生成權重 (Spawn Weights)
隨著樓層 (Floor Index) 增加，抽中高難度池的機率提升。
*   *F = 當前樓層 (1~10)*
*   **Floor 1**: 80% T1, 20% T2
*   **Floor 5**: 50% T2, 50% Elite (中BOSS)
*   **Floor 9**: 30% T2, 70% T3

### C. 房間類型決定 (Room Type Determination)
當玩家在上一層過關並生成「門」時，系統會預先決定下一層這三扇門背後是什麼：
*   **戰鬥 (Battle)**: 最常見 (60%)。
*   **精英 (Elite)**: 高風險高報酬 (15%)。
*   **商店 (Shop)**: 花費 GOLD 購買卡牌/升級 (10%)。
*   **事件/寶箱 (Event)**: 回血、獲得遺物 (15%)。

### D. 實作方式 (Implementation)
建立一個 `DungeonManager` (Autoload)：
*   維護 `current_floor`。
*   擁有 `generate_next_room_choices()` 方法，回傳 3 個 `RoomData`。
*   每個 `RoomData` 包含：`type` (Battle/Shop...), `difficulty_level`, `enemy_layout_id`。

---

## 7. 敵方數值成長系統 (Stat Scaling - Buriedbornes Style)

參考《Buriedbornes》的無限成長機制，敵人不能只有固定的數值，必須隨著樓層膨脹。

### A. 基礎成長公式 (Scaling Formula)
敵人的最終數值由 **基礎值 (Base)** 與 **樓層係數 (Floor Factor)** 決定。

```gdscript
# 虛擬代碼
func calculate_enemy_stats(base_enemy_data: EnemyCard, floor: int):
    # 成長幅度：每層增加 10% ~ 20% 數值
    var growth_rate = 0.15 
    var floor_multiplier = 1.0 + (floor * growth_rate)
    
    # 階段修正：每過一個大循環(10層)，怪物強度額外跳躍一次
    var world_rank = floor / 10
    var rank_multiplier = 1.0 + (world_rank * 0.5)

    final_hp = base_enemy_data.hp * floor_multiplier * rank_multiplier
    final_atk = base_enemy_data.atk * floor_multiplier * rank_multiplier
```

### B. 詞綴系統 (Affix System) - 變異怪
為了增加重複遊玩性，生成的敵人有機會獲得「詞綴 (Affix)」，類似 Buriedbornes 的 "Fierce", "Giant" 等前綴。

*   **機制**: 在生成敵人實體時，隨機 `roll` 一個詞綴並套用。
*   **範例詞綴**:
    *   **強壯的 (Sturdy)**: HP x 1.5, 體型變大。
    *   **兇猛的 (Fierce)**: ATK x 1.5, 但 HP x 0.8。
    *   **迅速的 (Swift)**: 移動力 +1 (如果機制允許)。
    *   **硬化的 (Armored)**: 受傷減免 20%。
*   **顯示**: 敵人的名稱顯示為「強壯的 史萊姆」，並且模型可能會有顏色濾鏡 (Modulate) 變化（如紅色代表兇猛，綠色代表強壯）。

### C. 實作整合
這些邏輯應封裝在 `EnemyFactory` 或 `MapLoader` 中：
1.  從 `MapGenerator` 取得敵人 ID。
2.  讀取 `EnemyCard` (Resource)。
3.  計算 `current_floor` 的數值倍率。
4.  隨機附加 `Trait/Affix`。
5.  實例化敵人並寫入最終數值 (`current_health`, `attack_damage`)。

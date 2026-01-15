# 技術規格書：移動型戰技卡牌 (Movement Skill Implementation)

## 1. 概述 (Overview)
本文件規劃了一種新型「移動戰技」卡牌的實作方案。
此類卡牌允許玩家選擇一名單位（自身或盟友），使其立即獲得一次額外的移動機會。當該單位移動到目的地後，會自動觸發後續的技能效果（如周圍範圍傷害），且**不會**強制結束回合或觸發常規的攻擊結算。

### 核心需求
1.  **目標選擇**：卡牌首先像 Buff 一樣選擇一個單位（Targeting: Ally/Self）。
2.  **移動階段**：被選中的單位進入移動模式，玩家點擊目的地進行移動。
3.  **無縫銜接**：移動不消耗 Action Point，不結束回合。
4.  **後續效果**：移動落地後，立即以新位置為中心觸發第二段技能（如周圍 150% 傷害）。

---

## 2. 數據結構變更 (Data Schema)

### 修改 `Scripts/SkillSystem/SkillCard.gd`
為了在單張卡牌資源中同時定義「選人」和「落地後的效果」，我們需要在 `SkillCard` 中擴展欄位。

```gdscript
extends BaseCardData
class_name SkillCard

# ... 原有屬性 (soul_cost, targeting, effects 等) ...
# 原有的 'targeting' 用於第一階段：選擇要移動的單位 (例如：射程 3 內的盟友)
# 原有的 'effects' 用於第一階段效果 (通常為空，或加個加速 Buff)

@export_group("Movement Skill Settings")
@export var is_move_skill: bool = false # 標記這是否是一張移動技卡牌

# 第二階段：落地後的目標判定 (例如：自身周圍 1 格)
@export var post_move_targeting: TargetingDefinition 

# 第二階段：落地後的實際效果 (例如：造成 150% 攻擊力傷害)
@export var post_move_effects: Array[EffectDefinition] = []
```

---

## 3. 系統架構修改 (System Architecture)

### A. `GridSelector.gd` (狀態管理)
`GridSelector` 負責處理點擊與移動邏輯。我們需要讓它知道現在處於「特殊移動模式」，從而在移動完成後**暫停**回合推進。

1.  **新增變數**：
    *   `var pending_special_move_card: Resource = null`：用來儲存正在執行的卡牌引用。

2.  **新增方法**：
    *   `start_special_move(entity: GridEntity, card: Resource)`：
        *   強制選取該單位 (`select_entity(entity)`).
        *   儲存 `card` 到 `pending_special_move_card`.
        *   (選用) 顯示特殊的移動範圍指示器。
    
3.  **修改 `_on_movement_completed`**：
    *   **舊邏輯**：移動完成 -> `TurnManager.advance_turn()`.
    *   **新邏輯**：
        ```gdscript
        func _on_movement_completed(entity: GridEntity, _final_pos: Vector2i) -> void:
            if entity == selected_entity:
                clear_selection()
            
            # 檢查是否正在進行特殊移動
            if pending_special_move_card != null:
                print("[GridSelector] Special move completed. Triggering post-move effects.")
                # 通知 SkillManager 繼續執行第二階段
                SkillManager.complete_special_move(entity, pending_special_move_card)
                
                # 清除狀態
                pending_special_move_card = null
                
                # 重要：這裡 RETURN，不呼叫 advance_turn()
                return

            # 常規邏輯：推進回合
            if TurnManager and TurnManager.current_faction:
                if entity.faction == TurnManager.current_faction:
                    TurnManager.advance_turn()
        ```

### B. `SkillManager.gd` (流程控制)
`SkillManager` 是整個流程的導演。

1.  **修改 `cast_skill`**：
    *   當玩家對著某個單位施放卡牌時：
    *   檢查 `card.is_move_skill`。
    *   若為 `true`：
        *   不直接執行 `_apply_effects`。
        *   改為呼叫 `GridSelector.start_special_move(target_entity, card)`。
        *   (UI) 顯示提示：「請選擇移動目的地」。

2.  **新增 `complete_special_move(entity, card)`**：
    *   被 `GridSelector` 在移動結束後呼叫。
    *   **執行第二階段**：
        *   使用 `card.post_move_targeting` (例如 SelfSurround) + `entity` (新位置) 計算受擊敵人。
        *   對這些敵人執行 `card.post_move_effects` (例如 Damage 150%)。
    *   **信號**：發送 `skill_cast_completed`。

---

## 4. 具體交互流程 (User Journey)

1.  **施法 (Cast)**：
    *   玩家從手牌拖曳「跳斬卡 (Leap Slam)」。
    *   `Targeting` 設定為 `SINGLE` (Ally)。
    *   玩家將卡牌放置在 `Unit 001` 身上。

2.  **狀態切換 (Phase Switch)**：
    *   `SkillManager` 判定這是移動卡。
    *   `GridSelector` 鎖定 `Unit 001` 為選取狀態。
    *   地圖上顯示 `Unit 001` 的可移動綠色格子。

3.  **移動 (Move)**：
    *   玩家點擊 (0, 3) 的空地。
    *   `Unit 001` 執行移動動畫，走到 (0, 3)。

4.  **結算 (Resolve)**：
    *   移動結束。`GridSelector` 攔截了回合結束信號。
    *   `SkillManager` 接手。
    *   讀取 `post_move_targeting` (SelfSurround)。
    *   偵測到 (0, 3) 周圍有 2 個敵人。
    *   讀取 `post_move_effects` (Damage 150%)。
    *   敵人受到傷害。

5.  **後續 (End)**：
    *   `SkillManager` 完成工作。
    *   控制權回到玩家手上 (`PLAYER_TURN`)，回合**沒有**結束。
    *   玩家可以繼續操作其他單位或該單位 (視 Action Point 規則而定，目前設計為免費行動)。

---

## 5. 資源範例 (Example Resource)

### `Skill_LeapAttack.tres`
*   **Base Info**:
    *   `is_move_skill`: **true**
    *   `targeting`: `Targeting_AllyRange3` (內嵌或引用)
        *   *Scope*: Single
        *   *Filter*: Ally
    *   `effects`: [] (第一階段無效果，或可加個 '準備移動' 的特效)
*   **Post Move Info**:
    *   `post_move_targeting`: `Targeting_SelfSurround` (內嵌)
        *   *Scope*: Area Square (Radius 1)
        *   *Origin Is Self*: true
        *   *Filter*: Enemy
    *   `post_move_effects`: [`Effect_Damage150`] (內嵌)
        *   *Type*: Damage
        *   *Calculation*: Percent Caster Atk
        *   *Value*: 1.5

---

## 6. 潛在問題與解決 (Edge Cases)

*   **取消移動？**：如果玩家進入移動模式後後悔了怎麼辦？
    *   *解法*：點擊右鍵或 ESC。`GridSelector` 需要處理取消邏輯 -> 如果 `pending_special_move_card` 不為空，則取消移動模式，退還卡牌 (Refund Cost)，回復到 IDLE 狀態。
*   **移動力不足？**：如果單位被定身 (Rooted) 或移動力為 0？
    *   *解法*：`GridSelector` 在 `start_special_move` 時會計算 `reachable_cells`。如果列表為空，應立即報錯並取消施法，退還卡牌。

此架構不需要修改 `TurnManager` 或 `UnitMovementController` 的核心邏輯，僅透過 `GridSelector` 的信號攔截與 `SkillManager` 的流程分段即可實現。

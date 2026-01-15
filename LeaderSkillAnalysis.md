# 角色特性 (Leader Skill) 機制分析與實作規劃

## 1. 《召喚圖板》Leader Skill 機制分析

在《召喚圖板 (Summons Board)》中，**Leader Skill (隊長技能)** 是隊伍構建的核心。它通常由三個部分組成：**對象 (Scope)**、**條件 (Condition)** 與 **效果 (Effect)**。

### 結構拆解
*   **對象 (Scope)**：技能生效的目標群體。
    *   屬性：火、水、木、光、暗。
    *   類型：攻擊型、體力型、平衡型...等。
    *   全體：不分屬性與類型。
*   **條件 (Condition)**：觸發效果所需的狀態。
    *   **常駐 (Passive)**：無條件生效 (例：火屬性攻擊力 2倍)。
    *   **HP 條件**：HP x% 以上/以下 (例：HP 70% 以上時攻擊力 3倍)。
    *   **Combo 條件**：連擊數 x 以上 (例：4 Combo 以上時攻擊力 2.5倍)。
    *   **同時攻擊**：特定條件的隊友同時攻擊時。
    *   **特殊行動**：如迴避成功時、反擊時。
*   **效果 (Effect)**：滿足條件後獲得的加成。
    *   **數值倍率**：攻擊力 xN、HP xN、回復力 xN。
    *   **減傷**：受到的傷害減少 x%。
    *   **特殊機制**：每回合回復 HP、吸血、復活、追擊傷害。

### 運作邏輯範例
> 「**火屬性**之味方，**HP 70%以上**時攻擊力 **3倍**，**9 Combo以上**時攻擊力 **2倍**」
> *   這是一個複合條件技能。
> *   若火屬性隊友 HP > 70% 且 Combo > 9，則獲得 3 x 2 = 6 倍攻擊力加成。

---

## 2. 專案實作規劃：Character Trait (角色特性)

為了在我們的專案中實踐此機制，我們將建立一個基於 **Resource** 的模組化系統。配合 **隊長系統 (Leader System)**，只有被指派為「隊長」的單位，其特性才會對全隊生效。

### A. 資料結構設計

我們將新增一組 Resource 腳本來定義特性。

#### 1. `TraitData.gd` (Resource)
特性的容器，定義了這個特性的描述與包含的效果。
*   `trait_name`: String
*   `description`: String
*   `icon`: Texture
*   `effects`: Array[TraitEffect]

#### 2. `TraitEffect.gd` (Resource)
定義單一效果的邏輯 (條件 + 數值)。
*   **Target (目標)**:
    *   `target_faction`: Self / Ally / Enemy / All
    *   `target_unit_id`: (Optional) 特定單位 ID
*   **Conditions (觸發條件)**:
    *   `condition_type`: NONE, HP_THRESHOLD, COMBO_COUNT, FACTION_MATCH...
    *   `condition_value`: float (例如 0.7 代表 70%, 4 代表 4 Combo)
    *   `comparison`: GREATER, LESS, EQUAL
*   **Bonuses (加成效果)**:
    *   `stat_type`: ATTACK_MULTIPLIER, DAMAGE_RECEIVED_MULTIPLIER, CRIT_RATE_FLAT...
    *   `value`: float (例如 1.5 代表 +50% 或 1.5倍)

### B. 系統整合

#### 1. 賦予特性
*   修改 `CharacterData.gd`，新增 `trait: TraitData` 變數。
*   在 `UnitCard.gd` 中新增 `trait` 欄位，並在單位生成時傳遞給 `CharacterData`。

#### 2. 隊長系統 (`PartyManager`)
引入「隊長欄位」概念，確保只有特定單位的特性生效。
*   **修改 `PartyManager.gd`**：
    *   新增 `leaders: Array[CharacterData]` (為了彈性，使用陣列，雖然目前 size 為 1)。
    *   新增方法 `set_leader(index: int, character: CharacterData)`。
    *   新增方法 `get_active_traits() -> Array[TraitData]`：返回當前所有隊長的特性列表。
    *   **欄位邏輯**：隊伍列表的第一位 (`party[0]`) 預設為隊長。

#### 3. 數值計算 (`AttributeSystem`)
在 `AttackManager` 或 `TurnManager` 計算傷害時，**動態查詢**隊長的 Trait。

**攻擊力計算流程 (TurnManager / AttackManager)**:
1.  取得基礎攻擊力 (`attacker.character_data.attack_damage`)。
2.  **獲取生效特性**：呼叫 `PartyManager.get_active_traits()`。
3.  檢查每個 `TraitData` 中的每個 `TraitEffect`。
4.  **判定條件**：
    *   檢查受影響者 (`attacker` 或 `target`) 是否符合 `Target` 範圍 (例如：是否為隊長的我方單位)。
    *   檢查環境條件 `condition_type` (例如：當前 Combo > 4)。
    *   檢查狀態條件 (例如：HP > 70%)。
5.  **應用加成**：
    *   若符合，將 `value` 累乘到 `final_multiplier`。

### C. UI 實作與擴充

#### 1. DeploymentMemberCard (單位卡片)
修改卡片以支援點擊切換顯示 Leader Skill。

*   **場景修改**：
    *   新增 `LeaderSkillBox` (VBoxContainer)，內含：
        *   `SkillNameLabel` (Label)
        *   `SkillDescLabel` (Label, autowrap=true)
    *   預設隱藏 `LeaderSkillBox`。
*   **腳本修改 (`DeploymentMemberCard.gd`)**：
    *   實作 `toggle_info_display()`：切換顯示「基礎數值(HP/ATK)」與「Leader Skill 資訊」。
    *   **互動邏輯**：
        *   使用 `_gui_input(event)` 監聽點擊 (MouseButton Release)。
        *   **解決衝突**：Godot 的 `_get_drag_data` 會在滑鼠按下並移動時觸發拖曳；若按下後原處放開，則觸發 Click。兩者不衝突。
    *   **資料綁定**：在 `setup_with_data` 時讀取 `trait` 資訊並填入 UI。

#### 2. DeploymentUI (部署介面)
新增「隊長欄位」的視覺呈現。

*   **場景修改**：
    *   在 `LeftPanel/VBox` 中，於 `ScrollContainer` 上方新增一個 `LeaderContainer` (PanelContainer)。
    *   加上標題 "Leader"。
*   **邏輯修改 (`DeploymentUI.gd`)**：
    *   在初始化隊伍列表時，將隊伍的第一個成員 (`party[0]`) 實例化並放入 `LeaderContainer`。
    *   其餘成員 (`party[1..n]`) 放入下方的 `ScrollContainer/MemberList`。
    *   (可選) 支援拖曳交換隊長：這屬於進階功能，目前先實作顯示分離。

### D. 執行步驟

1.  建立 `TraitData` 與 `TraitEffect` 的 Resource 腳本。
2.  更新 `CharacterData` 與 `UnitCard` 以支援 Trait。
3.  修改 `DeploymentMemberCard.tscn` 與 `.gd`，實作點擊切換資訊功能。
4.  修改 `DeploymentUI.tscn` 與 `.gd`，實作獨立的 Leader 欄位顯示。
5.  修改 `PartyManager` 實作隊長邏輯與 `get_active_traits`。
6.  在 `AttackManager` 與 `TurnManager` 整合數值計算。

請確認這份規劃文檔是否符合您的需求？如果沒問題，我將開始實作資源結構與 UI。

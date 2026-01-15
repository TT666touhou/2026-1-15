# Room Editor & Enemy Customization Upgrade Plan

## 1. Objective
Allow developers to customize individual enemy statistics (Health, Attack, Movement Range) directly within the `RoomEditor` tool. These overrides will be saved in the Room Template and applied when the room is loaded in the game, enabling greater enemy diversity without creating new Resource files.

## 2. Data Structure Changes

### A. RoomTemplate (`Scripts/Map/RoomTemplate.gd`)
*   **Update `entities` Array**: Modify the stored dictionary structure to include an optional `overrides` key.
    *   **Old**: `{ "pos": Vector2i, "card_path": String }`
    *   **New**: `{ "pos": Vector2i, "card_path": String, "overrides": Dictionary }`
*   **Overrides Dictionary Schema**:
    ```gdscript
    {
        "max_health": int,      # Optional: Override Max Health
        "attack_damage": int,   # Optional: Override Attack Damage
        "move_limit": int       # Optional: Override Movement Distance Limit (-1 for default/unlimited)
    }
    ```
*   **Update methods**: Update `add_entity()` to accept the `overrides` parameter.

## 3. Script Changes

### A. GridEntity (`Scripts/Entities/GridEntity.gd`)
*   **New Property**: Add `var move_limit: int = -1` (Default -1 means use `MovementRangeData` settings).
*   **Update `get_reachable_cells()`**: Modify the loop to check `distance > move_limit` (if `move_limit != -1`). This allows restricting an enemy with "Unlimited" movement type to a fixed number of steps.
*   **Helper Method**: Add `apply_overrides(data: Dictionary)` to easily set these values and update `CharacterData` (Health/Attack).

### B. MapLoader (`Scripts/MapLoader.gd`)
*   **Update `instantiate_room()`**:
    *   When iterating through `template.entities`, check if the dictionary has an `overrides` key.
    *   After spawning the entity and calling `setup_character()`, call `entity.apply_overrides(overrides)`.

### C. RoomEditor (`Scripts/Tools/RoomEditor.gd`)
*   **State Management**: Update `placed_entities` dictionary to store the `overrides` data for each instance.
*   **Selection Logic**:
    *   Implement `select_entity(instance)` which highlights the entity and populates the Inspector Panel.
    *   Clicking a cell with an entity should trigger selection.
*   **Inspector Logic**:
    *   Create a UI panel (Inspector) with SpinBoxes for:
        *   `Max Health` (Default: `active_card.max_health`)
        *   `Attack` (Default: `active_card.attack_damage`)
        *   `Move Limit` (Default: -1)
    *   Connecting SpinBox `value_changed` signals to update the selected entity's `character_data` (for immediate visual feedback if bars are visible) and the `placed_entities` storage.
*   **Save/Load**:
    *   Update `_on_save_pressed` to serialize the overrides into the `RoomTemplate`.
    *   Update `_on_load_pressed` to deserialize and apply overrides to the editor instances.

## 4. UI Changes (`Scenes/Tools/RoomEditor.tscn`)

### A. Layout Update
*   **Right Panel (Container)**:
    *   Add a **TabContainer** or **Split View** to separate the "Card List" (Toolbox) and "Entity Inspector" (Properties).
    *   **Entity List**: A `Tree` or `ItemList` displaying all placed entities (e.g., "Goblin [3, 4]").
    *   **Inspector Panel**: A `VBoxContainer` (initially hidden) containing:
        *   Label: "Entity Properties"
        *   HBox: Label "Health", SpinBox `sb_health`
        *   HBox: Label "Attack", SpinBox `sb_attack`
        *   HBox: Label "Move Limit", SpinBox `sb_move`
        *   Button: "Reset to Default"

## 5. Implementation Steps

1.  **Modify `RoomTemplate.gd`**: Update data structure definition.
2.  **Modify `GridEntity.gd`**: Implement `move_limit` logic and `apply_overrides`.
3.  **Modify `MapLoader.gd`**: Integrate override application during spawning.
4.  **Update Editor UI**: Edit `RoomEditor.tscn` to add List and Inspector.
5.  **Update `RoomEditor.gd`**: Implement the selection, editing, and persistence logic.


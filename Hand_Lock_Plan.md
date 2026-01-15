# Hand Interaction Lock Plan

## Objective
When a player uses a "Move Skill" (e.g., Leap Attack), the Hand UI should be temporarily locked (disabled dragging, moved down visually) until the movement action is completed. This enforces the game flow where the player must finish the move before playing another card.

## Implementation Details

### 1. Script: `Scripts/Card/Hand.gd`

*   **New Properties**:
    *   `@export var lock_offset_y: float = 60.0`: Distance to move the hand down when locked.
    *   `var _default_offset_top: float`: To store the original layout position.
    *   `var _tween_lock: Tween`: To manage the animation.

*   **Initialization (`_ready`)**:
    *   Store `offset_top` into `_default_offset_top`.
    *   Connect to `SkillManager` signals:
        *   `skill_cast_started`: Trigger lock if `card.is_move_skill` is true.
        *   `skill_cast_completed`: Trigger unlock.
        *   `skill_cast_failed`: Trigger unlock (safety fallback).

*   **Logic: `_on_skill_cast_started(card, source)`**:
    *   Check `if card.get("is_move_skill") == true`:
        *   Call `set_interactable(false)`.

*   **Logic: `_on_skill_cast_ended(arg)`**:
    *   Call `set_interactable(true)`.

*   **Update `set_interactable(value)`**:
    *   Existing logic: Sets `card.interactable` (which allows hover but disables drag).
    *   **New Logic**:
        *   Kill existing `_tween_lock`.
        *   Create new tween.
        *   If `value == false` (Locked): Tween `offset_top` to `_default_offset_top + lock_offset_y`.
        *   If `value == true` (Unlocked): Tween `offset_top` to `_default_offset_top`.
        *   Use `Tween.EASE_OUT`, `Tween.TRANS_CUBIC` for smooth UI feel.

### 2. Verification
*   **Hover Behavior**: `Card.gd` already handles `interactable = false` by allowing `_handle_mouse_hover_rotation`. This meets the requirement "player can still check and interact with the card by placing mouse above it".
*   **Visual Feedback**: The hand lowers slightly, indicating it's not currently active.

## Summary
This change effectively locks the hand state during the special movement phase managed by `SkillManager` and `GridSelector`, automatically restoring it when the action resolves.


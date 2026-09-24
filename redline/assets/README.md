# assets/

Exported, game-ready art and audio (Art Bible §9). Sources live in `art/`, outside the game import.

- `assets/<district or character>/<subject>_<action>[_variant].png` (snake_case). Sheets are horizontal strips with a fixed cell size.
- Each character sheet gets a `SpriteSheetSpec` (`.tres`) next to it: cell size, origin (bottom-centre, at the feet) and animations. Point `EnemyData.sprite`, or the player visual's `sprite`, at it, and the placeholder drawing is replaced. No code changes.
- Check before committing: `godot --headless res://devtools/content/ValidateContent.tscn`. It runs the Art Bible checks: names, crisp alpha, sheet sizes, palette size and reserved colours.

Currently empty: all art is placeholder (D-026).

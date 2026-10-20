# Vendored and external build inputs (tools/build_assets.sh)

| Input | Where | Status |
|---|---|---|
| Fonts: Jersey10-Regular, PixelifySans, PressStart2P-Regular, Silkscreen-Regular, Silkscreen-Bold | `vendor/fonts/` (from T704), `vendor/fonts/OFL.txt` | vendored (SIL OFL 1.1) |
| /pixel-avatar scripts | `~/.claude/skills/pixel-avatar/scripts` or `PIXEL_AVATAR` (skill root) | external fleet skill, not vendored |
| /pixel-scene scripts | `~/.claude/skills/pixel-scene/scripts` or `PIXEL_SCENE` | external fleet skill, not vendored |
| /pixel-foliage scripts | `~/.claude/skills/pixel-foliage/scripts` or `PIXEL_FOLIAGE` | external fleet skill, not vendored |
| python3 (numpy, pillow), godot 4.7.2 | PATH | system |

The skills are still changing (T712 hands, T715 foliage), so a vendored copy would drift; vendoring them is the owner's call.
`vendor/.gdignore` keeps Godot from importing these copies.

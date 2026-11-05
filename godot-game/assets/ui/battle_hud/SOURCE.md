# 会战 HUD 纸签

`toolbar.png` 是既有 `assets/ui_rpg/ui.png` 的 `Rect2(636,246,67,37)` 裁片，
`paper.png` 是同一原图的 `Rect2(396,31,86,99)` 裁片；两者均使用最近邻放大 3 倍。
来源与许可沿用 `assets/ui_rpg/SOURCE.txt`。没有重画或替换原图。

这是当前 `data/presentation/ui.tres` 和 `scripts/rpg_ui.gd` 所生成纸签的资源化版本。
`battle_hud_theme.tres` 的 normal/hover/pressed/disabled/selected 颜色、纹理边距和
内容边距沿用原实现；`status_paper.tres` 用于计时纸签。独立 PNG 使编辑器无需执行
`_ready()` 或工具脚本就能预览实际像素纹理。

在 Inspector 中编辑 Theme 即可调整本 HUD。如果以后统一修改远征纸签配置，
也应同步本 Theme；当前是可编辑快照，不会在运行中覆盖 Inspector 改动。

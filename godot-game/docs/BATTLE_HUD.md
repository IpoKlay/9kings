# 会战 HUD 编辑与验收

## 三个修改入口

- **位置**：打开 `res://scenes/ui/battle_hud.tscn`，选择
  `BattleActions/StartButton`。直接在 2D 编辑器拖动，或修改 Inspector 的
  Layout → Transform / Offsets。该按钮锚定右下角，父节点不是 Container，
  `trial.gd` 不会重置其坐标和尺寸。它在部署、战斗、结算中分别显示开战、坚守、重新试战。
- **外观**：打开 `res://assets/ui/battle_hud/battle_hud_theme.tres`。
  Button / OptionButton 的 StyleBoxTexture 控制纸签和状态颜色，
  `SelectedBattleButton` 控制选中态；字体引用现有 `game_pixel_font.tres`。
  计时纸签单独使用 `status_paper.tres`。像素来源见同目录 `SOURCE.md`。
- **行为**：`res://scripts/tactical/trial.gd` 的 `bind_hud()` 连接信号，
  `start_or_hold_or_retry()` 处理开战、坚守、重试；`refresh()` 更新数据、文本和可用态。
  不在 `refresh()` 中创建控件或连接信号。

## 场景树

| 节点 | 内容与编辑方式 |
| --- | --- |
| `StatusGroup` | 计时、双方队数、操作/目标提示；直接移动 Label。 |
| `TopActions` | 兵力对比、速度、头像、角色选择、帮助、暂停、菜单；各控件独立锚点。 |
| `DeploymentActions` | 七兵种、标准、山口守阵；仅空部署时显示；移动父组可整体调整。 |
| `RegimentRoster` | 现有十个预备队名额对应的部队纸签；按实际队伍更新名字、士气、选中态；战前有部队及战中显示。 |
| `ReserveActions` | 七兵种预备队按钮，余量及可用态由规则更新。 |
| `BattleActions` | 全军进攻、神力、开战/坚守/重试。StartButton 可自由移动。 |
| `HelpGroup` | `ControlsLabel` 和 `PowerNote`；默认隐藏，点问号打开。 |
| `ResultGroup` | `ResultLabel`；默认隐藏，胜败/超时结算显示。 |

`ReserveActions`、`RegimentRoster` 是 HBoxContainer：选中整行调整位置，
修改 Theme Overrides → Constants → Separation 调整间距；子按钮的宽度在
Custom Minimum Size 中调整。子按钮位置由容器管理，不应逐个拖动。
其它分组均为透明 Control，不接收鼠标事件。只有真实按钮区域拦截点击。
OptionButton 的弹出菜单在打开时正常接收输入。

场景默认预览部署状态。要预览部队栏、帮助或结算，在编辑器临时打开相应节点
Visible；必要时隐藏 DeploymentActions，避免预览时两组重叠。固定节点始终存在，
游戏中会根据当前阶段更新可见性。设计时示例文字和运行时控件是同一批节点。

## 自动化与手动验收

使用工程要求的 Godot 4.7.2：

```sh
godot --headless --path godot-game --script res://tests/tactical/test_battle_hud_layout.gd
godot --path godot-game --fixed-fps 60 --script res://tests/tactical/test_battle_hud_live.gd
```

第一个测试直接加载实际 HUD，检查纸签、节点、鼠标穿透和编辑后保存/重载。
第二个必须有完整工程与图形渲染环境，从主菜单真实按钮进入会战，检查双语、
三个布阵按钮、开战、选队、坚守、帮助、暂停、神力落点、菜单、结算、重试与
单次连接。胜败/超时使用显式 UI 状态夹具，不作为战斗平衡或自然胜利证据。
位置验证写入 `user://` 临时副本，移动 StartButton 96 像素后进入真实控制器，
检查战前、战中位置和点击，结束删除副本，不改正式场景。

GitHub Actions 的 `Native battle HUD` 使用完整仓库，另跑已有七兵种、山口、
途经点、地形回归；产物 `native-battle-hud-evidence` 保存日志、原生截图及编辑器截图。
只有实际成功运行的日志才是通过证据。CI 不是手动拖动编辑器的替代。

人工最终验收：打开 HUD → 拖动 StartButton → 保存 → F5 → 主菜单进入
「军团会战 · RTS」→ 布阵 → 在修改后位置点开战 → 选队坚守 → 重试。
然后按需要恢复布局。现版本没有独立「山口守卫战」菜单，山口守阵位于同一会战部署界面。

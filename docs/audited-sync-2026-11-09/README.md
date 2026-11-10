# 本地差异审核与合并（2026-11-09）

基线：`ae072305ebbc70067a88dfd6b0623690e28ba7de`。对照原目录 `9kings/godot-game` 与 main；不是整目录覆盖。原始“15 个新增、11 个差异”只统计 scripts/scenes/data/assets，未包括 tests/tools 与本地输出。

## 合入内容

- 单位图集：8 张 PNG + units.json + unit_atlas.gd；96 张已有单位源图的哈希和源像素均一致。带回可再生成的 tools/build_unit_atlas.py（开发工具，需要 Pillow），未增加兵种或改原画。
- 原静态缓存改为每个战场显示节点独有的实例，退出场景释放；图集读取与脚下阴影接到 main 的最新 trial_field.gd，保留策略地图、受阻动作和双方闪白接口。
- whiteboard_battlefield.tscn / whiteboard_field.gd 接入已存在于 main 的草地图片，保留地图范围、单位比例、寻路和新策略主菜单入口。此场景是旧会战场景；不替换新策略地图。独立多排预览隐藏该底层场景，仍显示自己的同材质草地，不重复绘制。
- trial.gd 只合入按存活士兵实际命令显示“冲锋／分队执行／坚守”的提示及选中整队时的冲锋提示。
- regiment_soldiers.gd 只合入 H 坚守解除旧盾墙行军控制的修复；保留盾姿、最新路径/策略回调、受阻恢复和敌人占位检查。
- 更新两份已经落后的旧会战测试：先确认主菜单进入 StrategyBattle，再单独建立 WhiteboardBattle 测试旧会战操作，避免把旧入口假设作为生产要求。测试输出移至忽略目录，不改历史截图。

## 审核后不合入

| 原目录内容 | 决定与依据 |
| --- | --- |
| battle_hud_backgrounds.gd | 不合入。它把所有纸签背景移到父节点先画，依赖当前按钮互不重叠；编辑器移动按钮造成重叠后，背景与文字的原生遮挡顺序不能保证；也只缓存初始化的样式。保留 Godot 原生控件绘制和自由布局。 |
| UI 图集的 4 个文件，以及 battle_hud.tscn / battle_hud_theme.tres 的接入差异 | 不合入。本次 HUD 只用其中 toolbar，原纹理 201×111 RGBA 约 87KB，整张图集为 2048×1024 RGBA 8MiB；撤掉背景合批后，替换同一共享纹理不能证明收益。全部原文件留在原目录，未删除。 |
| main.gd | 保留 main 的 StrategyBattle 入口，不退回旧白板入口。 |
| shield_wall.gd | 保留 main 的列数不超过实际人数修复。 |
| soldier_charge.gd / tactical_trial.json | 保留 main 的盾墙、长矛阻力、穿透上限、2.6 秒缺口保持等新代码与参数。 |
| trial.gd / trial_field.gd / regiment_soldiers.gd 的其余差异 | 不覆盖；这些差异会删除策略模式接入、双方闪白或冲锋修复。 |

## 实际验证

- 96 张源图：哈希与原始 PNG 区域逐字节比对；引擎导入后的可见像素和 alpha 相同。Godot 默认透明边缘修正在 3 张图的完全透明 RGB 上产生差异，不影响可见像素；不隐瞒该区别。
- 576 组单位图集采样：全部 8 方向、动画帧、6 组缩放/刚体旋转组合，画面逐字节一致。
- 13 组实际战场画面对照：3 档缩放、9 个交战时点、石化，原纹理与图集画面逐字节一致。
- test_sync_assets：295 项通过，包含状态提示、移动开战按钮后 refresh 不复位、草地场景、重试和退出释放缓存。
- test_impact_feedback：21 项通过，含图集闪白与原图遮罩完全一致、只生成单张角色表大小的遮罩；独立多排场景实际截图能看到进攻骑兵和受击步兵同时闪白。
- test_shield_columns：27 项通过，新增正在行军的盾墙按 H 后不被旧命令重新推进。
- test_command_route_input：28 项通过；中文/英文、选兵、路点拒绝后修正、途中改令、坚守、重试，渲染窗口里的引擎输入事件。
- test_whiteboard_battle：83 项通过；草地、部署、地图边界、缩放、实际双方伤害、胜利分支与重试。胜利分支使用清除敌军的测试条件，不冒充自然打完一局。
- test_contextual_ui：27 项通过，正常主菜单进入新策略模式、选择村民/建筑和操作面板；有渲染截图。
- test_personal_charge（35 项）、test_charge_readability、test_cavalry_depth（532 项）、test_formation_camera、test_economy_match 均通过。经济战局结算属于无窗口规则测试。
- test_cavalry_depth_scene：9 项通过，暂停、反馈开关、镜头开关、重试后恢复 64 人且清空接触历史。

以上输入回归是引擎事件或按钮信号自动测试；本轮系统操作工具连接超时，没有新增系统鼠标人工实玩或编辑器拖拽验收。

## 性能与资源代价

条件：本机 Apple M4 / 16GB、Godot 4.7.2 Compatibility，实际 1280×720，114 人起始、无扩军，60 FPS 限帧、关闭 VSync，seed 20261109，相同草地/镜头/开战命令。先原纹理、后图集，各预热 2 秒并正常运行 30 秒；计时内没有强制绘制、截图或手动推进模拟。

| 指标 | 原纹理 | 图集 |
| --- | ---: | ---: |
| 平均帧耗时 | 16.655ms | 16.657ms |
| 第 95 百分位帧耗时 | 18.048ms | 18.113ms |
| 超过 50ms | 0 | 0 |
| 绘制次数中位数 | 235 | 135 |
| 引擎纹理分配记录 | 794,841,571B | 819,308,451B |
| 退出战场后纹理分配 | 121,826,747B | 121,826,747B |

绘制次数下降不等于流畅度提升；本次流畅度没有明显变化。图集原始 RGBA 页面 157.5MiB，原源图合计 140MiB；驱动监测差值约 23.33MiB。已有全兵种加载范围保持原样，不宣称已完成按兵种加载优化。每页最高 8192 像素，仅本机验证；其他平台需单独确认。

详细数值见 performance.json。只有各 30 秒，不能证明每分钟卡顿门槛、长时间稳定性或输入延迟≤100ms；未独立测 GPU 时间与加载耗时。没有做千人、攻城扩展或 Windows 导出验收。

## 复查入口

Godot 原生工程 `godot-game/project.godot`；常规入口仍是主菜单。独立多排骑兵预览为 `res://scenes/previews/cavalry_depth.tscn`。图集重现/采样与规则测试在 `godot-game/tests/tactical/`，真实时间对照运行 `benchmark_sync.gd`。本机日志及截图放 `output/audited-sync/`，不提交录像/构建包。

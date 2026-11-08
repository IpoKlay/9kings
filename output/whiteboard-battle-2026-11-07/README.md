# 白板地图收尾 · 2026-11-07

已完成本次地图范围。正常 Godot 主菜单「军团会战」进入 3200×3200 纯白战场；完整战斗复现目标仍未完成。

入口：`godot-game/project.godot` → `scenes/main.tscn` → `%TacticalTrial` → `WhiteboardBattle`。场景为 `scenes/battlefields/whiteboard_battlefield.tscn`。旧美术场景、山口及攻城实现保留。

## 参数与操作

唯一地图参数源：`godot-game/data/presentation/whiteboard_map.tres`。

| 项目 | 当前值 |
| --- | --- |
| 地面/显示边界 | Rect2(0, 0, 3200, 3200)；恒等投影 |
| 敌军 / 缓冲带 / 我军 | y=0..1300 / 1300..1900 / 1900..3200 |
| 相机边距 | 200 |
| 默认缩放 / Tab 全览 | 1.0 / 0.2375 |
| 默认镜头中心 | (1600, 2250) |
| 单排步兵屏幕阵宽 | 13.49%，沿用既有兵数及尺寸 |

中键拖动、滚轮缩放、Tab 全览/恢复；沿用部署、选队、路线、开战、暂停及重试。地图无旧岩石碰撞或装饰地形。上下近距部署是本项目现有选择，**没有实现原作四边随机部署**。修改资源后重建/重试战斗生效；不承诺战斗中实时改尺寸。

## 修正与验证

失败根因是本机 Godot 对 `const MAP.values` 链式访问使用了旧编译值：测试把资源改为4000，规则仍读3200。规则和画面改为运行时读取同一 Resource；没有改默认3200或删弱尺寸测试。测试现在直接断言4000边界、三段部署区、双方预设位置，再恢复并验证3200。

- 无窗口专项：**78 checks，0 failures，exit 0**，见 [focused-headless.log](focused-headless.log) 与 [engine-validation-headless.json](engine-validation-headless.json)。
- 真实窗口专项：**82 checks，0 failures，exit 0**，见 [visible-run.log](visible-run.log) 与 [engine-validation.json](engine-validation.json)。从正常菜单注入鼠标事件；其余操作混合真实输入与按钮信号，非人工游玩声明。
- 覆盖：正常入口、尺寸同源、可部署范围、越界命令、无岩石阻挡、镜头拖动/缩放/全览恢复、路线、暂停、真实接战、重试、山口切换及资源尺寸变更/恢复。
- 首次双方近战伤害在约4.55模拟秒内出现。胜利/重试使用明确清除敌人的测试夹具，**不是自然打完整场的证据**。
- 已有专项结果沿用：square_overview 0失败、square_input 0失败、editor_map 21项0失败；不重复跑广域套件。

复现（工作目录为项目根目录）：

```sh
/Users/ip/Downloads/Godot.app/Contents/MacOS/Godot --headless --path godot-game --script tests/tactical/test_whiteboard_battle.gd
/Users/ip/Downloads/Godot.app/Contents/MacOS/Godot --path godot-game --resolution 1920x1080 --position 0,0 --always-on-top --script tests/tactical/test_whiteboard_battle.gd
```

## 真实渲染截图

- [默认视角 default.png](default.png)
- [全览 overview.png](overview.png)
- [实际接战 combat.png](combat.png)
- [正常菜单 menu.png](menu.png)

以上为Godot窗口实际渲染的1920×1080 PNG；同目录 `*-field-native.png` 为原生战场子视口读回。不是生成图，也不是人工编辑器截图。截图已检查：白色正方形、灰色外部、部署虚线、可读原像素单位；接战截图镜头未涵盖全部后排。

## 原作证据与边界

[map-evidence.json](map-evidence.json) 保存旧公开脚本绝对路径、SHA-256、行号及短摘录：

- `/private/tmp/sword-banner-reference/analysis/scripts/battle_tilemap_generator.gd:499–500,625–627`：半宽高1600、完整边界(-1600,-1600,3200,3200)。这是3200尺寸的直接来源。
- 同目录 `battle_manager.gd:15–25,85–95`：四边部署区及随机相对边；241–250为初始部署镜头；253–268为地形生成调用。
- 同目录 `rts_camera.gd:7–14,169–182,203–220`：200边距、原缩放档位、镜头边界及滚轮/中键。

这些属于20260409旧公开包源码证据，不是最新Steam实测。本项目平移坐标、纯白底、恒等投影、固定上下布局和Tab适配属于当前设计选择。没有取得或运行最新Steam版；第三方分析目录只用于追溯，不是运行依赖，未复制完整第三方源码。

## 修改与保留

本轮白板累计文件清单及当前SHA-256见 [validation.json](validation.json)：新增白板参数、场景、规则、画面和专项测试；接入main/trial/trial_field；四个旧测试显式使用原美术地图夹具。之前对旧选择/路线测试的迁移保留，失败基线见 `before-*.log`、`baseline-comparison.json` 及 `before/`；不把旧断言迁移冒称为战斗修复。

本次最后修正只动白板规则、白板画面及白板专项测试。`preserved-sha256.json` 中8项全部匹配，含旧square/roman_pass场景、square/pass/siege规则及视图资源；范围不等于对所有贴图音频逐项建立了哈希基线。没有覆盖旧美术或清理其他开发更新。

## 已知限制

- square_overview 虽断言通过，仍有2个ObjectDB及1个resource退出警告，原日志保留。
- `test_square_battle.log` 只有启动记录，检查时对应进程已不存在；结果未完成，未重跑。历史 `output/combat-core-2026-11-07/validation.json` 记录的三项旧失败及退出警告也未在此修复或重验。
- 第一次修正后窗口运行在默认1280×720停于菜单截图后，未产出结果，已停止本次拥有的进程；显式1920×1080重跑通过。默认窗口尺寸下的完整新验证仍未完成；中断日志为 `visible-run-interrupted.log`。
- 没有实际人工编辑器交互；editor_map为自动化场景检查。没有视频、导出、推送、性能重构、额外模型或代理调用。
- 本次交付仅结束白板地图验证/修正/文档周期，不代表完整战斗目标完成。

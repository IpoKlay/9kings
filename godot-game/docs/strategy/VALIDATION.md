# 验证记录 · 2026-11-09

环境：Linux，Godot 4.7.2 stable。渲染使用 Xvfb + OpenGL Compatibility / llvmpipe。无声卡，窗口验收使用 Dummy 音频；未验证音频输出。早期烟雾测试使用4.6，最终检查改用工程要求的4.7.2。

| 检查 | 结果 | 范围 |
| --- | --- | --- |
| `tests/strategy/test_strategy.gd` | 30项通过 | 开局、独立单位、6–11队分行、43人溢出编组、多数阵型、伤害公式、悬崖、实际行军、果树双资源、建筑影响力、施工、生产、晋升同步、丘陵构建、中断、城镇失败 |
| `tests/strategy/test_strategy_combat.gd` | 20项通过 | 加算攻击/减伤、丘陵骑兵、朝向限制、箭雨冷却、精锐门槛、攻城锤、破门导航、修复、攻城塔装载/登墙/通行层、胜利 |
| `tests/strategy/test_strategy_ui.gd` | 0失败 | 正常菜单鼠标入口、原生地形/面板、鼠标单兵选择与右键实际到达、重试 |
| `tests/strategy/test_strategy_live.gd` | 通过 | 1800个60Hz步、30秒正常规则循环，敌军主动推进并接战 |
| `tests/tactical/test_personal_movement.gd` | 17项通过 | 旧模式单兵移动回归 |
| `tests/tactical/test_personal_charge.gd` | 37项通过 | 旧模式独立冲锋回归 |

规则复现：`godot --headless --path godot-game --script res://tests/strategy/test_strategy.gd`，其他脚本替换路径。窗口输入/截图：不加 `--headless` 运行 UI 脚本；Linux 截图默认写 `/tmp/strategy-ui.png`。

30秒运行记录仅证明推进和接战，不是完整三波真人试玩、不代表性能基准。胜负、生产、研究与攻城边界由独立场景夹具覆盖；不能当作已人工完整通关。首轮攻城检查发现返回值始终为true，已改为仅成功下令时返回true并复测。

原生窗口已实际渲染并检查截图；原始截图保存在本次运行环境 `/tmp/strategy-ui.png`，不作为源码上传。可用上述 UI 测试重新生成。

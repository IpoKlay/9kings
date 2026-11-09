# 验证记录 · 2026-11-10

环境：Linux，Godot 4.7.2 stable，OpenGL Compatibility / llvmpipe 原生窗口，Xvfb 显示。音频使用 Dummy；没有本轮音频输出或 Windows 实机验证。

| 脚本 | 结果 | 覆盖 |
| --- | --- | --- |
| `test_economy_opening.gd` | 23项通过 | 即时开局、6村民、手动生产、选定建筑绑定、取消退款、建筑摧毁中止研究、村民施工、AI招募/延迟出击/超过三次进攻/生产建筑破坏、城镇胜负 |
| `test_contextual_ui.gd` | 27项通过 | 正常菜单鼠标入口、旧HUD隐藏、无选择无右栏、村民建造图标、实际前往采集、Esc清空/不暂停/不撤回任务、城镇和军营不同生产栏、真实鼠标排队、Esc取消放置不扣费、村民建成房屋、摧毁选择清理、重试 |
| `test_strategy.gd` | 30项通过 | 21人集结、43人溢出与多数阵型、分行、伤害加算、移动/悬崖、双资源、施工影响力、生产、晋升、丘陵阵型和受击中断 |
| `test_strategy_combat.gd` | 20项通过 | 护甲减伤、骑兵朝向/丘陵、箭雨、精锐限制、破门、攻城器修复、装载登墙、墙面通行和城镇胜利 |
| `test_economy_match.gd` | 完整脚本对局胜利 | 正常起始资源，采集→生产村民/军队→三级晋升→进攻→摧毁敌城镇，200.97模拟秒获胜，我方城镇1200生命、18单位存活；没有额外赋予资源 |
| `test_strategy_live.gd` | 210秒循环通过 | 60Hz共12600步，开局保护期没有派兵，随后AI实际行军和接战；无人操作样本中的村民阵亡，不作为经济平衡通过依据 |

复现：`godot --headless --path godot-game --script res://tests/strategy/test_contextual_ui.gd`，其他脚本替换文件名。`test_strategy_ui.gd` 保留为新UI测试的兼容入口，不重复计数。

真实窗口执行 UI 脚本（去掉 `--headless`）生成 `/tmp/contextual-opening.png`、`contextual-villager.png`、`contextual-barracks.png`、`contextual-cleared.png`。已观察无选择、村民建筑网格、军营生产与研究、Esc清空四种状态。首次画面发现建筑图标的价格溢出按钮，已增加格高、缩小图标并复验。

完整脚本对局只证明这一套固定操作可以走通，不是玩家试玩评价或难度平衡结论。

该轮没有宣称完全复现《帝国时代4》，没有完成长局平衡或完整采集/建造型AI。窗口测试退出时仍有少量ObjectDB/资源引用警告，未记作规则断言失败；未发现运行中的脚本异常。原始日志在本次运行环境 `/tmp/context*.log`、`/tmp/economy-opening.log`。

## 平滑移镜与实体阵型验证

- `test_formation_camera.gd`：19项检查，覆盖加速/减速/停止、30Hz与120Hz位移一致、窗口外无边缘输入、对角限速、小数相机位移、21人实心三角形、散阵间距、圆阵朝外、顶部提示、2.5秒半条、暂停、5秒完成计时、真实21士兵走到阵位、新命令中断。
- 修复实机变阵发现的提前停步：原通用移动会因为附近同伴已经停止而清空路径；阵位移动现在需抵达自己的位置，不能靠近同伴就结束。
- Linux Godot 4.7.2 原生窗口执行新脚本，观察 `/tmp/contextual-wedge.png`、`contextual-scatter.png`、`contextual-progress.png`；通过正常主菜单进入RTS，测试兵力由脚本创建。截图是引擎实际渲染，未提交重复图片到源码。
- 回归：strategy 30、strategy combat 20、contextual UI 27、personal movement 17、personal charge 37检查通过。新脚本有窗口与headless两种运行，不重复计数。
- 尚未做Windows实机或人工手感评价。原有退出时ObjectDB/资源引用警告仍存在；本轮未改变其生命周期。

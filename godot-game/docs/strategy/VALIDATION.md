# 2026-11-10 本轮：城镇、探索与测试经济

运行环境为当前容器 Godot 4.6.3 stable，Linux，原生OpenGL Compatibility/llvmpipe窗口。Godot AI插件要求4.7，未用于本轮验证；没有Windows实机结果。

| 脚本 | 结果 | 主要证据 |
| --- | --- | --- |
| test_expansion.gd | 94项通过 | 新开局/四环分布/营地规模、视野记忆、即时生产/三资源扣费/集结令、五级城镇效果、实际克制与冲锋伤害、果树双收益、战利品只领一次与奖励排除精锐 |
| test_expansion_ui.gd | 17项通过 | 正常主菜单入口，真实鼠标选建筑/右键设集结/点击生产、单兵数据、同队伍指令合并、士兵加速、攻击移动颜色、Esc、失去视野禁止锁定、真实点击城镇升级 |
| test_expansion_live.gd | 5项通过 | 单位实际出城再返回、野狼实际攻击村民、死亡狼成为资源 |
| test_formation_camera.gd | 19项通过 | 平滑相机、实体阵型、变阵5秒进度/暂停/中断；更新空地位置避免新城墙与城镇阻挡测试夹具 |
| test_strategy.gd | 30项通过 | 集结/21人上限/阵型、采集、建造、晋升、丘陵减速、战斗打断 |
| test_strategy_combat.gd | 20项通过 | 加算伤害/新护甲、箭雨、冲锋朝向、攻城/修复/登墙 |
| test_economy_opening.gd | 23项通过 | 新开局、生产建筑绑定、村民排队取消退款、研究中断、AI波次与城镇胜负 |
| test_contextual_ui.gd | 27项通过 | 选择栏、实际采铁/造房、即时生产、Esc和重试；更新旧开局与时间假设 |
| test_personal_movement.gd | 17项通过 | 原通用单兵移动回归 |
| test_personal_charge.gd | 35项通过 | 最新main原冲锋行为回归 |
| test_strategy_live.gd | 210模拟秒通过 | 保护期没有城邦攻击，随后一轮AI实际出击；8名我方单位存活，战斗继续 |

合计287个断言通过；窗口与headless同一脚本不重复计数。窗口截图检查了城墙/开局、集结点、单兵面板、绿/红军令、黑雾与灰雾总览、城镇升级。运行记录与原始截图在本次环境/tmp，未将重复截图或构建产物写入源码。军令截图发现旧逐兵黄色路线与新标记重叠，已禁用此模式的旧路线显示并重截验证。

复现：`godot --headless --path godot-game --script res://tests/strategy/test_expansion.gd`；替换脚本名可运行其他检查。原生窗口UI验证去掉--headless，脚本截图路径为 `/tmp/contextual-new-opening.png`、`contextual-rally.png`、`contextual-unit-stats.png`、`contextual-orders.png`、`contextual-attack-orders.png`、`contextual-fog-overview.png`、`contextual-town-upgrade.png`。

已修复运行中发现的旧AI导演接管蛮族/狼、狼遗漏队列类型、营寨生命被旧同步逻辑重复放大、隐形敌人仍可锁定和旧路线重复显示问题。退出时原有少量ObjectDB/资源引用警告仍可能出现；本轮通过检查未出现运行脚本异常。当前普通动物仍是静态采集点，狼和墙为简单像素绘制。没有宣称完成完整敌方经济AI或长局平衡。下面保留此前验证记录；旧100资源完整对局记录只代表旧版本。

---

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

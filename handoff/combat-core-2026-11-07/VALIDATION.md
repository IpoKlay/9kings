# 复测与最终验收

> 历史产物已于 2026-11-11 归档，见[归档与恢复索引](../../docs/archive/README.md)。文中的输出命令仍写入本地 `output/`；旧截图、日志和验证数据请从固定版本读取。

## 先运行维护中的回归

需要Python3和Godot4.7.2。下面在仓库根目录执行，Godot参数替换为自己机器的可执行文件。首次导入不要跳过。

```sh
python3 handoff/combat-core-2026-11-07/run_checks.py --godot /绝对路径/Godot --import-first
python3 handoff/combat-core-2026-11-07/run_checks.py --godot /绝对路径/Godot --suite deployment_mouse --suite personal_charge --suite individual_full_battle
```

全部套件名单在suites.json。新部署鼠标套件从主菜单发送真实InputEvent，覆盖中英文七兵种/攻城/山口、部队按钮、开战/胜利重试和透明区域，不直接emit部署按钮信号。它先在旧代码得到6个失败，修复空RegimentRoster遮挡后16项通过。旧测试直接emit按钮不能证明鼠标可点，这次已补。

维护中的基线原为49套2473项；交接新增16项，共50套2489项，最终上传副本结果看 [output/combat-core-2026-11-07/checks/source/results.json](https://github.com/IpoKlay/9kings/blob/81b5e7492ac5bdbec6b7b89fff64eab383624554/output/combat-core-2026-11-07/checks/source/results.json)。返回码、SCRIPT ERROR、断言失败都必须检查。脚本单独保留既有ObjectDB/资源退出警告，不把它们称作已修复；三套旧失败按STATE.md/R18处理。

很多历史测试使用/tmp或工程相邻output目录，Windows运行这些测试还需路径适配。本轮不冒称Windows测试全通过。自己的文件不能写进用户真实存档；使用独立settings_path和测试存档。

## 导出资源与独立程序分开验证

```sh
Godot --main-pack /绝对路径/UnderTheEagle.pck --script /仓库绝对路径/handoff/combat-core-2026-11-07/check_export.gd -- /绝对路径/导出检查目录
```

这里使用Godot编辑器可执行文件加载导出PCK，78项检查含64张死亡图集、必要JSON、真实菜单回调、自然胜利、暂停/半速、重试、显式致死的失败分支、五击破墙。Release模板没有--script功能：不能把它忽略参数后退出0当作通过。Windows PCK在Mac引擎能加载，只证明资源包完整，不证明Windows exe运行。独立Mac.app另做实际鼠标操作，从菜单部署、开战、全军进攻、暂停、返回菜单；独立程序截图单独记录。

## 固定的三类冲锋录像

每次改变移动/碰撞/冲锋后，用同一队8骑、同样助跑距离、兵力、朝向和指令，录侧击步兵、正撞盾墙、正撞坚守长矛。默认镜头、正常速度、先静音/隐藏血条粒子，另附逐帧关键图。已有capture_reference_brace.gd仅重建旧版单排剑盾估读脚点；其他捕捉脚本的配置必须先读，不能把不同起点影片称同条件。

记录首次命中模拟步、伤害次数、每骑经过/停止位置、阵线破口宽度、两秒后的缺口和归位路径。转动全场景后正面/侧翼判定不变；骑手先后接触有差异，远端未接触者保持动作。多排60人测试独立建夹具，不改变主工程单排。

## 性能：禁止把固定步倒数叫正常FPS

```sh
Godot --path godot-game --script res://tests/tactical/benchmark_large_battle.gd -- sample 500 120 /绝对输出目录
Godot --path godot-game --script res://tests/tactical/benchmark_large_live.gd -- live /绝对输出目录
```

先创建输出目录。第一项固定120个1/60更新，只衡量每步成本和状态一致性；.state保留原精度，比JSON位置字符串强。第二项真实engine delta运行至少10现实秒，报告平均/P95帧耗时、实际FPS与模拟推进。测量前停掉其他回归、录制和导入；使用相同机器、兵力、镜头、分辨率和单位资源。最终还要长时运行到结算并做GPU/绘制成本定位，当前短测不足以证明千人可玩。

## 必做边界与正式山口验收

- 30/60/120渲染输入下首次命中、伤害次数、穿透终态；半速、暂停、目标提前死亡、冲锋中改令、两队撞同一队。
- 岩石边缘、无侧移空间、狭门、队列转向、途经点、回防、点火、夺旗；图像与实际阻挡同源。
- 盾墙错位：中央已接触停住，外翼仍进；静音可读，远端不能整队闪白/抖动。
- 1队和3队音效限流；箭落点、石弹落地和医护反馈不同，主撞击清晰，关闭镜头反馈仍成立。
- 完整七兵种会战从主菜单操作至结算，再重试一次；无旧冲锋ID/缺口/音效/位移/尸体/冷却/路径/层级状态。
- 中英文、帮助、神力、菜单返回、设置、存档恢复；编辑器移动HUD按钮/军旗/岩壁/菜单行距保存并运行，再恢复正式布局。

## 完成交付清单

R20前，逐项链接原始需求与证据。提交当前原生源工程、可直接试玩包、固定版本原作与本机前后对照、少量参数表及当前值、真实平均/P95、明确仍飘的动作和对应视频时间。所有未经实机验证的内容单列。测试数量或本目录任务清空不能替代原作完整功能审计。

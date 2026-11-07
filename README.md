# Under the Eagle · 鹰旗之下

## 当前开发版：Godot 原生工程

**最新交接：** [2026-11-07 战斗核心与完整剩余任务](handoff/combat-core-2026-11-07/README.md)。本节点暂停扩展，完整复现尚未完成，千人性能仍未达标。

当前开发以 [godot-game/](godot-game/) 为准。在 Godot 4.7.2 中导入 `godot-game/project.godot`，按 F5 运行。

- 从主菜单进入「军团会战 · RTS」，默认开放野战；七个部署类别可切换旧公开版32种配置，也可选择山口守阵或攻城演练。山口保留守旗/夺旗规则，攻城目前完成石墙五击破坏。
- 血条旁的短三角标出方阵正面。盾兵坚守时锁定朝向，骑兵从侧后方冲入可削弱敌军士气。
- 选中方阵后，Shift 点击地面添加路点，普通点击确定终点。山口行军按阵宽绕岩，后队在窄口等候，正面接敌时可改道。
- 一局远征地中海：三大战区、城邦分支、敌军情报与多轮战斗。
- 从步兵和 3×3 军营开始，通过战后选牌、建筑相邻协同与外围扩建构筑军团。
- 安全节点自动存档；战败后整备与一次性临时军令；精英奖励强化保底与一次重抽。
- 二维像素战场、地图海面与行军动效、纸张 UI、书页动画，以及中英双语、音量和帧率设置。
- 本仓库保存工程源文件、所需素材、授权说明、配置、设计文档及测试脚本。Godot 导入缓存、玩家存档和临时测试产物不入库。

运行与历史更新见 [工程说明](godot-game/README.md)，数值与数据归属见 [DATA_GUIDE](godot-game/DATA_GUIDE.md)。山口地形与行军的验收记录见 [RTS 开发进度](godot-game/docs/RTS_PROGRESS.md)。

## 2026-11-05 原生工程同步

主工程保持单排编队，包含山口进攻计划、预备队、战后复盘、萨贡图姆远征战斗，以及骑兵冲击和各兵种反馈。三个正式布局现在可直接在 Godot 2D 编辑器修改并保存。

- [会战 HUD](godot-game/scenes/ui/battle_hud.tscn) · [编辑器与实机对照](output/editable-scenes/comparison-hud.png)
- [山口布局](godot-game/scenes/battlefields/roman_pass.tscn) · [编辑器与实机对照](output/editable-scenes/comparison-pass.png)
- [主菜单](godot-game/scenes/ui/main_menu.tscn) · [编辑器与实机对照](output/editable-scenes/comparison-menu.png)
- [六排冲锋独立源码](output/formation-impact/六排Godot工程/project.godot) · [冲击验收与录像](output/formation-impact/试玩与验收.md)
- [同步范围与复测说明](docs/SYNC-2026-11-05.md)

按钮位置、纸签样式、树木、军旗、阻挡岩壁、出生标记与菜单行距的具体编辑入口见 [DATA_GUIDE](godot-game/DATA_GUIDE.md)。六排源码保留当时的冲锋验收版本，具有独立应用标识；后续编辑器场景重构位于当前单排主工程。

## 最新游戏画面

以下为当前 Godot 开发原型的游戏截图。

### 山口会战

![骑兵方阵预览绕过岩壁的行军路线](docs/screenshots/pass-terrain.png)

![山口后方的罗马军旗受到威胁](docs/screenshots/pass-standard.png)

### 地中海远征地图

沿城邦分支选择下一站，对比敌军、战斗轮数与奖励，规划本局远征。

![地中海远征地图：路线分支与敌军奖励预览](docs/screenshots/expedition-map.png)

### 城邦历史档案

以像素书页查看古地名与地理资料；地理参考公元前 30 年，行军与交战为架空设计。

![城邦历史档案：德尔托萨的书页与地理资料](docs/screenshots/history-archive.png)

### 军营与战败整备

在石柱港口战区调整军团，查看建筑相邻协同，并选择仅作用于下次进攻的临时军令。

![军营整备：军团阵容、相邻协同与临时军令三选一](docs/screenshots/camp-recovery.png)

## 旧网页试玩版 v0.14

下面的公开试玩链接与网页源码档案保留原版本；上传 Godot 源码不会自动部署网页版。

[直接试玩 / Play online](https://ipoklay.github.io/eagle-standard-demo/)

A full-screen isometric legion strategy game with 24 cards, seven troop types and endless yearly battles. Use the gear button to choose **中文 / English**, adjust sound and war-cry volume, or toggle impact feedback. Settings pause the battle and are saved locally.

## Growing threats

Years 1–3 are gentle infantry patrols. Enemy archers arrive in year 4, shield guards in year 6, cavalry in year 8 and catapults in year 10. Health and attack increase gradually every year; enemy squad count grows every other year to a cap of 20. The year label includes a compact preview of the enemy composition before battle.

## Build your legion

Every year offers three random cards, avoiding consecutive repeats whenever possible and filtering capped upgrades. Buildings remain fixed; troops automatically form a shared battlefield. Combine Fire Arrows + Pitch Stones, Spearmen + Pin & Pierce, Shields + Medics, Cavalry + Blood & Glory, and melee engagement + Crossfire. BUILD lists your army and synergies.

Choose a card → build or upgrade → MARCH. Start with three lives; one failed year costs one life. Pause, speed up battle, or press M to toggle sound. Download index.html to play offline. Campaign progress is not saved after reloading.

49 automated checks cover combat, yearly progression, localization, random draws and synergies. The starting army can survive the first three years without supplies. A fixed seven-squad army loses in year 16 without doctrines, and wins with the tested combined build. This is an initial balance pass for further playtesting.

## Source and private design documents

- [Source archive](eagle-standard-demo-source.zip) — current HTML/CSS/JS, assets, 49 checks, balance probe and packaging scripts.
- [Initial design](123.pdf)
- [Image prompt handbook](鹰旗之下-完整图像Prompt手册.pdf)
- Original roguelike.docx preserved. Audio credits are included in the archive.

The public play link requires no repository invitation. Source collaboration requires access to this private repository; GitHub App authorization is a separate permission.

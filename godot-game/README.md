# 鹰旗之下 — Godot 原生远征版

Open `project.godot` with Godot 4.7.2 or later compatible 4.x releases and press **F5** (Run Project). The main scene is `scenes/main.tscn`. This is a native GDScript/CanvasItem game, not a browser embedded in Godot. No JavaScript runtime, Node installation, or network connection is required to play.

## 当前开发入口：Godot

后续以此工程为准，不再更新或发布网页版本。保留原生版本已有的林地裸土地面、苔藓与落叶、卡牌轻微叠放、140%悬停放大和独立纸牌录音。此轮没有重新导入旧网页的军队、美术、地形或音效。

### 远征流程

- 仍从现有初始三选一卡牌开始。选择完成（建筑卡需放置）后留在军营，点击右上角的折叠地图图标打开局内地图。
- 点击亮起的马西利亚访问港口、领取补给，再选择塔拉科或新迦太基。城邦小窗显示实际敌军、倍率与奖励，可收起。
- “进入战斗”调用原有 `campaign.gd` 战斗。胜利后点“领取奖励”，通过现有卡牌交互选择或放置，再点击右上角地图图标继续远征。失败不推进、不发胜利奖励，扣一条生命后可重试；第三次失败重开。
- 军团建筑、等级和永久教义在本局保留。临时军令在战斗后消耗，和平访问不会消耗。港口、精英和战区目标提供一点生命恢复，上限3。
- 同一局依次完成加德斯、昔兰尼、安条克、亚历山大里亚四个目标；前两站情报可见，已关闭支路不能回头刷奖励。
- “军营 / 构筑”返回已有军营；右上角地图图标打开同一局地图。战斗中打开地图会暂停战斗，返回后继续；未完成补给时可以查看，但不能前往下一站。Esc依次关闭设置、情报或地图。
- 地图是原生 `Control` 场景，使用 PNG 纹理、`Line2D` 路线和 `Button` 城邦；没有 WebView、HTML 或 JavaScript 运行时。地图城名、情报、奖励、历史档案与状态提示完整跟随中英设置，切换语言立即刷新且保留路线与选择。
- 进度仍按原工程保存在当前会话内，关闭游戏后新开一局；此轮未加入跨会话存档或跨局数值成长。

新增文件：`scenes/expedition_map.tscn`、`scripts/expedition_map.gd`（地图界面）、`scripts/expedition.gd`（路线与战役状态）、`data/expedition*.json`、`assets/expedition/`。

地图沿用批准的配色、海岸轮廓与古地名；植被与地势是美术示意，敌我关系与战役顺序为架空。资料与许可见 `assets/expedition/CREDITS.txt`。`tools/build_expedition_map.cjs` 仅为离线纹理制作工具，仅更新地图素材，不触碰原有地形、人物或音效；游戏运行不需要它。

原生验证：`tests/test_expedition.gd` 验证路线、情报、真实战斗、奖励去重、失败和最终通关；`tests/test_expedition_ui.gd` 通过原生按钮连续完成两次城邦战斗、领取卡牌并返回地图，保存原生画面用于检查。原有卡牌交互及音效检查继续通过。

### 远征流程回归检查（2026-10-22）

- 战报入口只在已有战斗结算时出现，无数据时不再打开空白窗口。结算前打开地图，可从右上角直接返回战报；地图提示区分待选牌、待放置、战斗暂停和待结算。
- 通关后的新远征按钮移到地图右上角，不再遮挡第四个战区目标。重开会清除上局倍速、暂停、建筑选中和战斗反馈状态。
- `test_expedition_flow.gd` 在中英文下逐一覆盖全部12条路线，以及放置中查看地图、重复领奖、失败锁定分支、三次失败和通关重开。路线测试直接完成战斗以隔离流程，真实战斗另由 `test_expedition.gd` 和 `test_expedition_ui.gd` 验证。
- `test_report_dialog.gd` 验证中英文的胜利、失败、全军覆没战报与领取奖励后的状态；`test_map_locale.gd` 检查地图双语文字与暂停/恢复。

## 之前的原生移植与更新记录

以下为此前版本记录；无限年份及“出征直接开战”已由上述远征流程替代。

### Migrated from the local v0.22 game

- A cool earthy forest clearing with scattered trees, root moss, leaf litter and boot impressions. The isometric projection, original pixel characters and buildings are preserved.
- Seven allied troop types plus the training yard, all 24 cards, three nonrepeating choices per year, in-place upgrades, level caps, permanent doctrines and temporary orders.
- Unified battlefield, role-based automatic formation, healing, shields, Testudo, burning, slowing, charge, area damage, kill haste and all five documented synergies.
- Endless years, three camp lives, early gentle encounters and progressively mixed, stronger enemy armies.
- Chinese / English settings, sound enable, master and voice volume, impact feedback, pause, speed controls, army/build panel, building inspection and year reports.
- Original edited sound bank decoded to standard WAV; source credits remain in `assets/AUDIO-CREDITS.txt`.
- Settings persist in Godot's user directory. Campaign progress remains session-only, as in the original version.

### Controls

Choose a card with the mouse or **1 / 2 / 3**. Building cards reveal camp cells; click an empty cell or matching camp to build/upgrade. Click the folded map icon at the top right (or press **Space** when ready), select a reachable city, then travel. Space pauses combat; the speed button cycles 1× / 2× / 4×. **Esc** closes the current panel, closes city intel, or returns from the map; in camp it opens settings. **M** toggles sound in camp or battle. Settings and the map suspend combat. Buildings cannot be moved.

## Implementation

- `scripts/campaign.gd`: engine-independent native campaign/combat rules.
- `scripts/battlefield.gd`: fixed isometric projection, depth sorting, frame animation, projectiles and bounded impact effects; the world renders at 960×540 and is enlarged without smoothing.
- `scripts/main.gd`: native interface, input, modal pause, localization and preferences. UI is constructed at runtime, so the scene canvas is intentionally empty before running.
- `scripts/sound.gd`: 12-voice pool, per-sound cooldowns and limiter using existing recordings. Headless tests skip playback because no audio device is available.
- `data/rules.json`: all original card/type/enemy definitions and Chinese translations.
- `assets/`: baked pixel art/animation sheets and WAV files. Animations reuse the original renderer; the native port does not convert the game to 3D meshes.

The old HTML game and its deployment have not been replaced. This port is maintained separately in the private repository’s `godot-game/` directory. Export templates and publishing are separate next steps. The GUI uses the operating system's serif/CJK fonts; verify the target's font coverage when packaging for other platforms, or bundle a suitably licensed CJK font.

## Verification

```
godot --headless --path . --script tests/test_campaign.gd
godot --headless --path . -- --smoke-test
godot --path . -- --render-test
```

- 161 rule checks: 18 original-JavaScript combat references across nine years, combat duration, 100 seeded yearly draws, construction validity, three-life defeat, order expiry and full-camp fallback.
- Native UI smoke: language switches preserve state; settings suspend battle; opening battle wins; reports advance into the next year.
- Render check: all 24 cards in both languages fit their bounds; screenshots cover cards, construction, battle, build panel, settings and result. `--render-test` uses a temporary verification window and quits automatically.

`tools/import_web_assets.cjs` rebuilds native assets and reference fixtures from `../eagle-standard-demo/dist`. It requires Node and `@napi-rs/canvas` (set `EAGLE_CANVAS_MODULE` to the installed module path if needed). It is a developer tool, not a runtime dependency.

## Forest clearing terrain

`node tools/forest_floor.cjs` rebuilds only the native terrain texture. The central battlefield and construction area use bare soil; moss and litter gather beneath the retained forest trees. The web asset importer uses this same generator, so importing again will not restore the old grass field.

## Slightly layered card hand

Three cards overlap by 18 logical pixels (7.5% of their width), with only 1.4 degrees of side-card tilt. Hover lifts a card by 58 pixels and scales it to 140% in 0.19 seconds, placing it above its neighbours; leaving settles it in 0.22 seconds. A chosen card lifts out while the others fade, with input locked until the one reward is committed. Resting hit regions remain stable during animation, including fast switching and overlap-edge clicks.

Native paper foley uses Kenney's CC0 Casino Audio recordings: fan/deal, a single slide on hover, and a single shove on selection. Each action always uses the same recording; leaving a card is silent. The four active short cues in `assets/cards/trimmed/` have aligned onsets, matched RMS levels, and baked fades. Other earlier variants remain as unused assets. A dedicated single-voice player prevents rapidly changing gestures from stacking; pitch is fixed and global volume/mute still apply. This preserves the original recordings and short durations without frame-dependent volume tweens. Rebuild with `godot --headless --path . --script tools/prepare_card_audio.gd`, then reimport assets.

`godot --headless --path . --script tests/test_card_hand.gd` checks overlapping hit targets, hover depth, rapid switching, modal blocking, double-selection protection and audio decoding.

`godot --headless --path . --script tests/test_card_audio.gd` checks decoded loudness spread, clipping, short durations, rapid-hover gain, voice isolation, master volume and mute.

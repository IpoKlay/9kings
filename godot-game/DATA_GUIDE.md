# 《鹰旗之下》数据与调参指南

本次是原生 Godot 工程的数据整理。保留整理前的数值、随机顺序、玩法流程、像素画面和素材。运行入口仍是 `project.godot`；没有网站、WebView 或额外网络依赖。

## 当前远征存档与奖励状态（2026-10-28）

| 数据层 | 入口 | 内容与边界 |
|---|---|---|
| 新局模板 | `data/defaults/campaign.json` | 新增 `reward_context`（空/elite/recovery）、`reward_rerolls`（0/1）、`recovery_used`（城市ID）、`temporary_orders`（临时军令ID）。配置只提供默认值，运行不写回模板。 |
| 奖励规则 | `campaign.gd`、`expedition.gd` | 精英从满足 `available()` 的 Permanent 卡中保底；满级/不满足前置不入保底池。重抽仅刷新当次三选一，不重复回血。临时军令用原卡牌效果的I级，不写 `upgrades`，一整座城的多波战斗视为一次进攻，结束才清除。 |
| 当前远征 | `scripts/data/run_store.gd` | `VERSION=1`，保存 first_act、Campaign.g、Expedition.state；当前版本与有效卡牌、地块、城市引用必须匹配。拒绝包含对象字段的状态。 |
| 磁盘文件 | `user://expedition.cfg` | Godot ConfigFile；先写 `.tmp` 并重新读取校验，再保留上次有效文件为 `.bak`，最后替换正式文件。主文件不可读/无效时尝试备份；均无效则不显示可继续的远征。 |
| 玩家设置 | 原 `settings_store.gd` | 语言、音量、帧率、效果仍在原设置文件，不随新远征重置。 |
| 临时表现 | 原场景/UI控制器 | 悬停、镜头、选牌手势、云幕、声音、粒子不存档。关闭再开不续播这些动画。 |

默认macOS位置：`~/Library/Application Support/Godot/app_userdata/Under the Eagle/expedition.cfg`。不提供多存档槽或云同步。原来仅有内存中的游戏没有旧远征文件可迁移；后续改变状态格式时需增加版本并明确迁移规则。

安全节点：新局/地图、军营放置与交换/扩建、奖励生成/重抽/选择/跳过、临时军令领取、战斗开始与结算。`main.render_ui()`调用保存入口，对状态快照进行相等比较，没有变化就不写磁盘；不在逐帧模拟中保存。测试工程使用独立路径，原有自定义设置路径的测试默认不写真实远征存档。

战斗中保存的是同一目标的战前重打状态，不保存中途血量/弹道/已过波次；构筑、军令、路线承诺和抽卡随机状态保留。结算界面尚未确认时，副本先结算到安全节点，实际界面不被修改；彻底战败保留最后战报，不返还生命。最终战报里的显示坐标经文本序列化可能出现极小取整差异，不影响已经结束的战斗。

`recovery_used`在打开三选一时记录，所以退出再进仍是相同选项，跳过不能重新领取。临时军令覆盖下一整场攻城，无论胜败都清除；如仅在战斗中退出，按上述战前重打约定保留这次军令。永久军令等级不受影响。

验证：`tests/test_run_recovery.gd`验证规则、实际首战、磁盘往返、损坏主文件回退、扩建/摆放、强化池耗尽与终局；追加 `-- --verify-disk`可在另一Godot进程读取上一轮测试文件。`tests/test_run_ui.gd`原生窗口点击与上滑，反复销毁并重建游戏实例验证恢复与防重复领取；精英胜利与败退采用明确测试状态，不作为战斗平衡证据。

## 当前军营与远征成长（2026-10-27）

以下是本次明确修改的玩法；本节覆盖下方旧版本关于12格、三支初始部队和训练场退役的说明。

| 数据层 | 正式入口 | 当前约定 |
|---|---|---|
| 新局模板 | `data/defaults/campaign.json` | `buildings`仅一队I级步兵，`cell=12`；`unlocked_cells=[6,7,8,11,12,13,16,17,18]`为中央3×3；`phase=prepare`。JSON数字在新局加载时统一转整数地块ID。 |
| 军营规则 | `data/balance/camp.json` | `columns/rows=5`是最大坐标范围，不是开局可用面积；`max_buildings=25`。`expansion_every_victories=3`控制每几城额外扩一格。标准外围为25−9=16格，包括四个角；扩建可选任意未开放格，不要求先与核心上下左右连通。协同加成仍只算上下左右。 |
| 相邻协同 | 同上 | `training_adjacency_per_level=0.25`；`medic_adjacency_health_per_level=0.15`。仅上下左右，训练场加攻击、医疗营加军团生命上限；同类最强，不叠加。 |
| 前期奖励 | 同上、`data/balance/cards.json` | `guaranteed_troop_until=3`：不足3支军团时，至少一个选项是当前可用兵种。训练场恢复抽取；满格时只提供可放置或能升级的兵种/建筑。 |
| 出阵位置 | `data/balance/combat.json` | `deployment_column_spacing=85`、`deployment_row_spacing=110`为战场世界单位。格子列控制前后，行控制侧向；不自动按兵种排序。营地脚下位置与出阵起点共用Formation。 |
| 初期敌军 | `data/balance/assaults.json` | `early_roster_limits`按第一战区的节点step裁剪最初几城首轮队数，之后各轮仍由原波次模板生成；情报与实战共用裁剪后的配置。地理起点轮换后强度一致。 |
| 地块显示 | `data/presentation/field.tres` | `camp_origin/camp_hit_origin`共同定位5×5完整范围；`camp_spacing/camp_half_size`控制投影地块。人物继续`troop_scale=2`，未缩小已有军团。 |
| 文案 | `data/localization/bindings.json`、`cards.json`、`interface.json` | `yard_pct/hospital_pct/expansion_cities`从规则读取，中英文数值不另抄一份。 |
| 局内状态 | `Campaign.g` | `unlocked_cells`、`expansion_credits`、`cities_captured`与各建筑的`id/type/cell/level`。仅胜利结算增加攻城数，独立扩建不消耗卡牌。移动/交换只改cell，不重建实体。 |
| 玩家设置/存档 | 原`settings_store.gd` | 设置照旧独立保存；当前远征持久化见上方2026-10-28章节。 |

验证入口：`test_camp_expansion.gd`、`test_camp_ui.gd`、`test_supply_to_battle.gd`、`test_card_swipe.gd`、`test_legion_deployment.gd`、`test_city_waves.gd`及`tools/validate_data.gd`。`test_expedition.gd`分别记录真实获胜和强制结算测试数量；后者只验证路线/奖励流程，不证明该构筑能通关。旧`combat_reference.json`保留为历史编队样本，自动按兵种排阵时代的胜负/时长不再作为当前空间玩法的数值基准。

## 路线战术与侦察比较（2026-10-27）

| 数据层 | 入口 | 用途 |
|---|---|---|
| 敌军战术 | `data/balance/enemy_doctrines.json` | `profiles` 定义循环首轮编成、增援替换池及应对卡牌ID；`sites`固定九处分岔的18个地点战术；`theaters`提供其他地点的地域编成。`intro_stage/intro_last_step`保留第一战区前两战。 |
| 强度与波次 | 原 `balance/assaults.json` 与 `content/locations.json` | 仍根据本局阶段取得队数、血量、攻击倍率及波数，再由地点战术分配兵种；不是所有地区使用相同编成。原静态地点表不改。 |
| 战术文案 | `data/localization/interface.json` 的 `routeintel.*` | 敌军名称、威胁、应对说明及侦察纸签文案。卡牌名字从现有卡牌词条读取。 |
| 线路表现 | `data/presentation/atlas.tres` 的 `route_ink` | `ready_width=10`、`future_width=3`、`branch_lane_offset=16`（逻辑屏幕像素）。偏移只作用于绘制，不改变真实路线、地理数据或军团行军点。 |
| 临时界面 | `route_briefing.gd`、地图/Atlas | `briefing()`返回当前或前一站可侦察的分岔；纸签点击只选中，实际出发沿用 `depart_to()`。`full_network/focus_local`是镜头表现状态，不写入玩家设置/存档。 |
| 构筑提示 | `Expedition.response_cards()` | 已放置部队、仍满足兵种条件的强化和当前有效军令；不读取或消耗抽卡随机数，不产生胜率评分。 |

验证器检查所有地点、兵种、卡牌和文案引用，要求同处分岔提供两种战术。`test_route_tactics.gd`检查侦察与实战一致、每波保留战术核心、三起点真实首战及军令消耗；`test_route_readability.gd`检查双语九处分岔、提前预览不能越站、选支路/败退、字形排版、窗口大小变化与静止路线缓存。`atlas_sea_surface.refresh()`忽略已经离开场景树但尚未删除的旧地图，防止同帧切换与缩放触发失效回调。

敌军组成改变会影响真实难度；保留队数与倍率不等于完成平衡。地理与奖励流程测试使用显式胜负状态；只有三种基础首战记录为实际打通。截图中的多单位战斗使用专门的测试军团，不是玩家存档。旧试玩包未重新导出。

## 行军与进战场过渡（2026-10-27）

- 表现参数放在 `data/presentation/atlas.tres` 的 `departure`：集结/遮云/停留/散云时长以现实秒计；行军按屏幕路径长度与 `march_pixels_per_second` 计算，并限制在1.0–1.65秒。与战斗1/2/4倍速、城邦强度及抽卡随机数无关。
- `cloud_size=480×270` 对应逻辑画面的4倍整数显示；`pose_fps=12`、`cloud_fps=15` 只限制动作更新，不修改全局帧率。`cloud_shadow/mid/light/highlight` 为四级不透明颜色；验证器检查时长、色板与整数画布比例。
- 独立散云：`cloud_count=24` 为固定上限内的云团数；`cloud_width=(110,190)` 为低分辨率画布中的宽度范围，`cloud_drift=(28,90)` 为单团完整漂移距离范围；实际高度、方向、轮廓和淡出时机由局部视觉随机数决定。`cover_seconds=0.5`，`reveal_seconds=1.6`；配色不变。
- `pixel_cloud_field.gd` 为每团云创建一次绘制矩形和材质，随后只更新整像素位置、尺寸与透明度。每次过场重新抽取视觉布局，不读写战役随机数。切场时底层浓雾确保所有像素完全遮挡，散云初段在全画面退去，再由不同方向的独立云团延迟消散；没有左右幕布裁切或循环云纹。
- `scripts/expedition_departure.gd` 的阶段、路径、计时、已提交标记及输入锁均是短暂表现状态，不写入配置或存档。路径读取既有 `generated/march_paths.json`，去除屏幕取整产生的连续重复点后采样；不新增运行时寻路，不改变地图路线。
- 地图确认按钮调用 `main.depart_to()`；全遮挡时控制器仅调用一次原 `main.travel_to(id,false)`，然后完成散云。控制器存在期间主战斗循环暂停。查看情报、换页签和悬停不能触发行军。和平地点在行军结束后直接沿用原事件流程。
- `Sound.play_rally()` 复用原音频池和音量设置，每次确认出发只播放一次，快速跳过时收掉上一段号角/呼喊尾音；后续波次的号角规则不变。未新增录音、许可或声音生成依赖。
- `test_departure.gd` 实际运行陆路/海路、云幕遮挡/显现、三种初始路径、和平到访、跳过、取消、音量及战斗冻结；截图与逐帧证据保存在 `../output/departure-cloud-v1/`。旧流程测试通过 `expedition_test_support.finish_departure()` 明确快速结束表现，再验证原结算，不把流程测试的强制胜利当作战斗平衡证据。
- 最新逐帧证据改存 `../output/cloud-scatter-v2/`；`test_cloud_scatter.gd` 检查12组固定种子布局，并实际渲染其中3组，验证全部像素的遮挡/清空、左中右都有云和缝隙、位置不成行、四方向漂移、减少动态效果及不在动画中追加节点。

## 地理分支表现与可达性（2026-10-27）

| 数据层 | 正式入口 | 修改边界 |
|---|---|---|
| 游戏连线 | `data/content/routes.json` | 原55地点、9处分岔、每局45站不变。决定真正可达关系；不能用视觉折线新增可走路线。 |
| 分支说明 | `data/content/march_choices.json` | 每处分岔的来源ID、汇合ID和两个进军方向的中英文名称。验证器检查来源→选项→汇合确实是原图中的连线。 |
| 地理折线 | `data/generated/march_paths.json` | 离线生成的陆海类型与世界坐标折线，覆盖三个起点轮换。`visual_sites`仅用于奥埃亚腹地这个区域标记，不改历史城邦坐标。 |
| 生成工具 | `tools/build_march_paths.py` | 从现有位置表、路线表及海岸遮罩生成示意道路，依赖Pillow；运行游戏不依赖Python。修改城邦锚点、连线或遮罩后才重新生成。不是古道路历史数据。 |
| 视觉参数 | `data/presentation/atlas.tres` 的 `route_ink` | 线宽、描边、金色高亮、城名字号和底衬，单位为屏幕逻辑像素；地图折线坐标仍用世界像素。原地形、海面、纸张、船和军团素材不变。 |
| 运行状态 | `Expedition.state`、地图镜头/选择 | 出发即锁定支路；其余支路本局关闭。页签只改变查看战区，不能远程出兵。路线缓存与标签引线在布局时更新，无每帧寻路。 |

运行 `tools/validate_data.gd`、`test_march_network.gd`、`test_march_ui.gd`；修改布局还应检查 `test_expedition_layout.gd` 和 `test_map_zoom_input.gd`。分支测试以显式胜负状态隔离路线规则；军营原生测试另运行真实首场战斗。截图和本轮记录在 `../output/route-branches-v1/`。

## 本轮选定声音（2026-10-26）

- `presentation/audio.tres` 的 `music.tracks.boss` 使用 Legionnaire (2022 Remaster)，`music.tracks.map` 使用 The Great Sea。军营保留 Lord of the Land；战斗中打开地图继续当前战斗音乐。音乐的独立音量、跨波连续播放和渐变沿用现有系统。
- `effect_files` 指定新音效列表，与 `variants` 数量一致。`gains` 是线性增益，`gaps` 是现实时间的最小触发间隔；4倍速和密集单位不会加快音频或无限叠音。新录音在 `assets/selected_audio/`，其他录音保留旧路径，卡牌、菜单移动和翻页的专用播放器不变。
- `ambience.tracks.sea/fire` 分别对应地图与军营。两条独立循环在1.4秒内渐变，设置和暂停降至50%，历史书与战斗淡出；服从音效开关和总音量，不占战斗的12个声部。WAV已处理循环接缝，使用无损PCM导入。
- 脚步只在存活友军真实移动时触发，最短0.30秒一次；开战/新波使用军号，部署添加低声装备动作；胜利领取与补给到达使用金币，失败不播放金币。
- 授权与处理记录保存在 `assets/selected_audio/SOURCES.json`、`CREDITS.txt` 和 `assets/music/`。原始下载与剪辑脚本在 `../output/selected-audio/`；重建需要NumPy和SoundFile，游戏运行无额外依赖。

## 原地图海上装饰（2026-10-27）

`presentation/atlas.tres` 的 `sea_life` 仅控制八爪鱼和航船的显示，不参与远征/战斗数值。`world_pixel_scale` 是素材像素到地图世界坐标的倍率；`kraken_position` 为原地图世界坐标；`kraken_sway_period` 为触手摆动周期（秒），`kraken_sway_pixels` 为素材像素位移倍率。八爪鱼独立材质只改变触手末端，复用地图5帧/秒时钟与暂停逻辑；原PNG、船帆和航线不变。每艘船的 `route` 是折线路径，`speed` 单位为世界像素/秒，`phase` 为初始单程进度，`frames` 引用八方向 SpriteFrames。修改航线后运行 `tests/test_atlas_sea_life.gd`，确保船体完整范围始终在水上。图片与原许可位于 `assets/expedition/sea_life/`。

## 先记住三条规则

1. 玩法数值只在 `data/balance/` 修改；同一个效果的中英文说明与数字徽标从这里取值。
2. 表现参数只在对应的 `data/presentation/*.tres` 修改。它们是 Godot 原生 Resource，可在检查器里展开 `values`；字段名称保持固定，类型与单位见下文。
3. 配置是只读定义；每局状态是独立副本；玩家设置单独保存。不要把战斗中的生命、已选卡牌、鼠标位置写回配置文件。

修改配置后停止并重新运行游戏。当前实现不热加载数值，避免一局中途出现新旧配置混用。

## 三战区地面（2026-10-27，当前版本）

`presentation/environment.tres` 的 `backgrounds` 依次为 `environments/iberia-grass`、`environments/africa-sand`、`environments/east-coastal`，`ground_overlays` 三项均为空。每张内部地面统一，三张分别使用深草绿、暖沙金、冷灰绿；不能再把北非或东岸换成同色深绿。背景按原画面比例使用既有960×540战场视口近邻显示，人物保持1.0；水域、格子和单位逻辑不变。

新背景使用内置imagegen分别编辑各自原图。伊比利亚沿用已确认版本；北非与东岸参考其像素纹理密度，色彩和材料按当地地貌区分。最新提示词、输入路径与实际画面存于 `../output/three-theater-terrain/`，伊比利亚此前记录在 `../output/sbs-full-ground/`。`tests/test_sbs_ground.gd` 检查三图内部颜色一致性、地域色差，以及实际部署、出阵和开战。

旧SBS图集、CC0许可、`sbs/iberia-ground.png` 与离线生成器保留用于回溯，当前游戏不显示旧覆盖层；运行 `tools/build_sbs_ground.gd` 不会更新现在的整幅背景。

## 三级军团与出阵（2026-10-26）

- `balance/units.json` 的 `formation_counts` 是军团 I/II/III 的人数：步兵、弓兵、长矛和盾卫为6/9/12，骑兵为4/6/8。军团生命与攻击按人数比例计算，单兵精灵大小保持1.0；当前仍以一支小队作为战斗结算单位，并非每个画面人物独立寻路和计算生命。
- `balance/cards.json` 增加 `Troop` 类别。军团与建筑都在同类格上升级，最高III；23张当前可抽卡均为三级。训练场 `training` 标记 `retired`，保留旧数据解析，但不再抽取。
- 强化卡累计到III后退出抽取。军令的熟练等级存于 `g.upgrades`，每次选择升一级、上限III；本场激活仍存于 `g.orders`，战后消耗，下次选择III级军令可再次使用。龟甲阵是单独军令，三级减伤40%/50%/60%，移动惩罚保持25%。其他效果按自身每级增量累计，显示值由 `campaign.card_copy()` 结合原数值绑定解析。
- `formation.gd` 共用营地中心和投影的反算，准备画面与 `muster()` 的实际起点相同。`combat.deployment_seconds` 当前3.2秒；每座城开战时军团从原格走向战线，完成前敌我不攻击，行军不占该轮75秒战斗时限。轮间仍采用原3秒休整、补员和战线重新集结规则，不重复从营地出阵。
- 攻城营和医疗营的六张正式素材位于 `assets/facilities/`，96×96 RGBA、近邻显示。建筑固定一格，三级增加结构与设备；未添加木板底座或栅栏。部队卡与详情直接复用真实军团精灵，建筑卡复用当前建筑素材；旧卡图不覆盖。
- 对应检查：`test_legion_deployment.gd`、`test_card_levels_ui.gd`、`test_city_waves.gd`，以及原生的 `test_card_swipe.gd`、`test_supply_to_battle.gd`、`test_pixel_fonts.gd`。`test_campaign.gd` 的历史战斗基准从出阵结束开始计时；旧抽卡序列因训练场退役和三级上限被确定性/可用性检查替代。

素材原图、生成提示词、源代码备份和原生预览位于 `../output/legions-v1/`。其中 `upgrade-guide.png` 是放大素材对照，`legion-march.gif` 是原生游戏逐帧录制。

## 分层与正式修改入口

以下路径均以此 Godot 工程目录为起点。

| 层 | 存放位置 | 内容与修改边界 |
|---|---|---|
| 引擎/结构约定 | `project.godot`、`data/schema/contracts.json` | 逻辑分辨率、世界/纹理比例、固定战斗步长、随机算法、阶段与语言、着色器数组容量。不是平衡调参项；变更要同步相关实现和检查。 |
| 玩法平衡 | `data/balance/*.json` | 部队、敌军、卡牌条件、战斗、效果、城邦波次、补给与侦察。外部 JSON 为唯一正式数据。 |
| 初始模板 | `data/defaults/*.json` | 初始军团、远征状态、设置默认值。每次建立状态都会深复制，不能共享可变数组。 |
| 关卡内容 | `data/content/*.json` | 城邦身份、三战区、路线、历史文本、固定敌军模板。ID 与显示名分离；改名字不改 ID。 |
| 语言与数值说明 | `data/localization/*.json` | 中英文界面、卡牌文案、旧标签翻译与数值绑定。 |
| 表现资产 | `data/presentation/*.tres` | 树风、水域、海面微风、地图镜头、卡牌动画、音效、反馈和共用 UI 参数。 |
| 原始素材 | `assets/` | 图片、地图、字体、音频、导入设置和许可；本轮逐文件校验未改动。 |
| 地图生成结果 | `data/generated/` | 城邦像素锚点、历史版本的水光/地图坐标。生成结果不是历史地理源数据。 |
| 资料与离线来源 | `data/sources/`、`tools/map-source/` | 历史来源、旧树林布局、地理几何与像素绘制方法；不参与战斗平衡。 |
| 运行状态 | 内存中的 `campaign.g`、`expedition.state` 及场景成员 | 当前生命、建筑、手牌、敌军、路线访问记录、镜头、动画、声音池等。按所属对象管理。 |
| 玩家设置 | `user://settings.cfg` | 语言、主音量、独立音乐音量、人声音量、音效开关、打击反馈、帧率上限。含版本号，另有 `.bak` 备份与写入期间的 `.tmp`。 |
| 测试基准 | `tests/fixtures/` | 原战斗结果、固定种子抽牌序列、整理前的完整规则/远征数据。只用于验证，不能充当新数值来源。 |
| 验证输出 | 上一级 `output/data-organization/` | 整理前后截图、检查日志、素材指纹结果、原始源文件备份。不会进入游戏包。 |

`data/manifest.json` 登记正式数据。新增一个数据文件时同步登记；不要重新建立根目录 `rules.json` 或 `expedition.json` 作为第二份来源。

## 玩法数据：按修改目的查找

| 文件 | 管理的数据 | 单位与注意事项 |
|---|---|---|
| `balance/units.json` | 军团兵、矛兵、盾卫、骑兵、弓兵、军医、投石车、训练场 | `hp` 生命；`attack` 单次伤害；`heal` 单次治疗；`range` 战场逻辑像素；`speed` 逻辑像素/秒；`interval` 秒/次。训练场没有部队战斗属性。名称保留旧接口的英文标签，中文由语言表解析。 |
| `balance/enemies.json` | 五类敌军基础属性与护盾 | 和我军相同单位。城邦难度倍率在波次层叠加，不重复改基础表。 |
| `balance/cards.json` | 24 张卡的类别、叠加上限、需要的兵种和前置卡 | `requires` 仍是全部满足；`needs` 是前置升级。卡牌 ID、类别字符串是行为标识，不能当文案随意改名。 |
| `balance/effects.json` | 护盾、龟甲、燃烧、减速、军号、冲锋、交叉火力、牵制、燃油、联合兵种等 | 小数比例和倍率分开：0.25 表示额外 25%，1.4 表示 1.4 倍。`duration` 是秒，范围是战场逻辑像素。 |
| `balance/camp.json` | 营地行列、容量、等级、生命上限、奖励数量、等级成长、训练加成、败战扣血和历史长度 | 4×3 地块、三级建筑与三选一还受现有排版/素材约束；验证器明确阻止只改数字而未改界面的情况。 |
| `balance/combat.json` | 轮间休整、超时、恢复/补员、抛射物飞行时间、范围伤害、列阵、队伍分离和战斗边界 | 时间为秒；比例为 0–1；坐标为战场逻辑单位。恢复比例与生命上限是不同概念。 |
| `balance/assaults.json` | 3/5/8/10 轮、首轮与后续敌军变体、压力交替、地区进度增长、普通/精英/首领强度 | 波次数量是整数。增长公式与计算顺序保持在战斗逻辑中，系数只在此处。 |
| `balance/expedition_rules.json` | 侦察距离、可恢复生命的节点类型、恢复数量、三战区开局抽签池 | 改恢复值时不需要再改中英文奖励说明。三图抽签袋仍只在这次程序运行内保留。 |
| `balance/legacy_encounters.json` | 未使用城邦覆盖数据时的原轮次遭遇规则 | 保留旧测试及军营预览兼容。正常远征优先使用城邦遭遇，不是另一套平衡源。 |

`schema/field_contracts.json` 登记主要平衡字段的类型、单位、边界。验证器还检查卡牌前置、素材、城邦引用、路线递进、初始建筑位置及容量等关联。它能拦截常见配置错误，不等于保证任意新增玩法都正确。

## 地图、历史与三战区

| 文件 | 内容 |
|---|---|
| `content/routes.json` | 起点、终点、每区 15 站、全局 45 站、连线及三个目标。 |
| `content/theaters.json` | 三战区的 ID、双语名字、路线说明、目标城邦。 |
| `content/locations.json` | 55 处地点的稳定 ID、类型、所属战区、层/分支、敌军模板、经纬度（已有时）、古名和双语历史。历史叙述与地点放在同一条记录，避免错配。 |
| `sources/history.json` | 历史资料出处。 |
| `generated/atlas_positions.json` | 当前 5760×2520 逻辑地图中各地点的像素坐标。和底图配套生成，不能只改锚点假装修改地理。 |
| `generated/legacy_map_positions.json`、`legacy_water_points.json` | 旧地图/旧水光生成记录；当前路线地图与海面不读取它们。 |

远征会在运行时复制路线定义，调整三战区的先后顺序、阶段强度和最后首领身份。这是本局派生数据，不写回原始城邦表。地图位置和战区地理外观不因这个复制过程被覆盖。

## 表现参数：在 Godot 里编辑对应 Resource

| 资产 | 用途 | 单位/界限 |
|---|---|---|
| `presentation/environment.tres` | 三张背景引用、可选地面覆盖层、每张 12 棵树的位置/尺寸、水域多边形、水流速度、旗帜位置、独立树风和漂浮物 | 三图依次为 `iberia-grass`、`africa-sand`、`east-coastal`；`ground_overlays` 当前全为空。树坐标/尺寸为 1920×1080 逻辑画面单位；风的振幅和速度范围分别管理；环境随机种子独立于抽卡。水域最多 24 个顶点，由着色器容量约束。 |
| `presentation/atlas_sea.tres` | 海面风区寿命、速度上限、鼠标速度系数、阻尼、生成间隔、范围、淡出与帧率 | 速度为地图逻辑像素/秒，寿命/间隔为秒；半径为逻辑像素。上限 28、寿命 2.8 等默认值保持原样。 |
| `presentation/atlas.tres` | 三条路线颜色、缩放上下限、定位范围、城邦标记大小和避让，以及 `boundary` 像素外框 | 标记和外框采用屏幕逻辑像素；锚点采用地图坐标。最低缩放还受外框的填满高度约束，避免再次出现空白横条。不能把两个坐标系混用。 |
| `presentation/card_hand.tres` | 卡尺寸、间距、悬停 1.4 倍、抬起距离、旋转、阴影、发牌和选中动画时长、上滑距离 `drag_threshold`、拖动网格 `drag_pixel_step`，以及卡面 `face_palette` 与三类插图区 `face_wells` | 位置/手势距离为逻辑像素，旋转为度，动画为秒。命中测试与显示共用卡尺寸；提交等待不能短于提交动画。卡面颜色不决定卡牌稀有度或玩法。 |
| `presentation/audio.tres` | 音效变体、增益、最短间隔、声部数、音高范围、固定纸牌录音，以及菜单切换音效 `menu_move` | `gains` 和 `menu_move.gain` 是线性增益，不是分贝；`menu_move.file` 指向用户提供的 MP3；`gaps` 是秒；声音池与缓存只属于运行时。玩家音量不在此处修改。 |
| `presentation/feedback.tres` | 打击停顿、后仰/局部闪光、像素命中痕迹、镜头采样/限频、粒子数量/速度/寿命、战报等待、飘字 | 距离为1920×1080逻辑像素；`pixel_step=2` 对应960×540战场的1像素。只影响反馈，不修改伤害。击杀停顿仍为0.045秒。 |
| `presentation/field.tres` | 战场投影、营地格子中心、间距、命中起点与范围，以及人物显示比例 `troop_scale` | 显示和鼠标反投影共用布局参数。`troop_scale=2` 只放大军营/战斗人物和阵内视觉间距；不放大格子、队伍实际坐标或卡牌插图。保留脚底锚点，血条、命中点和箭矢高度同步适配；960×540战场下为原精灵1:1像素显示。调整后检查地块选择、密集队形与反馈位置。 |
| `presentation/ui.tres` | 六张罗马 UI 素材引用、RPG 纸张素材裁切与配色、菜单共用布局、纹理种子、按钮和面板边距；文字菜单字号、光标尺寸/网格、跟随速度、浮动周期/幅度 | 光标以逻辑像素计，周期为秒，跟随速度为每秒衰减率；当前选择与光标时钟属于运行状态，不存入 Resource。 |

共用字体/字号主题继续由 `assets/fonts/game_pixel_font.tres` 和 `game_pixel_theme.tres` 管理。字体、许可与导入文件本轮均未改动。

战斗反馈（2026-10-27）：`hit_recoil_pixels / heavy_recoil_pixels` 是视觉后仰，当前4/6逻辑像素，不改变单位坐标或碰撞；`heavy_hit_hp_fraction` 只决定表现强度，不是伤害倍率。`hit_flash_seconds` 为0.055秒，`recoil_seconds` 为0.16秒。`hit_repeat_gap_seconds=0.075` 合并同单位的连续普通命中，破盾优先。`impact_mark_limit=24` 与 `particle_limit=180` 限制密集交战开销。

`shake_poses` 按 `shake_pose_fps=24` 播放并以0结束，`shake_repeat_gap_seconds=0.14` 按本次起始强度限频，避免衰减后再次被同级事件重启；更强事件可打断。普通命中不触发镜头；投石强度由3改为6逻辑像素，其余死亡/突破强度保持2/5。镜头和后仰按2逻辑像素取整，真实时间驱动；痕迹/粒子同样使用真实时间，不会因4倍战速一闪即逝。攻击和行走动画仍随战速播放，但击杀停顿时一起冻结。暂停和查看地图时停止反馈时钟；波次和新战斗清空短时反馈。设置关闭打击反馈后，关闭后仰、镜头与停顿，保留识别命中的闪光/痕迹及现有音效。调整后运行 `tests/test_combat_feedback.gd`，原生窗口可保存实机截图；性能工具为 `tests/benchmark_combat_feedback.gd`，需要本次输出目录中的修改前快照。

卡面由 `scripts/card_face.gd` 静态绘制，使用2逻辑像素网格、有限色阶、阶梯角和双层细边，无新增材质或逐帧刷新。`TEXT_RECTS`、`ART_RECT` 与 `ICON_RECT` 是当前240×334卡面的排版结构，代码和排版检查共同使用；修改卡尺寸时必须同步这些区域。原64×64卡图按2倍近邻显示，卡名、数值、说明和类别仍由当前卡牌与本地化数据提供。调整字号、行距后重新设置文字框尺寸，避免Godot保留旧字体造成的最小高度；不要通过裁字解决溢出。运行 `test_pixel_fonts.gd` 检查全部24张卡的双语布局，原生运行 `test_card_face.gd` 与 `test_card_hand.gd` 检查渲染、鼠标和既有动效。新卡面没有增加卡背、翻牌阶段或额外选牌点击。

纸张 UI 的 `rpg_sheet` 指向原始 PNG；`rpg_regions` 为原图像素坐标的矩形；`rpg_scales` 必须为正整数，采用近邻放大；`rpg_margins` 按左、上、右、下定义原图像素边距，不能吃掉九宫格中部。`rpg_tints` 管理纸色及按钮状态，`rpg_ink / rpg_secondary_ink` 为正文与次要文字颜色。首次使用后的纹理与样式缓存在 `rpg_ui.gd` 中；修改资源后重启游戏。校验器检查素材存在、裁切范围、整数缩放和边距。

地图顶部长按钮使用 `RPGUI.box('toolbar')`：它直接复用 `button` 的裁切、纹理、边距与配色，仅将中段改为横向平铺，不复制一套素材数据。整排位置/高度由 `expedition_map.gd` 的 `TOOLBAR_Y` / `TOOLBAR_HEIGHT` 与 `toolbar_button()` 管理，属于界面布局；应用字体后重新指定尺寸，防止文字的临时最小尺寸造成不齐。内部 `ZoomButton` 在按钮中心绘制加减笔画并读取现有主题状态色，保留原生按钮输入与焦点；提示及无障碍名称读取 `localization/interface.json` 的 `expedition_map.zoom_in / zoom_out`。

卡牌使用手势由 `card_hand.gd` 统一管理。`drag_threshold` 当前为96逻辑像素（1280×720窗口约64屏幕像素），以实际按下位置为起点，悬停自动抬起不计入距离；向上距离还必须不小于横向距离，排除横划。只有松手时仍满足条件才提交，瞬间越过后拖回来不会锁定使用。`drag_pixel_step` 当前为2，只约束卡牌显示位置，不改变鼠标判定距离。按下坐标、原卡位置、当前拖动卡和待确认状态属于临时界面数据，取消、弹窗和窗口中断时清除，不存入配置或存档。提示语在 `localization/interface.json`，金边高亮复用已有配色，状态变化才重绘。修改后运行原生 `test_card_swipe.gd` 和 `test_supply_to_battle.gd`，检查两个窗口尺寸、取消/快速移动、三战区开局和战后奖励；键盘1/2/3仅预览，不绕过手势。

历史书继续读取 `content/locations.json` 的 `history / history_en`，地区分类使用该城邦的 `act`，位置图使用既有 `generated/atlas_positions.json`。不要在 UI 中另抄历史内容或奖励数值。`expedition_documents.gd` 的当前阅读城市、地区、页码和本次事件恢复量只属于临时界面状态；不会改写远征进度、侦察权限或玩家设置。事件纸页只确认已有结果，原来的恢复与抽卡仍由远征和军营系统负责。

纸张动效同样位于 `presentation/ui.tres`：`book_turn_fps` 是独立翻页动画帧率（当前12.5），8个纸张弯折姿态由 `book_page_turn.gd` 管理，总时长派生为8/12.5＝0.64秒，不再另存重复的翻页时长。`paper_motion_pixel_step` 仍是书页几何的整数像素步长（4逻辑像素）。

地图入口已于2026-10-28改成直接显示地图，旧 `map_unroll.gd` 及对应 `map_unroll_* / map_roll_width_pixels` 参数删除，不再创建地图快照或卷曲网格。

`presentation/ui.tres` 的 `map_pins` 只控制四角落钉：单枚落下0.11秒，依次相差0.04秒，落地短标记0.05秒，总长派生为0.28秒；`fps=24`只限制姿态更新，不改变全局帧率。`drop_height=42`、`inset=30` 为逻辑像素，`pixel_step=3`为绘制网格；`palette/shadow`为旧铜色钉头与硬边阴影。钉头的12×10图案留在 `map_pins.gd`，不作为平衡数值。四角钉子属于屏幕纸边装饰；原地图折痕继续随地形缩放和拖动。

真实进入地图时，`expedition_map.present()`播放一次纸声并开始落钉；城邦选择、缩放或界面重绘不重播。地图和按钮第一帧即可操作，不需要跳过。落定后停止处理与重绘；提前离开或弹出窗口立即收束并停止相关音频，没有延迟回调。系统“减少动画”偏好直接显示四枚静态钉子，保留纸声。书本继续独立使用原12.5帧/秒翻页。

`presentation/audio.tres` 的 `map_paper / map_pin` 分别复用原 `ui_paper_motion/page-turn.wav` 纸张录音（增益0.65）与 `cards/card-place-1.ogg` 短落点音（增益0.3）。原声音文件不改，使用独立原生播放器，纸声最多1路、落点最多4路；跟随主音量和音效开关，不受军团呼喊音量控制。声音、计时、落地状态不写入存档。验证入口：`test_map_entry.gd`、`test_paper_motion.gd`、`test_map_zoom_input.gd`、`test_map_paper_camera.gd`、`test_book_audio.gd`，证据在 `../output/map-pin-entry/`。

完整书页范围是 `rpg_ui.gd` 的 `BOOK_PAGES`，属于当前书本图集的几何约定：左页 `Rect2(20,0,492,584)`，右页 `Rect2(552,0,492,584)`。排版中心和动画取样必须共同读取此范围，不能再单独裁切正文内框；翻页宽度姿态以整页宽度的比例表示。书页外的封皮与书脊保持静止。更换书本美术时，一并检查 `test_book_layout.gd` 的整页/页脚截图对照及全部语言排版。

局部绘图几何、像素图案算法、精灵帧格、字符串分支和状态机仍留在所属场景/脚本/着色器中，属于实现与结构常量。这些不能当作普通平衡数值编辑。没有为了“外部化”而把每个加减乘除数字拆成不明含义的配置。

海面配色/像素水纹算法仍由 `shaders/atlas_sea.gdshader` 管理，战场水面由 `water_surface.gdshader` 管理，罗马 UI 配色由 `roman_ui.gdshader` 管理。本轮没有改写着色器算法。运行时的时间、风区数组与材质实例不保存到表现资产。

`atlas_sea_surface.gd` 管理按实际屏幕像素生成的海面缓存，尺寸随窗口与画布变换更新；`atlas_sea.gd.revision` 标记水纹时钟/风区材质参数变化，触发按需刷新。鼠标风区或拖动时旁路缓存，直接显示原材质；暂停时恢复冻结缓存。不要依赖路线层的 `queue_redraw()` 来刷新海面，也不要把缓存纹理存成地理源数据。调试代码若直接修改海面材质参数，应显式刷新缓存。改动缓存后运行 `test_atlas_cache.gd`、`test_atlas_sea.gd` 和地图布局检查。

缓存显示节点和实时海面 `source` 都必须使用 `MOUSE_FILTER_IGNORE`。实时海面会从 `gui_disable_input` 的缓存视口重新挂到地图中，不能依赖原父视口来屏蔽输入；绘制顺序靠后也不等于鼠标穿透。相关回归为 `tests/test_map_zoom_input.gd`，覆盖鼠标激活风纹后的滚轮、捏合、拖动、选城及弹窗遮挡。

地图 `boundary` 的轮廓使用固定重复图形：`inset` 是外侧留边，`side_depth` / `horizontal_depth` 分别是左右与上下凹凸深度，`period` 是齿间距，`pixel_step` 是像素网格。`shoulder_steps` 是单侧短斜肩的网格数，`crest_steps` 是平头长度的网格数；剩余长度平均留给前后直段。齿间距必须大于两侧斜肩与平头的总长度，且为两个网格长度的整数倍；`corner_size` 为四个网格长度的整数倍。`edge_color` / `ink_color` 与两种线宽管理描边；`paper_palette` 按暗到亮排列卷轴底色，`paper_seed` 独立生成纸纹，`paper_stain_scale` 控制斑痕大小（纹理像素，必须大于0）。纸纹只在本次运行首次需要时生成，之后复用缓存；修改纸纹参数后重新运行查看。修改深度或留边后运行 `tests/test_map_boundary.gd` 和 `tests/test_expedition_layout.gd`，检查55个地点仍完整可见且可点击。

`map_paper_wear.gd` 管理地图独有的固定折痕、短皱褶、边缘磨损和两处小翘角。归一化折线位置、断续色阶、细纹宽度和角尖尺寸属于美术绘制结构，不是玩法数值；颜色与网格仍读取 `boundary.paper_palette / pixel_step`。首次绘制生成一张640×360透明纹理（当前3逻辑像素网格）并复用，卷面背纹与旧纸底纹另外合并缓存。地图表面在地形之上、路线/标记/文字之下绘制，纸边装饰不接收鼠标事件。内部纸纹固定在地图世界坐标，随地形平移和缩放，但不随海面时钟、拖拽或缩放重新生成；开场从当前视图快照取样，不改展开几何。窗口纸边用独立缓存 `edge_texture()`，只含边缘磨损和小翘角，没有固定屏幕的褶皱。它不写入存档，不消耗游戏随机数，不改变情报窗使用的原纸纹。改动后重启查看，并运行 `tests/test_map_paper_wear.gd`、`tests/test_paper_motion.gd` 和 `tests/test_map_boundary.gd`。

地图内部使用固定容器 `map_layer`（节点名 `MapSurface`）。`paper_surface`（`MapPaperSurface`）是它的独立子节点，`expedition_atlas.gd` 的 `layout()` 将纸纹的位置、尺寸同步为地形的 `sea_surface.position / size`，共用5760×2520地图世界坐标、缩放和相机中心；不要另存一套偏移或缩放。海面缓存与实时海面也是容器子节点，使用 `show_behind_parent` 保持在纸纹之下；路线画布位于纸纹之上。不要缩放整个容器，否则屏幕海面缓存和城市点击区域会被重复变换。`tests/test_map_paper_camera.gd` 用真实加减、滚轮、触控板和拖动输入检查纸纹确实移动缩放，并用一个原生绘制的定位标记验证纸面坐标始终对齐地理位置；缓存/实时海面切换只影响海面，不改变纸纹定位。

## 文案与实际数值只留一个来源

- `localization/cards.json`：每张卡的名字、说明、详情、数字徽标、标签；保留中英文既有显示。
- `localization/interface.json`：97 条有稳定键名的界面文案。
- `localization/legacy_zh.json`：旧英文标签到中文的兼容翻译，供现有界面和战场飘字使用。
- `localization/bindings.json`：说明中的占位符如何读取平衡表，例如护盾值、燃烧时间、攻击加成、恢复比例、生命上限和总行军数。

例：修改 `effects.json` 中的军令护盾值，实际开战护盾、英文说明、中文说明与卡牌徽标会同时变化。不要再手动替换文案里的数字。效果叠加规则仍由现有逻辑决定，文案绑定不会新增效果。

## 每局状态、设置与存档边界

| 数据 | 唯一拥有者 | 何时清理/是否落盘 |
|---|---|---|
| 轮次、生命、建筑实例/等级/格子、下一实例 ID | `campaign.g` | 确认新远征后重置；由run_store写入当前远征存档。 |
| 永久教义、本局军令、训练等级、待放置建筑、已选牌 | `campaign.g` | 保留原有局内和城邦结算规则；不写回卡牌定义。 |
| 抽卡随机状态、已显示手牌、当前发牌轮次 | `campaign.g` | 查看地图/菜单不重抽；新远征重置。 |
| 正在交战的队伍生命/护盾/冷却/状态期限、弹道、波次、休整计时、战报 | `campaign.g.battle` | 只在本次战斗内存在；按原规则进入结果和结算。 |
| 当前城邦、已访问列表、目标/锁定目标、开局部署阶段、待领奖、结束标志、通知 | `expedition.state` | 新远征重置；返回主菜单和重新启动均可恢复安全节点。 |
| 本局战区顺序与重排后的路线/敌军 | `expedition` | 从只读地点/路线资料派生，不回写配置。 |
| 三地图抽签袋与其随机状态 | 主场景 | 同次程序运行保留；退出后重新开始；不消耗卡牌随机数。 |
| 语言、音效开关、主音量、独立音乐音量、人声音量、打击反馈开关、帧率上限 | 设置服务 | 保存到 `user://settings.cfg`，新开一局不重置。 |
| 地图缩放/镜头/选择、UI 状态、动画时钟、风区、粒子、材质、音效池与资源缓存 | 对应场景/表现对象 | 运行时临时数据；不写入配置或玩家设置。 |

**2026-10-28已加入关闭程序后读档续局。** “继续游戏”恢复最近的远征安全节点；跨局成长、账号解锁和长期征服进度仍未加入。详细保存与战斗重打规则见文首。

设置服务兼容旧的、没有版本号的 `settings.cfg`。保存时先写临时文件并验证，保留上一份可读设置后再替换正式文件。语言和字段类型会校验，音量限制在 0–1；设置文件损坏时尝试 `.bak`，两份都不可用才使用默认设置。未知较新版本不会当成本版本直接读取。

`fps_limit` 默认值为60，位于 `data/defaults/settings.json`；合法档位由 `scripts/data/settings_store.gd` 的 `FRAME_LIMITS` 统一定义为30、60、120、0，其中0代表无限制。旧文件缺少该字段时补入60；错误类型、不支持的数值和非整数不会写入引擎。设置服务同时接受JSON中的浮点数与ConfigFile中的整数。显示上限不属于战斗平衡参数，不修改 `simulation_step_seconds`；运行时通过 `Engine.max_fps` 应用，并关闭窗口垂直同步，避免第二个帧率上限。帧率实际值取决于设备和当前负载。

当前远征存档只保存游戏状态，不保存节点、材质、声音播放器等场景对象；后续修改格式或数值兼容规则必须明确版本与迁移行为，并验证已发手牌、随机状态和一次性结算标记。没有额外创建跨局成长/神明/装备存档。

## 离线工具和导出

- 地图工具现在读取 `content/routes.json`、`theaters.json`、`locations.json`；坐标输出到 `generated/`。`tools/data_source.cjs` 是离线聚合入口。
- 根目录混合数据已移走。原战斗/抽牌对照移到 `tests/fixtures/`，完整原始规则与地图也在这里冻结，防止一边修改实现、一边不小心改掉测试答案。
- `tools/import_web_assets.cjs` 保留历史源文件，但入口已禁用，防止覆盖用户后来更新的原生素材和测试基准。没有运行此工具。
- 地图、海岸、字体、纸牌音频生成工具本轮均未运行；它们属于明确的素材制作操作，不是普通调参步骤。
- 两个导出配置都包含分层后的 JSON 目录；测试、工具、文档不作为游戏内容导出。

## 修改后的检查方法

先运行 `tools/validate_data.gd`，检查数据引用、单位边界与素材容量。然后用 `tools/run_data_checks.py` 跑对应检查；它接受 `--godot` 指定 Godot 程序和 `--suite headless/native/all` 选择范围。需真实窗口/GPU的水面、布局和交互测试放在 native 组。

纯改部队数值：检查数据和战斗/远征回归。改路线：检查三种起点、所有分支、地图往返。改表现：检查相应原生画面和鼠标操作。改设置：检查旧格式、保存读取、损坏恢复。

`test_data_layers.gd` 额外覆盖完整数据重组一致、深层只读、不同局的隔离、文案随单一数值变化，以及坏设置/坏配置。`test_data_visual_parity.gd` 对照整理前的 22 张截图；它是这次“画面不变”要求的基准，以后主动换美术时应明确更新基准，不能为了让失败消失而覆盖它。

本次验证的具体数量与结果见上一级 `output/data-organization/verification-summary.json` 和 `after/` 日志。损坏设置测试会故意触发两条 ConfigFile 解析报错，用于验证备份恢复；其余脚本错误视为失败。


## 五首原生配乐（2026-10-26）

`data/presentation/audio.tres` 的 `music` 配置主菜单 The Pyre、地图/军营 Lord of the Land、普通战斗 Crusade、首领及终局战 Five Armies、历史书 Ancient Rite。五个原始 MP3 在 `assets/music/`，来源、下载日期与 SHA-256 在 `SOURCES.json`；CC BY 4.0 许可与曲目署名随导出保留，游戏设置内有“音乐鸣谢”。原文件不改动，播放时应用增益、首尾静音偏移、场景与循环交叉淡入淡出。

`music_volume` 默认 0.45，保存于玩家设置，与 `volume` 主音量相乘；旧设置补入默认值，音效开关只控制原音效。音乐滑块调到0立即静音，音乐时钟继续前进；恢复音量时平滑进入。同一城的多轮敌军和轮间休整共用一个播放位置；暂停、速度切换、战斗中查看地图都不会重播或改变音高。设置/暂停/战报把音乐降到62%，返回后恢复。

`scripts/music.gd` 只保留两个原生播放声部，场景切换2.4秒、曲末衔接2秒，使用等功率交叉淡入淡出。快速出现第三个目标时用0.18秒释放较轻的声部，再进入最新目标。每首曲目记录离开时的进度，因此历史书/菜单往返从原位置接续。播放参数与音量响应时长均留在上述 audio 配置；音乐不使用战斗模拟时间。

验证入口：`tests/test_music.gd`（原生窗口可额外生成设置截图及游戏内混音录音）、`tests/test_city_waves.gd`、`tests/test_data_layers.gd`。下载记录、修改前备份和运行证据在 `../output/music-integration/`。

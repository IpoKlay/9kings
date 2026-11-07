# 代码、数据和编辑位置

所有路径相对仓库根目录；正式工程只有 `godot-game/`。

## 最常用的入口

| 要改什么 | 位置 | 保持的约束 |
|---|---|---|
| 正常启动/菜单依赖 | `scripts/main.gd`、`scripts/main_menu.gd`（以下脚本均在godot-game内） | app依赖初始化、语言刷新不重建固定布局 |
| 菜单布局 | `scenes/ui/main_menu.tscn` | 原图 `assets/menu/forum-original.jpg` 完整等比，不改原画 |
| HUD布局 | `scenes/ui/battle_hud.tscn`、`scripts/tactical/trial.gd` | 移动 StartButton 保存后实机同位置；透明区不吞战场输入；信号只接一次 |
| 开放野战/山口/攻城 | `scripts/tactical/square_battle.gd`、`pass_battle.gd`、`siege_battle.gd` | 当前默认开放方场，山口为另一玩法 |
| 战斗阶段/60Hz步进 | `scripts/tactical/trial_rules.gd`、`trial.gd` | 暂停、半速、死亡生命周期与投射物顺序 |
| 单兵行为 | `scripts/tactical/regiment_soldiers.gd` | 不改变目标排序/并列评分/随机调用/原有指令转换 |
| 积分与挤压 | `scripts/tactical/soldier_physics.gd` | 顺序逐对排斥、盾阵锚定、岩壁回退；不是同时求和 |
| 冲锋 | `scripts/tactical/soldier_charge.gd`、`regiment_contact.gd` | 每骑状态/命中记录、余势、同次伤害不重复 |
| F/V/B/特殊兵 | `shield_wall.gd`、`soldier_volley.gd`、`soldier_blink.gd`、`soldier_specials.gd` | 能力按具体配置，不能从基础kind错误继承 |
| 弹道和死亡 | `soldier_projectile.gd`、`corpse_motion.gd`、`trial_field.gd` | 脚点/武器锚点分离；视觉不能额外扣血或士气 |
| 大范围神力 | `myth_powers.gd` 等神力脚本 | 本项目扩展，与原作逐兵伤害语义明确区分 |
| AI | `enemy_director.gd`、`pass_battle.gd`、`myth_powers.gd:select_target` | hold夹具不证明AI运行；山口夺旗/侧道不能被野战优化破坏 |
| 地形与寻路 | `pass_terrain.gd`、`scenes/battlefields/roman_pass.tscn` | 图片、部署和寻路必须读同一份位置/形状 |
| 墙体 | `scenes/battlefields/roman_siege.tscn`、`siege_wall.gd`、`siege_structures.gd` | Wall1–Wall7位置/Footprint/5次耐久；当前仅轴对齐，任意旋转缩放未验证 |
| 数值/能力 | `data/balance/tactical_trial.json` 的types、unit_variants、loadouts与指令配置 | 更新字段后同时核对旧脚本证据、界面、测试和导出 |
| 图集/表现 | `assets/rts-*`、`data/presentation/`、`trial_field.gd` | 64×64活体、八方向、真人比例、二维像素；尸体128画布不意味着单位放大 |

实际文件名请以目录为准；个别功能在本工程分文件组织。查函数先用 `rg 'func 函数名' godot-game/scripts/tactical`。

## 坐标与帧顺序

- 地面逻辑坐标属于 Rules、单位 pos、个人 position。地图 Sprite/树/旗与岩壁布局使用场景的显示平面；`projection/ground_basis` 负责地面→斜视显示（当前ground_y=0.75）。
- 屏幕点由 `(projection * ground - camera_offset) * zoom` 得到；逆变换必须完整反向。不能把屏幕拖动100像素当作地面移动100单位。
- 选取、框选、接触、净空、路线、武器锚点使用对应的实际个人脚点；受击绘制偏移不应累计成真实位移。
- 每步个人行为访问、到时攻击、死亡收集、物理积分/排斥、登记释放、既有投射物访问、来源最终移除有顺序依赖。刚生成投射物下一步才推进；本步晚杀死的士兵可能下一次访问才收集。
- `personal_unit_lookup/personal_target_bounds` 只在决策阶段有效，物理前清空；归队贴回原槽位时必须使该队范围失效。不能把这个缓存跨帧沿用。
- 士兵HP、cooldown、attack_pending、death_state、charge_run、shield_wall、wall_slot、personal_order等都在单位soldiers数组。重试应重新创建战斗对象，而不是复用旧状态。

## 编辑器入口不得退回运行时搭建

HUD独立按钮用锚点/offset调整；Container中的一排要移动父节点并调整theme separation。主题资源、选中态、纸签纹理以现有rpg_ui/Theme为准，不要换成灰色默认按钮。山口装饰与阻挡分组、油桶与出生标记必须保留。修改主菜单、HUD或地形后要做编辑保存→主菜单运行的位置验证。

## 当前可调参数（交接时值）

`data/presentation/rts_view.tres`：ground_y=0.75、figure_scale=1.0、frontage_scale=1.0、default_zoom=1.0、formation_turn_rate=3.2。用户早期要求默认阵宽约占战场15%、25%近景；下一轮需按实际可见战场宽度复测，不能只凭zoom值称已达标。

`tactical_trial.json:individual_charge`：speed=240、max_range=760、damage_multiplier=2.5、acceleration=1200、trample_decay=0.7、slow_per_hit=0.12、slow_cap=0.65、knockback=260、cavalry_knockback=3、scatter_angle=0.45。盾阵行军50、近战减伤0.6、远程减伤0.8；参数来源与版本必须随改动写明。不要换回早期未对齐原作的0.52秒/1.82倍提速建议。

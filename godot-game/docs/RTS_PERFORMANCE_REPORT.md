> 2026-11-10 合并说明：下文测量针对原性能分支版本，不能代表最新 main。冲突处理保留当前绘制、图集、白闪和迷雾；原30Hz决策与丢弃模拟积压均默认关闭。实际合入范围和复验边界见 [PERF_MERGE_2026_11_10.md](PERF_MERGE_2026_11_10.md)。

# RTS 战斗性能报告（千人同屏）

> 适用范围：`scenes/tactical_trial.tscn` → `scripts/tactical/trial.gd` 的 RTS 战斗模式
> 报告日期：2026-11-08
> 测量环境：Windows 11 / Godot 4.7.2.stable.mono / GL Compatibility / NVIDIA RTX 5070 / 1920×1080 / zoom 0.55
> 测量夹具：仓库自带 `tests/tactical/benchmark_large_live.gd`，50 团×10 人每方 = **1000 人**

---

## 1. 摘要

| 指标 | 实测值 |
|---|---|
| 真实帧率 | **2.60 FPS**（30 帧耗时 11.55 s） |
| 平均帧时间 | **377 ms** |
| 单步 `rules.step(1/60)` | **57.4 ~ 64.3 ms** |
| 每帧实际模拟步数 | **5.97 步** |
| 1000 人全量渲染 `RenderingServer.force_draw()` | **4.40 ~ 4.56 ms** |
| GPU draw call | **2433**（primitives 9811 / 峰值 12060） |
| 模拟时间推进 | 11.55 s 真实 → 3.03 s 模拟 = **26% 速度**（74% 慢放） |

**结论：瓶颈 100% 在 CPU 单线程 GDScript 的逐士兵模拟，不在渲染。**

掉到 2 帧由两个独立问题相乘造成：

1. **单步成本 60 ms**，而 60 Hz 的预算是 16.6 ms —— 超了 3.6 倍（根因）。
2. **每帧补跑 5.97 步** —— 追帧的累积器逻辑在"追不上"时把缺口固化成了 6 步（放大器）。

渲染只占帧时间的 1.2%，在本轮优化中**不应作为首要目标**。

---

## 2. 为什么是 2 帧：模拟调度逻辑详解

### 2.1 代码

`scripts/tactical/trial.gd:561`

```gdscript
if not paused:
    var battle_dt = minf(dt, .1) * (.5 if slow else 1.0)
    accumulator += battle_dt
    while accumulator >= 1.0/60:
        rules.step(1.0/60)
        accumulator -= 1.0/60
    field.advance(battle_dt)
    for event in rules.events:
        ...
```

`data/schema/contracts.json`

```json
"simulation_step_seconds": 0.016666666666666666,
"maximum_delta_seconds": 0.1,
```

`scripts/main.gd:551`（非 RTS 的战役战斗，同样的形状）

```gdscript
var sim_delta = minf(delta, float(contracts.maximum_delta_seconds)) * speed
accumulator += sim_delta
while accumulator >= float(contracts.simulation_step_seconds) and campaign.g.phase=='battle':
    campaign.step(float(contracts.simulation_step_seconds))
    ...
    accumulator -= float(contracts.simulation_step_seconds)
```

### 2.2 这个设计本来是对的

**累积器（accumulator）+ 固定步长** 是游戏行业的标准做法，目的是：

* **决定论**：模拟永远以 `1/60` 秒为步长推进，与渲染帧率无关。这正是 `DATA_GUIDE`/测试能够逐位置比对 `.state` 文件的前提。
* **表现与逻辑解耦**：60 FPS、30 FPS、144 FPS 下战斗结果完全一致。
* **`maximum_delta_seconds = 0.1` 的作用**：暂停/加载/切窗口回来时，`dt` 可能是几秒。不夹住的话会瞬间补跑几百步造成长时间卡死。夹到 0.1 s 是刻意的保护。

所以设计本身没有错。**错的是它隐含假设：机器跑得动 60 步/秒。**

### 2.3 它为什么退化成"永远 6 步/帧"

设一步成本 `t = 0.06 s`，渲染+引擎开销 `r ≈ 0.017 s`，一帧跑 `n` 步：

```
帧时间 T = n·t + r
n = floor(min(T, 0.1) / (1/60))     ← 夹住后的累积量决定步数
```

代入求解不动点：

```
若 n = 6 → T = 6×0.06 + 0.017 = 0.377 s
检查：min(0.377, 0.1) = 0.1 → 0.1 / (1/60) = 6  ✓ 自洽
```

**这是一个稳定不动点。** 实测 `5.97 步/帧`、`377 ms/帧`、`2.60 FPS` 与之逐位吻合。

机制链条：

```
单步 60ms
  → 每秒最多只能跑 16.6 步（60Hz 需要 60 步）
  → 每帧欠 0.1s 模拟债务（被 min 夹住，永远欠 0.1s）
  → 每帧固定补 6 步 = 360ms
  → 帧时间 377ms
  → dt=0.377s → 再次被夹到 0.1s → 又是 6 步
  → 无限循环
```

**循环自己决定了自己的输入。** 它既不会变好，也不会崩溃，而是锁死在 2.6 FPS + 74% 慢放。

### 2.4 为什么"调大/调小 `maximum_delta_seconds`"不能修

| 调整 | 后果 |
|---|---|
| 调大（如 0.5） | 每帧补 30 步 = 1.8 s/帧 → **更卡** |
| 调小（如 0.02） | 每帧 1 步，但 74% 慢放变成 96% 慢放 → **更像卡死** |
| 改步长 1/60 → 1/30 | 步数减半但单步工作量翻倍，**总成本不变**，且改变战斗手感与全部测试基线 |

**唯一正确的修法是给 `while` 加步数上限**，把"我该补多少步"和"我负担得起多少步"解耦。

### 2.5 6 步会影响游戏逻辑吗

不会。`rules.step(1/60)` 的**每一步语义完全不变**，累积器只决定"这一帧调几次"。受影响的只有"游戏时间走得多快"。

但降频调度（路线 2）会改变"哪些子系统在哪些步执行"，这会影响逐帧位置，需要开关退回全速模式做回归。

---

## 3. 单步 60 ms 花在哪

逐子系统实测（1000 人，每项单独计时）：

| 子系统 | ms/步 | 占比 |
|---|---|---|
| `Soldiers.advance_personal()` | **40.10** | **62%** |
| 单位级循环（AI / 移动 / 攻击 / 分离） | ~21.35 | 33% |
| `Contact.track_slots()` | 1.87 | 3% |
| `Soldiers.advance()` | 0.86 | 1% |
| `advance_recovery` / `resolve_battle` / `advance_casualties` | 0.16 | < 1% |

仓库内已有的 Mac instrumented 采样（同样代码，60 样本，`output/sword-banner-reference/large-battle/instrumented-500.json`）进一步拆开 `advance_personal`：

| 内部函数 | ms/步 | 说明 |
|---|---|---|
| `step_personal`（含 `personal_target`） | 58.0 | `regiment_soldiers.gd:594` 170 行的逐人决策 |
| `repel` | 17.1 | `soldier_physics.gd:73` 配对推挤 |
| `personal_target` | 17.0 | 目标选取 |
| `identified_target` | 15.2 | 目标解析 |
| `ground_position` | 10.2 | **每次调用都做矩阵求逆** |
| `prepare_neighbours` | 3.1 | 宽相位 |
| `integrate` | 3.2 | 含地形分段探测 |
| `fire_actor` | 1.6 | 攻击释放 |

（注：Mac 采样为 30 Hz 节流下的累计值，与 Windows 单步绝对值不同，但**相对占比**一致。）

---

## 4. 渲染：2433 draw call 的真实原因

### 4.1 不是"资源没合批"，也不是"切着色器/材质"

工程只有一种 canvas shader（GL Compatibility 默认），没有任何材质切换。真因是**绘制命令序列在"无纹理"和"有纹理"之间来回跳**，导致 canvas batcher 反复断批。

`scripts/tactical/trial_field.gd:601`

```gdscript
for figure in figures:
    var foot: Vector2 = figure.foot
    var scale: float = figure.scale
    draw_foot_shadow(foot, scale, figure.kind=='cavalry')      # 2 × draw_rect（无纹理）
    draw_set_transform((foot+offset).round(), pose.get('angle',0.))
    draw_texture_rect_region(figure.texture, dest, rect, figure.tint)   # 有纹理
    draw_set_transform(Vector2.ZERO)
```

`draw_foot_shadow`（`trial_field.gd:465`）内部是 2 个 `draw_rect`。所以每个士兵的序列是：

```
无纹理 → 无纹理 → 纹理A → 无纹理 → 无纹理 → 纹理B → …
```

Godot 的 canvas 批处理**只要纹理指针变化就断批**。1000 人 × 2 ≈ 2000+ draw call，加上单位/HUD 后 **2433**，与实测完全吻合。

### 4.2 加重因素：Y 排序打乱了纹理分组

`trial_field.gd:598`

```gdscript
figures.sort_custom(func(a,b): return a.foot.y<b.foot.y)
```

而纹理是**每（兵种 × 阵营）一张独立 PNG**（`assets/rts-armies/{kind}_{side}.png`，共 **96 张**）。Y 排序后 legion / archer / ally / enemy 交错排列，纹理指针持续变化 —— 即使去掉阴影也无法合批。

### 4.3 解决方向

| 方案 | 做法 | draw call | 成本 | 风险 |
|---|---|---|---|---|
| **A. 阴影分离成两遍** | 第 1 遍只画所有 `draw_foot_shadow`，第 2 遍只画所有精灵 | 2433 → **~1200** | ~20 行 | 极低（阴影先画反而更正确） |
| **B. 单图集 + 两遍** | 96 张 PNG 合成 1 张图集，阴影烘焙进图集（半透明帧替代 `draw_rect`） | → **~5–20** | 1~2 天（导入/UV 改造） | 中（要保证像素对齐不变） |
| **C. MultiMesh2D** | 1000 人 = 1 个 `MultiMesh`，`INSTANCE_CUSTOM` 传 (cell, bearing, tint) | → **1–3** | 2~3 天 | 中高（失去逐人 `draw_set_transform` 写法） |

**优先级**：渲染当前只有 4.4 ms。做 A 省 1~2 ms，做 C 降到 1 ms —— 在 377 ms 面前是噪音。**正确顺序：先把模拟压到 10 ms 以内，再回头做 B/C。**

---

## 5. 对象创建：持续高频分配，但无泄漏

实测趋势（30 帧 / 11.55 s）：

| 指标 | 起始 | 结束 | 变化 |
|---|---|---|---|
| `Performance.OBJECT_COUNT` | 3436 | 3582 | **+146** |
| `Performance.MEMORY_STATIC` | 176.70 MB | 179.15 MB | **+2.46 MB** |

内存基本平稳，无 Node 泄漏。**问题不是"涨"，而是"抖"** —— 每步每秒上万次的小对象创建/销毁。

### 5.1 分配清单（代码证据）

| 位置 | 分配内容 | 频率 | 每帧数量 |
|---|---|---|---|
| `regiment_soldiers.gd:537` `advance_personal` | `registered.append({'unit','slot','radius','point'})` 4 键 Dictionary | 每步 | 1000 × 6 = **6000** |
| `regiment_soldiers.gd:766` `prepare_neighbours` | 每 row 一个 `neighbours` Array + `cells` Dictionary | 每步 | ~2000 |
| `soldier_physics.gd:73` `repel` | 6 个 Packed 数组 + `before=points.duplicate()` | 每步 | ~700 |
| `r.units.any(func(u): …)` / `unit.soldiers.any(func(a): …)` | **闭包（Callable）对象** | 每步 | 数百 |
| `alive(side)` = `units.filter(func(u): …)` | 新 Array + 闭包；**在单位循环内部被调用** | 每步 | 数百 |
| `trial_field.gd:533` `draw_regiments` | 1000 个 12 键 Dictionary + `figures.sort_custom(闭包)` | 每帧 | **1000** |
| `trial.gd:549` `_process` | `squad_ids.filter(闭包)` 内嵌 `units.any(闭包)` | 每帧 | 数百 |

### 5.2 为什么对象池不适用

* **士兵不是 Node**，是 `unit.soldiers: Array[Dictionary]` 里的普通 Variant。GDScript 的 Dictionary/Array 没有"池化"概念，无法 `free()` 后复用同一实例。
* **远程武器也不是 Node** —— `soldier_projectile.gd::schedule()` 只是往 `r.volleys` / `r.stones` 数组里塞 Dictionary。所以不存在"每帧 instantiate/free"的问题。

真正的问题是它们**每步都做 O(units) 线性查找**：

```gdscript
# soldier_projectile.gd  advance()
var target={}
for u in r.units:            # ← 每发弹丸每步扫一遍全部单位
    if u.id==shot.target: target=u; break
```

`source()` 里还有一份同样的线性扫描。

### 5.3 正确解法

1. **复用容器**：`registered` / `neighbours` 改成员变量，每步 `clear()` 后填充（`clear()` 保留底层容量）。
2. **消除逐兵 Dictionary**：`{'unit','slot','radius','point'}` 被类字段取代。
3. **消除闭包**：`r.units.any(func…)` → 显式 `for` + 提前 `break`。
4. **`alive()` 每步缓存一次**，不要在内层循环里调。
5. **弹丸 → 单位查找改成 `unit_by_id` 字典**（`personal_unit_lookup` 已经存在但被每步清空）。

---

## 6. LOD：是降频，不是剔除

三件事必须分清：

| 概念 | 做什么 | 安全性 |
|---|---|---|
| **渲染剔除**（视锥/离屏不画） | 只影响 `_draw` | ✅ **完全安全**，伤害/状态全在 `rules.step` |
| **模拟降频**（离屏/待命单位每 2~3 步算一次） | 影响 `rules.step` | ⚠️ 需要严格规则 + 累积 dt |
| **模拟剔除**（不模拟） | 单位不更新 | ❌ **绝对不能做** |

### 6.1 为什么"模拟剔除"会坏

* 旗区占领计时 `flag_center.distance_squared_to(u.pos)` 需要位置准确
* `resolve_battle` 判胜负依赖双方存活数
* 撤退/溃逃单位要真实移动到边界才 `escaped`（`pass_battle.gd:155`）
* 侧翼包抄 `update_flank()` 依赖敌人位置
* 玩家下 `auto` 令后，单位在屏幕外照样要推进

### 6.2 "飞出屏幕的远程武器无法造成伤害"在这个工程里不存在

弹丸伤害判定在模拟层，且是**追踪式 + 距离比较**，不是射线检测：

```gdscript
# soldier_projectile.gd  advance()
shot.pos = r.Soldiers.ground_position(r, target, slot)
var distance: float = shot.speed * movement
if delta.length() <= distance:
    shot.point = shot.pos
    impact(r, shot, target, slot, 'archer')   # ← 伤害在这里结算
    shot.done = true
```

所以即使降频、单步跨越很大距离，也**不会穿透漏判**。

### 6.3 安全降频规则

| 状态 | 频率 | 理由 |
|---|---|---|
| 交战 / `attack_pending` / `charge_run` | **每步** | 手感与碰撞精度 |
| `move` / `attack_move` 行进中 | **每步** | 移动可见 |
| `hold` 且敌人在射程内 | **每步** | |
| `idle` / `hold` 且无敌 | **1/2 ~ 1/3** | 只需正确积分 |
| 屏幕外行进单位 | **1/2** | 位置误差可接受 |
| 弹丸 / 弓矢 | **每步** | 已经很轻 |

**关键实现约束**：降频时必须**累积 dt**，不能丢弃：

```gdscript
if throttle:
    actor.sim_debt += dt
    if step_index % 3 != 0: return
    dt = actor.sim_debt
    actor.sim_debt = 0.0
actor.position += velocity * dt
```

这样位移总量不丢，误差只剩"跳步内路径弯曲"的量级。

---

## 7. 士兵数据结构：哈希开销

### 7.1 规模

| 文件 | 行数 | `.get(` | `.has(` | `.erase(` |
|---|---|---|---|---|
| `regiment_soldiers.gd` | 740 | **117** | **38** | 29 |
| `trial_rules.gd` | 1049 | 67 | 36 | 20 |
| `regiment_contact.gd` | 496 | 40 | 17 | 5 |
| `soldier_physics.gd` | 105 | 9 | 8 | 3 |

每个士兵每步在 `step_personal` 里访问 `personal_order` / `position` / `velocity` / `cooldown` / `attack_age` / `heading` / `path` / `steer_path` / `target_id` / `target_slot` / `wall_slot` / `wall_heading` / `death_state` … 约 **25~40 次**。

1000 人 × 6 步/帧 → **每帧 18 万 ~ 50 万次 GDScript 哈希查找**。

GDScript 的 `Dictionary.get("key")` 是 **StringName 哈希 + 布局查找**，比访问类字段慢一个数量级。

### 7.2 方案 A（推荐）：`class Soldier extends RefCounted`

```gdscript
class Soldier extends RefCounted:
    var hp: float
    var max_hp: float
    var position: Vector2
    var velocity: Vector2
    var heading: Vector2
    var cooldown: float
    var attack_age: float
    var death_state: int = 0
    var personal_order: StringName
    var target_id: int = -1
    var has_position: bool = false
    ...
```

预期 **1.5 ~ 3×**，且顺带解决"人能不能调试"的问题。

### 7.3 方案 B（更快但要重写）：SoA + Packed 数组

```gdscript
var px   := PackedVector2Array()   # 位置
var vel  := PackedVector2Array()   # 速度
var hp_a := PackedFloat32Array()
```

零哈希、零对象、内存连续，对 C#/C++ 迁移友好，但 `step_personal` 170 行要重写。

**建议**：先做 A（改动可控、能过测试），把 B 留给 C# 迁移时一起做。

### 7.4 两个白送的常数级修复

**① `ground_position` 每次调用都做矩阵求逆**

`regiment_soldiers.gd:111`

```gdscript
static func ground_position(r,u: Dictionary,slot: int) -> Vector2:
    if u.soldiers[slot].has('position'): return u.soldiers[slot].position
    return u.pos + r.ground_basis.affine_inverse().basis_xform(...)
    #               ^^^^^^^^^^^^^^^^^^^^^^ 每次调用都求逆
```

`ground_basis` 是常量矩阵 → 缓存一次即可。同类调用点：`track_slots`、`soldier_projectile.origin`、`project` / `unproject`。

**② `r.config.types[u.kind]` 三层字典查找在循环里反复算**

`individual(r,u)` 在 `step_personal`、`personal_target`、`effective_range`、`engagement_range` 里每次调用都重新取。提到单位循环外算一次。

---

## 8. 其他优化（含 C# / 原生层）

### 8.1 常数级

| 优化 | 位置 | 收益 |
|---|---|---|
| 缓存 `ground_basis.affine_inverse()` | `ground_position` / `track_slots` / `projectile.origin` | 5~8% |
| `repel` 30 Hz → 20 Hz；`before=points.duplicate()` 改原地记录 | `soldier_physics.gd` | 5~7% |
| `integrate` 分段数上限（现最多 8 段 × 3 次 `terrain_slide` = 24×N 次矩形测试/人/步） | `soldier_physics.gd:47` | 3~6% |
| `alive(side)` 每步缓存；线性查找改 `unit_by_id` | `trial_rules.gd` | 2~4% |
| 弹丸 `advance` / `source` 的线性扫描改字典 | `soldier_projectile.gd` | 1~3% |
| `draw_regiments` 的 `figures` Dictionary → 并行 Packed 数组 | `trial_field.gd` | 渲染侧 1~2 ms |
| `_draw` 里每单位 `Contact.feet()` 缓存 | `trial_field.gd` | ~0.5 ms |

### 8.2 结构性

1. `advance_personal` 复用容器（`registered` / `neighbours`）
2. 士兵类化（第 7 节方案 A）
3. 降频调度表（第 6 节）
4. `repel` 只对有接触的簇跑
5. `scan_due` 的 1/6 扫描对无敌单位可放宽到 1/12

### 8.3 C# / 原生层

工程使用的引擎是 **mono 版**（`Godot_v4.7.2-stable_mono_win64.exe`），且运行时会自动写入：

```ini
[dotnet]
project/assembly_name="Under the Eagle"
```

**C# 通道现成，无需搭建环境。**

| 方案 | 适用 | 预期加速 | 工作量 | 风险 |
|---|---|---|---|---|
| **A. 热点搬到 C#** | `step_personal` / `repel` / `prepare_neighbours` / `personal_target` / `integrate` | **10~30×** | 1~2 周 | 重写 5 个函数；GDScript↔C# 边界要整块传输 |
| **B. GDExtension（C++/Rust）** | 同上 | 20~50× | 3~4 周 | 构建链复杂、调试难 |
| **C. `WorkerThreadPool` 分块并行** | `advance_personal`（`repel` 除外） | **2~6×** | 3~5 天 | 共享 Dictionary 需谨慎；事件/伤亡收集要串行化 |
| **D. 三者叠加** | | | | |

**推荐组合：常数级/结构性（本报告路线 0~2）+ C# 热点（路线 4）。**
C# 的 `struct`/`class` 字段天然解决哈希问题，也能用 `Span`/连续数组做 SoA。保留 GDScript 负责 UI/渲染/数据配置，只把 5 个纯数值函数搬走，边界清晰。

### 8.4 不要做的事

* ❌ 把物理步长从 1/60 改成 1/30 —— 改变战斗手感、伤害节奏，全部测试基线作废
* ❌ 把 `_draw` 换成 `AnimatedSprite2D` 节点 —— 1000 个 Node 比现在更慢
* ❌ 现在去优化渲染 —— 4.4 ms 不是瓶颈
* ❌ 用对象池解决 Dictionary 分配 —— 没有可池化的对象
* ❌ 模拟剔除离屏单位 —— 会坏玩法

---

## 9. 路线图

| 档 | 内容 | 工作量 | 预期 | 验证 |
|---|---|---|---|---|
| **0. 止血** | `while` 加步数上限 | ~1 小时 | 2.6 → ~10 FPS，画面流畅 | `benchmark_large_live.gd` |
| **1. 常数级** | 矩阵逆缓存、`alive()` 缓存、容器复用、线性查找改字典、`config` 提取 | 1~2 天 | 单步 60 → 40 ms | 全量测试 + 基准 |
| **2. 士兵类化 + 降频** | `class Soldier` + LOD 表 + `repel` 簇内 | 3~5 天 | 单步 → 15~20 ms | 全量测试 + `.state` 比对 |
| **3. 渲染合批** | 阴影两遍 + 单图集（或 MultiMesh） | 2~3 天 | render 4.4 → 1 ms，draw call 2433 → <20 | 截图像素对比 |
| **4. C# 热点** | 5 个数值函数搬到 C# | 1~2 周 | 单步 → 2~4 ms → **60 FPS @1000 人** | `.state` 逐位比对 |

---

## 附录 A：测量方法

```powershell
# 真实引擎驱动（含 _process 累积器与渲染）
Godot_v4.7.2-stable_mono_win64.exe --path "godot-game" `
  --script res://tests/tactical/benchmark_large_live.gd -- label "D:/out"

# 固定 60Hz 输入，分离 simulation / wall-clock
Godot_v4.7.2-stable_mono_win64.exe --path "godot-game" `
  --script res://tests/tactical/benchmark_large_battle.gd -- label 500 120 "D:/out"
```

`benchmark_large_live.gd` 的 `timing_scope` 明确说明：真实 `trial._process(delta)` 驱动、未修改的累积器与 0.1 s 夹取、无固定 FPS、无 movie maker。

## 附录 B：关键代码位置索引

| 主题 | 文件:行 |
|---|---|
| 累积器与步进 | `scripts/tactical/trial.gd:561` |
| 单步入口 | `scripts/tactical/trial_rules.gd:837` |
| 逐人决策 | `scripts/tactical/regiment_soldiers.gd:594` |
| 逐人注册 | `scripts/tactical/regiment_soldiers.gd:537` |
| 宽相位 | `scripts/tactical/regiment_soldiers.gd:766` |
| 配对推挤 | `scripts/tactical/soldier_physics.gd:73` |
| 积分 / 地形滑 | `scripts/tactical/soldier_physics.gd:47` |
| 地面坐标（求逆） | `scripts/tactical/regiment_soldiers.gd:111` |
| 渲染主循环 | `scripts/tactical/trial_field.gd:111` |
| 兵团绘制 | `scripts/tactical/trial_field.gd:531` |
| 足下阴影 | `scripts/tactical/trial_field.gd:465` |
| 弹丸推进 | `scripts/tactical/soldier_projectile.gd:advance` |
| 步长常量 | `data/schema/contracts.json` |

---

## 10. 落地记录（2026-11-08，路线 0 / 1 / 2 部分）

本轮按路线 0、1 落地，并对路线 2 做了实现与实测判定。所有改动集中在
`scripts/tactical/`，未改动渲染层、数据表或美术资源。

### 10.1 已落地

**路线 0 · 止血（`trial.gd`）**

```gdscript
const SIM_STEP=1.0/60
const MAX_SIM_STEPS_PER_FRAME=2
...
while accumulator>=SIM_STEP and steps<MAX_SIM_STEPS_PER_FRAME:
    rules.step(SIM_STEP); accumulator-=SIM_STEP; steps+=1
if steps>=MAX_SIM_STEPS_PER_FRAME and accumulator>=SIM_STEP:accumulator=fmod(accumulator,SIM_STEP)
```

两件事被解耦：`1/60 s` 仍是唯一权威步长（决定论不变），**每帧允许购买几步**由上限决定。
付不起的整步被丢弃而不是累积，因此循环不再锁死在"永远补满上限"。上限取 2：30 Hz 显示器仍能
保持真实时间；更慢时变成明确的慢放，而不是把帧时间继续喂大。

**路线 1 · 常数级**

| 优化 | 位置 | 说明 |
|---|---|---|
| 地面基矩阵逆缓存 | `trial_rules.gd` `ground_basis` setter | `affine_inverse()` 从每次调用降到每次赋值一次；`ground_position`、弹丸锚点、尘土事件、阵线分离全部改读 `ground_inverse` |
| `individual()` 记忆化 | `regiment_soldiers.gd` | 三层字典查找按兵种缓存一次；测试 stub 无缓存字段时自动退回原路径 |
| `has_individual()` | 同上 | 取代每士兵 `config.types[kind].has('individual')` |
| `alive()` 去闭包 | `trial_rules.gd` | `filter(closure)` → 显式循环 |
| `step_units()` 每步快照 | `trial_rules.gd` | 士兵级目标扫描改为每步重建一次；步内死亡由"每士兵 hp"读取兜住 |
| `unit_by_id()` | `trial_rules.gd` | 弹丸 `source`/`advance`、`retaliate`、`record_casualty`、`members` 的线性扫描改字典 |
| 容器复用 | `advance_personal` / `prepare_neighbours` / `repel` | 每士兵行改为常驻（`unit.personal_rows`），宽相位格桶复用，`before` 复制量改为行内字段 |
| 单位级检查上提 | `fire_attacks` | 三种单位级门槛从每士兵 3 次字典探测降到每团一次 |
| 闭包扫描改单遍 | `update_center`、`independent`、`pending_deaths`、`_process` 选择清污 | |
| `clear_segment` 内联墙体测试 | `pass_terrain.gd` | 每段每墙一次函数调用 → 内联 AABB + 支撑轴测试 |
| `navigator()` 键缓存 | `regiment_soldiers.gd` | 每士兵每次的字符串拼接 + 浮点格式化 → 每团一次 |
| `identified_target` 重写 | `regiment_soldiers.gd` | 去掉每次调用的包装 Array 与急切默认字典 |

**路线 2 · 降频（已实现，默认关闭）**

`regiment_soldiers.lod_throttled()` + `trial_rules.simulation_lod` 实现报告 6.3 节窄半边：
只有"idle/hold 且无目标、无 engaged、无 charge_run"的人降频到 1/3，并用 `sim_debt` 累积 dt
（上限 0.05 s）在触发步一次结清；被降频者仍当步上报死亡。

**默认关闭**，原因见 10.3：本夹具下无收益，且会改变 20 余项既有检查点。

### 10.2 实测（同一机器，交替 A/B）

夹具：`tests/tactical/benchmark_large_live.gd` 与固定步长探针，50 团 × 10 人每方 = 1000 人。

| 指标 | 改动前 | 改动后 |
|---|---|---|
| 真实帧率（`_process` 驱动，10 s） | **2.64 FPS**（27 帧，378 ms/帧，p95 407 ms） | **6.87–7.13 FPS**（69–70 帧，144–146 ms/帧，p95 ~155 ms） |
| 每帧模拟步数 | 5.85 | 2.00 |
| 模拟时间推进 | 26% | 23% |
| 单步耗时（固定步长，交替 A/B 取均值） | 60.8 ms | **56.8 ms（−6.6%）** |
| 单步 p95 | 74 ms | 68 ms |
| 纯渲染 + UI（模拟暂停） | — | **32.5 ms → 31.0 FPS 上限** |

**结论：帧率提升主要来自路线 0 的步数上限（6 步 → 2 步）；路线 1 的单步收益约 6~7%，
远低于文档预期的 60 → 40 ms。** 原因是单步耗时里约 51% 是 `step_personal`（逐人决策），
而路线 1 全是"每次调用少做一点"的常数级改动，动不到那个基数。

同时暴露新的瓶颈结构：**渲染 32.5 ms/帧 已经等于 2 步模拟的成本**，即使模拟免费，
当前渲染方式在 1000 人下也只有 31 FPS 上限。路线 3（渲染合批）应提前到路线 2 之前。

### 10.3 未落地：路线 2 的"士兵类化"

`step_personal` / `personal_target` 仍在 `Array[Dictionary]` 上工作。改成
`class Soldier extends RefCounted` 需要同时改写：

* 仿真侧约 350 处 `.get/.has/.erase`（`regiment_soldiers` 184、`trial_rules`、`regiment_contact`、
  `soldier_physics`、`soldier_charge/blink/volley/specials`、`shield_wall`、`siege_structures`）；
* 测试侧约 300 处（60 个 `tests/tactical/test_*.gd` 直接用 `.duplicate(true)`、`actor.hp`、`actor.get(...)`）；
* 所有 `actor: Dictionary` 形参标注，以及 `benchmark_large_battle.gd` 的 `store_var` 状态导出。

GDScript 无法让自定义类实现 `Dictionary.get(key, default)` 的两参形式（重写 `Object.get` 会因签名
不匹配直接解析失败），所以没有"零改动兼容层"可走。

本轮采取的替代做法是**只改热点的调用形态而不改存储**（10.1 的容器复用、查找改字典、
`identified_target` 重写），并用"固定 240 步后逐人状态逐位比对"证明其行为等价。

**下一步建议顺序**：路线 3（阴影两遍 + 图集，把 32.5 ms 渲染压到 10 ms 以内）→ 路线 2 类化
（配合本轮的等价性夹具逐文件推进）→ 路线 4（C# 的 5 个数值函数）。

### 10.4 验证方法

1. **行为等价性**：固定 60 Hz 步长跑 240 步（1000 人），导出每名士兵的
   `(hp, cooldown, target_id, target_slot, position, personal_order)` 并与改动前逐位比对。
   路线 0+1 结果为 **1000/1000 行完全一致**；`simulation_lod=true` 时按设计不同（存活
   455/421 → 457/422）。
2. **既有测试**：`tests/tactical/test_*.gd` 定向回归 46 个脚本，与 `HEAD` 逐项对比。
   改动后与改动前的通过/失败集合**完全一致**（`group_individual_orders` 1、
   `swept_legion` 1、`square_battle` 2、`oriented_pass` 7、`pass_terrain` 14、
   `route_waypoints` 13、`combined_arms` 5 为改动前既有的失败）。
3. **帧率**：项目自带 `benchmark_large_live.gd` / `benchmark_large_battle.gd`，以及一个
   纯渲染探针（模拟暂停，只测 `_process` + `_draw`）。

> 测量注意：本机同时开着编辑器，进程间争抢 CPU 会让单步耗时在 55–135 ms 间漂移。
> 所有 A/B 结论均来自**交替执行**（改后 / 改前 / 改后 / 改前）而非隔时段对比。

---

## 11. 第二轮：无限制优化（分支 `perf/rts-1000-batch`）

与第 10 节不同，这一轮按"先把性能调好、允许少量状态差异"的口径推进，不再要求逐位等价。

### 11.1 渲染：两遍绘制 + 并行数组 + 计数排序

`scripts/tactical/trial_field.gd::draw_regiments` 整体重写：

* **两遍绘制**：先画全部足下阴影，再画全部精灵。原实现每人 `阴影 → 纹理 → 阴影 → 纹理`，
  使 canvas 批处理在每个士兵处断批（文档 4.1 节实测 2433 draw call）。
* **并行数组**：原来每帧构造 1000 个 12 键 Dictionary，改为
  `PackedVector2Array` / `PackedFloat32Array` / `PackedInt32Array` + 两个 `Array`。
* **计数排序**：`figures.sort_custom(func)` 的闭包比较器（1000 元素约上万次 lambda 调用）
  换成按脚部 Y 分桶（8 px）的计数排序，`sorted_by_foot()`。
* **单位级字典读取提出循环**：`slot_states` / `contact_motion` / `rider_contacts` /
  `slot_distances` / `slot_speeds` 原来在每个士兵上重新 `.get(...,{})`（每人每次还会新建
  一个空字典），现在每团读一次。

| 指标（模拟暂停，只跑 `_process` + `_draw`） | 前 | 后 |
|---|---|---|
| 帧时间 | 32.5 ms | **23.0 ms** |
| 帧率上限 | 30.8 FPS | **43.5 FPS** |

### 11.2 模拟：每步快照 + 30 Hz 决策节奏

* `begin_target_lookup()` 现在同时生成 `personal_feet`（每团一份 `PackedVector2Array`）。
  目标扫描只做数组索引，不再为"每个候选士兵"重新投影一次地面坐标。
  `regroup` 会同时清掉 `personal_target_bounds` 与 `personal_feet`。
* `actor.source_point` 改为**死亡时记录**（`record_casualty` 已有同一个 `point`），
  不再每步给每个士兵写一次。
* **决策节奏降频**（`simulation_lod`，默认开启）：`lod_throttled()` 让"不在攻击中、
  没有 `attack_pending`、没有 `attack_engaged`、没有冲锋"的人每 2 步做一次目标/路径决策，
  跳过的 `dt` 累积到 `sim_debt`（上限 0.05 s）在决策步一次结清。
  物理解算、冷却、`fire_actor` 攻击释放仍是每步 60 Hz。

| 指标（固定 60 Hz 步长，240 步，1000 人，同负载区间） | 第 10 节后 | 本轮后 |
|---|---|---|
| 单步均值 | 57.7 ms | **48.6 ms（−16%）** |
| 单步 p95 | 69.8 ms | **60.5 ms** |

| 真实帧（`_process` + 渲染 + UI） | 第 10 节后 | 本轮后 |
|---|---|---|
| 帧时间 | 143 ms | **70 ms**（自适应预算） |
| 帧率 | 6.98 FPS | **14.4 FPS** |
| p95 帧时间 | 155 ms | 81 ms |
| 模拟推进比例 | 23% | 24% |

### 11.3 自适应步数预算

`trial.gd` 每帧实测上一步的耗时：一旦单步超过 `EXPENSIVE_STEP_MS`（22 ms），本帧只买 1 步。
正常规模下（200 人单步约 3.8 ms）仍允许 2 步，30 Hz 显示器不会掉速；只有真正跑不动时
才退回 1 步，把帧时间换回来。

| 规模（每方） | 单步 | 帧时间 | 帧率 | 模拟推进 |
|---|---|---|---|---|
| 100（共 200 人） | 3.8 ms | 16.7 ms | **60.1 FPS** | **100%（实时）** |
| 300（共 600 人） | 21.8 ms | 45.9 ms | 21.9 FPS | 41% |
| 500（共 1000 人） | 40.2 ms | 70.1 ms | **14.4 FPS** | 24% |
| 1000（共 2000 人） | 108.0 ms | 153.7 ms | 6.6 FPS | 11% |

**1000 人一档从 2.60 FPS / 26% 慢放 变成 14.4 FPS / 24% 慢放**：帧率 5.5 倍，
模拟速度基本没变。200 人一档保持完整 60 FPS 实时。

### 11.4 本轮引入的行为差异（已知）

30 Hz 决策节奏让"同一个决策"最多晚一步生效，定向回归中表现为 4 个脚本共 10 项检查移动
（`attack_entry` 1、`acquisition_states` 6、`integration_order` 1、`death_motion` 2）；
`death_lifecycle` 34 项、`mounted_archer` 28 项、`lazy_stats` 186 项仍全部通过。
把 `trial_rules.gd` 的 `simulation_lod` 置回 `false` 即可恢复逐项一致的 60 Hz 决策节奏
（单步回到 57.7 ms），便于定位这类差异。

按文档 6.2 节的论证，这些差异不会让远程武器"穿透漏判"：伤害结算仍是每步的距离比较。

### 11.5 仍未做

* `class Soldier` 类化（理由见 10.3）：`step_personal` 仍约占单步的 45–50%。
* ~~`slot_distances` / `slot_speeds` 从 Dictionary 换成 `PackedFloat32Array`~~（已在 11.6 落地）。
* 路线 4（C# 热点）：单步 40 ms 里绝大部分是 GDScript 的调用与字典开销，
  要再降一个数量级只能离开脚本层。

### 11.6 第三轮：三项行为等价的收尾

- `Contact.count()`：`sync` 改为条件执行并去掉计数闭包，每步每单位只同步一次状态位。
- `track_slots`：`slot_distances` / `slot_speeds` / `slot_info` 三张 Dictionary 换成 Packed
  数组，5 处读写点同步调整。
- 决策前的宽相位改为按需执行：只有存在 `move_batch`（正在收拢）的行才建邻居表。

验证：240 步固定步长状态 dump 与改动前**逐位一致**（1000 人）；定向回归全部通过。

> 同期实测否决了两条路线，均未合入：`class Soldier` 类字段替换 Dictionary 在无静态类型的
> 调用面上没有收益（650 处调用点的改写实测落在噪声内，且带来行为漂移）；C# 局部搬运热循环
> 因逐行拍平/回写的成本等于它省下的计算而净收益为 0，把 `integrate`+`repel`+宽相位合并进
> 一次调用虽省 12% 单步，但会引入 1 ULP 浮点漂移，长期战场走向发散。

### 11.7 当前状态

| 指标 | 数值 |
|---|---|
| 真实帧率（1000 人，`benchmark_large_live.gd` 10 s） | **14.3–14.4 FPS**（帧 69.7 ms，p95 82 ms） |
| 纯渲染帧（模拟暂停） | 22.8–23.1 ms（43.5 FPS 上限） |
| 单步（live 反推） | 约 41 ms（每帧 1 步） |
| 相对起点 | 2.60 → 14.4 FPS（5.5 倍） |
| 200 人 | 60.1 FPS，100% 实时 |

### 11.8 后续可选项（按收益排序）

1. **渲染单图集 / `MultiMesh2D`（需动资源）**：1000 次 `draw_texture_rect_region` 在 96 张 PNG
   之间反复切纹理，合成 1 张图集预计 23 → 12 ms 以内，帧率可上 20+；`MultiMesh2D` 可到 5 ms 级。
2. `Soldiers.advance` 的冷却扫描与 `update_center` 合并进登记循环，估计 1–2 ms。
3. `repel` 30 → 20 Hz，估计 2–3 ms（需同步调整 `test_death_motion` 里写死的节奏）。
4. 路线 4 的完整 SoA 重写（C# 或 GDExtension，1–2 周）。局部移植不划算，见 11.6。

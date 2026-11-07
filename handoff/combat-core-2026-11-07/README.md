# 《鹰旗之下》战斗核心交接 · 2026-11-07

这是主要作者要求的暂停交接点，不是 Sword & Banner 完整复现完成声明。目标仍是：在现有 Godot 原生工程复现原作完整战斗系统，以原作可运行行为和录像对照验证，保留本项目美术与可编辑场景。

## 从这里开始

1. 拉取本仓库最新 `main`，用 **Godot 4.7.2 stable** 导入 [`godot-game/project.godot`](../../godot-game/project.godot)，等待资源导入后按 F5。
2. 主菜单 → **军团会战 · RTS** → 七兵种布阵 → 开战。当前默认是开放方形战场；山口守阵、攻城演练是其他入口。不要依据 11 月 5 日的旧 README 把默认入口当成山口。
3. 使用界面帮助查看现有操作。支持队伍/逐兵选择、普通移动、途经点、集火、C 冲锋、F 盾阵、H 保持、V 齐射、怨灵 B 闪现及暂停/半速。兵种能力不通用，先看所选兵种提示。
4. 阅读 [当前状态](STATE.md)，再按 [剩余任务](BACKLOG.md) 的顺序接手。详细文件入口在 [架构](ARCHITECTURE.md)，复测命令在 [验收](VALIDATION.md)。
5. 可直接下载 [本节点试玩包](../../builds/combat-core-2026-11-07/README.md)。按该目录的一条命令还原ZIP，以说明和 SHA256 为准；Windows 仅导出，不能当作 Windows 实机已通过。

## 本节点保住了什么

旧公开版 32 种战斗配置已映射到现有七类部署入口；逐兵寻敌、移动、攻击、冲锋、盾阵、投射物、特殊攻击、死亡与重试已接进原生流程。默认七兵种会战自然到胜利，另有失败分支检查。攻城目前只完成石墙五次命中、破口及通行。

**千人战不流畅：最近同机正常循环约 2.71 FPS。完整攻城、新版精灵/矮人/火炮、原生导航/随机细节与全面同条件对照仍未完成。不要对外称“完全一样”。**

## 文件导航

- [STATE.md](STATE.md)：已实现、验证边界、不可误读的旧证据。
- [BACKLOG.md](BACKLOG.md)：全部已知剩余任务、依赖、入口、验收与禁忌。
- [ARCHITECTURE.md](ARCHITECTURE.md)：代码、数据、坐标、帧顺序、编辑器入口。
- [VALIDATION.md](VALIDATION.md)：可执行复测、三类冲锋、性能与最终交付门槛。
- [REFERENCES.md](REFERENCES.md)：原作来源、版本、证据强弱与取证方法。
- [ASSETS_AND_COLLABORATION.md](ASSETS_AND_COLLABORATION.md)：源素材、导出与 Git 协作。
- [tasks.json](tasks.json)：与任务文档同编号的进度清单。
- [run_checks.py](run_checks.py)、[suites.json](suites.json)：50 套已维护回归入口。
- [check_export.gd](check_export.gd)：由 Godot 编辑器程序载入导出 PCK 的菜单—会战—胜负—重试—破墙检查；不等同于独立程序实机验收。
- [交接运行证据](../../output/combat-core-2026-11-07/checks/)；[性能证据](../../output/sword-banner-reference/large-battle-2/validation.json)。

不要把历史进度日志中的“下一步”直接当成当前待办；后续条目可能已经修正它。以本目录 STATE/BACKLOG、当前磁盘代码与新运行结果交叉核对。遇到尚无原作证据的规则，先记录未知，不能靠猜测调到测试变绿。

# 素材、导出与协作

## 素材与工具

- 运行资源在 `godot-game/assets/`，配置在 `godot-game/data/`。拉取后由Godot重建 `.godot/` 导入缓存，不需要任何生成API密钥。
- 自有Blender原模型、八方向渲染、武器锚点与尸体部件脚本在 `output/rts-armies/source/`；原盾兵源文件在 `output/shield-march/`。查看各脚本顶部的命令行参数，不要照抄历史 `/Users/ip` 或 `/private/tmp` 路径。
- `render_armies.py` 使用Blender后台Python，`pack_armies.py`等打包图集；Python图像依赖需单独安装。已有PNG和JSON足够运行游戏，重新渲染不是开箱运行前提。
- 自有新种族源模型/对应记录保留在相关art目录；已发布资源的来源和授权文档随工程保留。菜单原画不得修改构图。
- `output/formation-impact/六排Godot工程` 是独立历史试玩版，主工程仍单排。不要把六排目录覆盖到主工程。

## 本次同步范围

同步全部最新原生源码、场景、数值、运行素材、测试、必要生成脚本/源模型、开发文档与精选复现证据。旧网页档案保留原状，不部署新网页。

Godot缓存、玩家真实存档、私人配置/密钥、工具编译目录、重复历史工程备份、原始AVI巨文件与逐帧冗余素材不进源码历史；必要MP4、PNG、规则/验证日志随仓库。builds/combat-core-2026-11-07提供当前Mac与Windows分卷包与校验还原脚本。原始本机工作目录保留，不因清理上传范围删除本机文件。精确文件清单以同步清单为准。

## 导出

安装Godot4.7.2对应export templates。在仓库根目录执行：

```sh
Godot --headless --path godot-game --export-release 'macOS Playtest' /绝对输出路径/UnderTheEagle.app
Godot --headless --path godot-game --export-release 'Windows Playtest' /绝对输出路径/UnderTheEagle.exe
```

首次先完成资源导入。发布exe须附同目录pck；Mac须保留完整.app。Mac包仅本机签名，没有Apple公证；Windows包本轮只导出、不能声称Windows实际运行通过。新包必须用Godot编辑器加载导出PCK跑check_export.gd，并独立启动导出程序，检查JSON、全部图集与正常主菜单入口；只测试源码不算导出验证。

## Git约定

主要作者本人可直接提交main，无需PR；朋友从最新main建立任务分支，提交PR交主要作者审核。不强推或删除main，不擅自处理其他人的未合并PR。一次任务优先覆盖一个BACKLOG编号，PR必须写问题、最终行为、验证命令/结果、尚未验证的范围以及录像路径。

开发前先读根目录AGENTS.md及本目录，不借设计技能改成网页或重换画风。保留菜单/山口/HUD的编辑器可调性。任何性能优化须带相同兵力/镜头的前后数据和原精度战斗状态对照，不删兵或偷偷降低模拟频率。

## 完成交接后的状态

主要作者明确要求到核心节点后停下。当前完整复现目标应暂停，等待朋友或主要作者明确继续；交接完成不代表整个复现目标完成。

# 战斗核心试玩包

与本节点源码一起提交的Mac/Windows导出包。每个ZIP按80MiB分卷，以适应GitHub单文件限制；无需Git LFS。克隆整个仓库或下载仓库ZIP后，在仓库根目录执行：

```sh
python3 builds/combat-core-2026-11-07/reassemble.py
```

脚本校验每一卷及最终ZIP的SHA256，生成两份原始完整ZIP；随后正常解压即可。Mac包保留完整.app，Windows包包含.exe和同目录.pck。也可以直接使用Godot4.7.2打开 `godot-game/project.godot`，不需要还原试玩包。

Mac独立程序实际点通部署、开战、进攻、暂停、菜单；两平台导出PCK均通过78项资源/战斗检查。Windows exe尚未在Windows实机运行。Mac仅本机签名、未经Apple公证。完整复现未完成，千人战约2.71FPS，不建议用千人负载当作正常试玩。

接手文档：[交接目录](../../handoff/combat-core-2026-11-07/README.md)。

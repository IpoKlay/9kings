# 历史资料归档（2026-11-11）

当前开发入口是 [Godot 原生工程](../../godot-game/project.godot)。历史截图、日志、状态快照、旧代码副本和网页试玩档案已移出当前源码树；游戏素材、动画、音效、授权、测试代码和原始设计资料继续保留。

## 查找和恢复

- [完整文件清单](files-2026-11-11.csv)：原路径、大小、Git 内容校验值、SHA-256，以及归档或迁移后的去向。
- [清理前固定版本](https://github.com/IpoKlay/9kings/tree/81b5e7492ac5bdbec6b7b89fff64eab383624554)：此版本仍是 main 的祖先，没有重写历史。
- [历史截图、日志与验证记录](https://github.com/IpoKlay/9kings/tree/81b5e7492ac5bdbec6b7b89fff64eab383624554/output)。日期目录中的结果只代表当时的版本，不代表当前性能或功能验收。
- [旧网页版源码](https://github.com/IpoKlay/9kings/blob/81b5e7492ac5bdbec6b7b89fff64eab383624554/index.html)、[源码压缩包](https://github.com/IpoKlay/9kings/blob/81b5e7492ac5bdbec6b7b89fff64eab383624554/eagle-standard-demo-source.zip)、[旧预览](https://github.com/IpoKlay/9kings/blob/81b5e7492ac5bdbec6b7b89fff64eab383624554/preview.png)。不再作为开发或发布入口。

在 GitHub 打开所需文件后下载 Raw 内容即可。浅克隆中也可以按需恢复单个文件，不必切换整个工程：

```sh
git fetch origin 81b5e7492ac5bdbec6b7b89fff64eab383624554
git show 81b5e7492ac5bdbec6b7b89fff64eab383624554:output/editable-scenes/comparison-hud.png > /tmp/comparison-hud.png
```

本机另外保存了校验过的归档包 `output/repository-archive-2026-11-11/historical-files-before-cleanup.tar.gz`，包含 2,248 个清理前文件，包括迁移的源文件。归档包 SHA-256：`4be06b11835251ab0a8c6f7e8e05453259612ad54a2bac45ec18f86df8150d14`。此包未上传 Releases；其他协作者可使用上面的固定版本和清单恢复。

## 保留内容和生成约定

- 33 个 Blender 模型和 5 个美术生成脚本迁入 [art-source](../../art-source/README.md)，模型内容不变；城墙源模型仍位于 `art-source/blender/roman-fortifications.blend`。
- 素材盘点 [asset-inventory.csv](../art/roman_frontier_camp/asset-inventory.csv) 移到 Godot 工程之外，避免被当作翻译表；6 个误生成的翻译资源及其 CSV 导入配置随旧版本归档。
- 测试和美术工具仍可向本地 `output/` 写入新截图、渲染帧和日志。这些文件受忽略规则保护，不再提交整目录产物。
- 需要长期保留的验证摘要放在 `docs/`；可编辑模型、必要源图和生成脚本放在 `art-source/`；运行时资源放在 `godot-game/assets/`。
- 大型试玩包与录像应使用本地构建目录或 Releases，不进入源码历史。删除当前树中的历史产物不会自动缩小旧 Git 历史。

# 可编辑美术源文件

本目录保留生成游戏素材所需的源模型和脚本，不是运行时资源目录。实际游戏仍读取 `godot-game/assets/`，本轮没有重新生成或替换游戏中的图片与动画。

| 目录 | 内容 |
| --- | --- |
| `blender/` | 已接入的城墙、城门及拐角模型 |
| `shield-march/` | 原盾兵骨架与模型 |
| `rts-armies/source/` | 七个基础兵种模型及五个渲染、图集、尸体部件和武器锚点脚本 |
| `sword-banner-reference/*/art/` | 弓骑、人类、亡灵、哥布林、龙和怨灵模型 |

2026-11-11 从 `output/` 迁入的 33 个 `.blend` 文件逐一校验保持原内容，路径对照在[归档清单](../docs/archive/files-2026-11-11.csv)。历史制作记录见[固定版本归档](../docs/archive/README.md)。这些是本项目美术制作源文件，不代表还原了参考游戏的渲染实现。

各脚本顶部说明了参数。使用仓库根目录作为参数时，例如：

```sh
blender --background --python art-source/rts-armies/source/export_projectile_anchors.py -- "$PWD"
blender --background --python art-source/rts-armies/source/export_corpse_parts.py -- "$PWD"
python3 art-source/rts-armies/source/pack_corpse_parts.py
```

后两步按先导出部件、再打包的顺序执行；需要 Blender，打包另需 Pillow、NumPy。中间渲染结果继续放在忽略的 `output/`。导出/打包命令会改写对应游戏数据或图集，修改美术时按需执行；本次归档没有运行这些重生成命令。

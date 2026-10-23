# Under the Eagle · 鹰旗之下

## 最新开发版：Godot 原生工程

当前开发在 [`godot-game/`](godot-game/) 中进行。下载本仓库后，在 Godot 4.7.2 中导入 `godot-game/project.godot`，按 **F5** 运行；试玩不需要网络。

- 森林土地战场、统一阵型、24 张卡牌、逐年增强的敌军，以及中英双语设置。
- 三张补给牌轻微叠放；悬停放大 **40%** 并抬起，选中有抽离动画。
- 短纸牌音效统一响度：悬停固定同一段录音、移开无声、选中使用固定音效；快速切换不会叠声。
- 工程包含运行所需图像、音效、规则数据、素材授权说明和验证脚本。Godot 缓存与本地设置不入库。

[运行方式、控制和验证说明](godot-game/README.md)。最近验证：161 项规则检查、344 项卡牌音效检查、49 项卡牌交互/音频检查通过，游戏流程冒烟检查通过。

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

![Bilingual settings](preview.png)

## Source and private design documents

- [Source archive](eagle-standard-demo-source.zip) — current HTML/CSS/JS, assets, 49 checks, balance probe and packaging scripts.
- [Initial design](123.pdf)
- [Image prompt handbook](鹰旗之下-完整图像Prompt手册.pdf)
- Original roguelike.docx preserved. Audio credits are included in the archive.

The public play link requires no repository invitation. Source collaboration requires access to this private repository; GitHub App authorization is a separate permission.

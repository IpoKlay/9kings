# 鹰旗之下 · 远景战场 v0.9

斜俯视像素军团策略 Demo，带立体建筑与菱形营地。建设营地、选择补给、全军自动列阵，守过三轮进攻。

![试玩画面](preview.png)

## 试玩

[打开在线试玩](https://ipoklay.github.io/eagle-standard-demo/)

下载 `index.html` 后直接用浏览器打开，无需安装或联网。游戏资源和音效均已内嵌。

- 三张补给卡任选一张，也支持键盘 1 / 2 / 3。
- 建筑卡点击营地空格建造，或点击同类建筑升级。
- 军营建成后固定，步兵前阵、弓兵中阵、投石机后阵；点击“出征”共同作战。
- 战斗可暂停和加速；M 切换静音。

## 设计文档

- [初步方案：123.pdf](123.pdf)
- [完整图像 Prompt 手册](鹰旗之下-完整图像Prompt手册.pdf)
- 原有 `roguelike.docx` 保留在仓库中。

## 源码

[eagle-standard-demo-source.zip](eagle-standard-demo-source.zip) 包含拆分后的 HTML、CSS、JavaScript、音频、测试、打包脚本及设计文档。

解压后运行 `node --test tests/*.test.js`，共 25 项检查。开发说明见压缩包内 `DEVELOPMENT.md`；音频授权见 `dist/AUDIO-CREDITS.txt`。

地图扩大：外围疏林与开阔草原，部队纵向活动范围增加约 66%。

远景更新：镜头横纵范围各扩大 20%，可见背景面积增加 44%；树林进一步外移，UI 大小保持不变。

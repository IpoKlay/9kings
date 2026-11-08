# 地图编辑与 Godot AI

2026-11-07，本机 Godot 4.7.2，Godot AI 4.4.1。

## 打开地图

打开 `godot-game/project.godot`，再打开 `res://scenes/battlefields/square_battlefield.tscn`。这是保留的旧美术地图场景。最新正式主菜单「军团会战 · RTS」已切换到 `whiteboard_battlefield.tscn`；不要把编辑此旧场景当作修改当前白板。白板参数位于 `data/presentation/whiteboard_map.tres`。

| 场景节点 | 可以调整的内容 |
| --- | --- |
| Ground | 草地纹理裁片与地面颜色 |
| Roads | 道路、磨损地块的多边形顶点、位置与透明度 |
| GroundDetails | 小石片和地面细节 |
| Borders/RockBanks | 12 组岩石的位置和轮廓 |
| Camps/Enemy、Camps/Ally | 双方营地的原有建筑和旗帜 |
| Trees/Oak01–Oak42 | 树木位置、Canopy Size（树冠尺寸）、Wind Index（风动相位） |
| PlayableBoundary | 战场边缘的画线 |
| EditorGuides | 仅供编辑器参考的敌军、中立、我军三区；游戏中隐藏 |

树木和旗帜以脚点 Marker2D 为移动锚点；从左侧场景树选中后，拖动脚点或修改右侧 Transform → Position。树冠在编辑器内静止显示，进入游戏后沿用原来的逐条像素风动。营地建筑是 Sprite2D，道路和岩石是 Polygon2D，可直接使用 Godot 的原生编辑工具。

地图仍为 2100×2100 的战斗空间，以原来的 0.75 地面纵向投影显示。三等分部署区、军团尺寸、移动、个人战斗、寻敌、伤害和结算均保持原实现。地图装饰的位置不会自动生成碰撞；当前正方形战场仍是开放地面。若要增加可阻挡地形，需要把障碍接入现有通行规则。EditorGuides 是说明线，改变它不会改变实际部署边界。

山口和攻城继续使用已有的 `roman_pass.tscn`、`roman_siege.tscn`；这次没有重新制作它们。

## Godot AI 连接

- 来自 [dlight 的官方资产页](https://store.godotengine.org/asset/dlight/godot-ai/) 链接的 [官方 4.4.1 发行版](https://github.com/hi-godot/godot-ai/releases/tag/v4.4.1)。安装前验证了 RSA 签名、压缩包散列和 325 个文件的清单。
- 插件位于 `res://addons/godot_ai/`，已在工程中启用；uv/uvx 安装在本机 `~/.local/bin/`。
- 本机 Codex 配置已添加 `godot-ai`，使用固定版本和依赖时间界限的 stdio attach 命令，连接本机认证服务。原 Codex 配置已在用户配置目录备份。
- 当前编辑器连接与 Codex attach 命令关闭匿名统计。没有添加 API 密钥或外部模型服务。
- 右侧 Godot AI 应显示绿色 **Server connected**，Clients & Tools 内 Codex 为 **configured**。本次已经实际调用 MCP 读取场景、修改营地位置、保存、重新加载、截图，并在正式会战读取到修改后的营地坐标；随后恢复原位置。
- 当前对话的工具列表未热加载新的 Godot 工具，因此本次实测通过本机 MCP 客户端完成。重启 Codex 后，新会话可加载已写入的连接配置；不必重新安装插件。
- 插件会为编辑器运行加入 `_mcp_game_helper`，其官方导出插件在导出时移除此自动加载项。本轮没有重新导出独立试玩包。

## 验证与证据

证据目录：项目根目录 `output/editor-map/`。

- `test_editor_map.gd`：21 项通过，覆盖场景存盘重载、营地/树木/道路可编辑、正式入口、原地图边界、暂停与风动、总览和重试。
- `test_individual_full_battle.gd`：26 项通过；30/60/120 三档输入均在 37.9333 模拟秒获胜，17 名我方存活，逐兵最终状态一致。
- `test_deployment_mouse.gd`：中英文真实鼠标事件 16 项通过，覆盖七兵种部署、开始、重试、山口/攻城入口和地面输入。
- `setup/saved-editor-edit` 相关证据：通过 MCP 把南侧军医帐篷从 (760,1726) 移至 (800,1726)，保存后正式入口读到 (800,1726)，再经 MCP 恢复并保存为原位置。
- `before-*` / `after-*` 截图：默认视角最大通道差 3/255、平均 0.0716/255；总览平均 0.0929/255。少量高差像素位于顶部 UI，原始差分已保留。布局、尺寸和主战场纹理保持一致，未宣称逐像素完全相等。
- `编辑器地图实战.mp4`：45 秒、1280×720、60fps 的真实引擎录像，经过布阵、总览、接敌和胜利。录制器使用固定模拟步；不是实时时间性能基准。
- `test_square_overview.gd` 的旧「选择与 Shift 草稿」断言仍失败；换回迁移前地图后完全相同，分别保存在 `new-map-overview-failure.log` 和 `old-map-overview-failure.log`，未计为通过。短测试退出时仍有既有资源引用警告。

没有本轮首次真人试玩反馈。没有同步 GitHub，也没有重建已有独立试玩包；最新修改在当前 Godot 工程。

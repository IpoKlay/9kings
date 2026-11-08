# 投射物运动校正与验证

正式本机录像：[runtime.mp4](https://github.com/IpoKlay/9kings/blob/1f82ba2ad4b3ec802d9ba066dca6617a44e5d75a/output/sword-banner-reference/projectile-motion/runtime.mp4)。从菜单进入后，上方弓手射击移动骑兵；中部近处弓手先杀死15HP目标，远处在飞箭取消；下方骑兵离开固定石弹落点。测试使用正式移动接口，但不冒充手动鼠标操作或战略AI会战。

规则、输入与回归共1437项通过，详情[validation.json](validation.json)。35回归套件中的ground_combat首跑失败已保留并修正旧发射点/飞行时间假设，最后19项通过；并非未经检查把失败排除。既有部分UI退出资源引用警告仍存在。

四段本机影片完整解码、逐片帧数匹配。runtime为664帧；side/shield/pikes各601帧。三组冲锋结果保持前轮，没有将单排盾/矛称为成功拦停。

[原作录像](https://github.com/IpoKlay/9kings/blob/1f82ba2ad4b3ec802d9ba066dca6617a44e5d75a/output/sword-banner-reference/original-projectiles/tracking.mp4)仅提供移动目标受射的定性补证；随机起点、地图和镜头不等同本机。没有独立测量原作400箭速、同一模拟步生命周期或精确轨迹。完整系统一致性未通过。

当前可调/参考值：普通弓箭400、骷髅箭380；投石最短射程150，飞行distance/350限制.8–2.5秒，峰高distance*.25限制80–250。武器锚点来自本项目Blender源模型。

来源规则见[official-projectile-motion-rules.json](../official-projectile-motion-rules.json)。来源死亡的立即HP判断仍与原作延迟对象销毁存在边界差异；完整攻城、建筑、导航、原声与最终性能等继续开发。

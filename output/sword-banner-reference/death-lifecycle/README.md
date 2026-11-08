# 来源死亡与在飞投射物

[正常速度实机录像](https://github.com/IpoKlay/9kings/blob/1f82ba2ad4b3ec802d9ba066dca6617a44e5d75a/output/sword-banner-reference/death-lifecycle/runtime.mp4)：一名预伤至1HP的弓手先发箭，随后被近处敌弓手杀死；他的箭继续飞向远处盾兵并造成15点完整伤害。第50模拟帧死亡、第97帧命中；画面从菜单进入，固定默认缩放、无音效。集火通过正式接口由脚本下令，第四名友军用于维持战斗，不冒充自由会战。

依据为公开旧版脚本、[Godot4.6节点生命周期文档](https://docs.godotengine.org/en/4.6/classes/class_node.html#class-node-method-queue-free)及本机Godot4.7.2节点实验。原版完整游戏同条件死亡对照尚未执行。

[验证清单](validation.json)：1488项通过，37个既有回归套件。新检查覆盖仍登记/排队销毁/已销毁的盾牌与还击、石弹阵营、混合投射物生成顺序、新箭下步移动、暂停、半速和重试。既有UI退出资源引用警告仍在。

[引擎实验](engine-order.json)只证明本机引擎节点行为，不是原作UnitPhysics运行证据。新来源状态不等同完整死亡系统：致命伤后尚未释放的末次攻击、原生死亡移动/排斥、尸体时刻/散落与槽位复用还需继续。

四片完整解码；runtime424帧，side/shield/pikes各601帧。三组冲锋结果未变，单排盾/矛仍被越过，不称作成功拦停。详细规则与边界见[规则记录](../official-death-lifecycle-rules.json)。

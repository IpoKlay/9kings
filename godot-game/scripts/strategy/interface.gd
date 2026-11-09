extends Control
var trial
var mode=''
var build_kind=''
var info: Label
var message: Label
var panel: PanelContainer
var selection: Label
var previous_report=''

func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel=PanelContainer.new();panel.position=Vector2(1550,180);panel.size=Vector2(350,760)
	panel.add_theme_stylebox_override('panel',preload('res://scripts/rpg_ui.gd').box('paper'))
	add_child(panel)
	var scroll=ScrollContainer.new();scroll.custom_minimum_size=Vector2(350,760);panel.add_child(scroll)
	var box=VBoxContainer.new();box.custom_minimum_size=Vector2(325,0);scroll.add_child(box)
	info=Label.new();info.add_theme_color_override('font_color',Color('#382f25')); info.add_theme_font_size_override('font_size',21);box.add_child(info)
	selection=Label.new();selection.add_theme_color_override('font_color',Color('#382f25')); selection.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(selection)
	button(box,'开战 / 暂停',func():
		if trial.rules.phase=='deploy':trial.rules.start();trial.selected=''
		else:trial.paused=not trial.paused)
	button(box,'集结移动：右键地面',func():mode='move')
	button(box,'举盾 / 放下盾',func():trial.rules.shield(trial.selected_people()))
	button(box,'箭雨 → 点击目标',func():mode='rain';trial.selected='')
	button(box,'调整阵型朝向 → 点击方向',func():mode='face';trial.selected='')
	var forms=OptionButton.new()
	for id in trial.rules.strategy.formations:forms.add_item(trial.rules.strategy.formations[id].name);forms.set_item_metadata(forms.item_count-1,id)
	box.add_child(forms)
	button(box,'切换所选单位阵型',func():trial.rules.set_formation(trial.selected_people(),forms.get_item_metadata(forms.selected)))
	var buildings=OptionButton.new()
	for id in trial.rules.strategy.buildings:
		var b=trial.rules.strategy.buildings[id]
		buildings.add_item('%s · %d木材'%[b.name,b.wood]);buildings.set_item_metadata(buildings.item_count-1,id)
	box.add_child(buildings)
	button(box,'工程师建造 → 点击空地',func():build_kind=buildings.get_item_metadata(buildings.selected);mode='build';trial.selected='')
	var units=OptionButton.new()
	for id in trial.rules.strategy.units:
		var u=trial.rules.strategy.units[id]
		units.add_item('%s · %d食物'%[u.name,u.food]);units.set_item_metadata(units.item_count-1,id)
	box.add_child(units)
	button(box,'生产单位',func():trial.rules.train(units.get_item_metadata(units.selected)))
	button(box,'城镇：村民生产加速',func():trial.rules.research('towncraft'))
	button(box,'军营：晋升至下一级',func():trial.rules.research('promotion'))
	button(box,'房屋：经济研究',func():trial.rules.research('economy'))
	button(box,'军工厂：军事研究',func():trial.rules.research('military'))
	button(box,'学院：选择经济方向',func():trial.rules.research('direction_economy'))
	button(box,'学院：选择军事方向',func():trial.rules.research('direction_military'))
	message=Label.new();message.add_theme_color_override('font_color',Color('#382f25')); message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;message.add_theme_font_size_override('font_size',19);box.add_child(message)
	var help=Label.new();help.add_theme_color_override('font_color',Color('#382f25')); help.text='单击选1人；Shift加选；拖动框选\n右键资源：村民采集\n右键建筑：修复 / 开关门 / 攻城\n右键攻城器：修复；步兵右键塔装载\nC冲锋，H坚守，Tab总览\n守住城镇，击败三波增援并摧毁敌堡获胜\n城镇每20秒花35食物生产村民\nEsc取消待放置操作'
	help.add_theme_font_size_override('font_size',18);box.add_child(help)
func button(parent: Node,text: String,callback: Callable):
	var b=Button.new();b.text=text;b.custom_minimum_size.y=33;b.add_theme_font_size_override('font_size',19);b.pressed.connect(callback);parent.add_child(b)
func _process(_dt: float):
	var r=trial.rules
	if not r.has_method('strategy_paths'):hide();return
	info.text='食物 %d   木材 %d   铁矿 %d\n人口 %d/%d   等级 %d/5\n增援 %d/3 · 下一波 %d秒'%[r.stock.food,r.stock.wood,r.stock.iron,r.population(),r.population_cap(),r.level,r.waves_sent,maxf(0,r.next_wave-r.elapsed)]
	var people=r.Soldiers.members(r,trial.selected_people())
	selection.text='已选 %d 人'%people.size()
	if not people.is_empty():
		var u=people[0].unit;var a=people[0].actor
		selection.text+=' · '+r.strategy.units[u.unit_type].name+'\n'+r.strategy.formations[a.get('formation','default')].name
		selection.text+=' · 构建 %.1f秒'%a.form_left if a.has('form_left') else ' · 生效' if a.get('formation_ready',false) else ' · 无阵型增益'
	if not r.research_queue.is_empty():selection.text+='\n研究剩余 %.1f秒'%r.research_queue.remaining
	if r.report!=previous_report:message.text=r.report;previous_report=r.report
	queue_redraw()
func _input(event):
	if not trial.rules.has_method('strategy_paths'):return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:mode='';return
	if not event is InputEventMouseButton or not event.pressed:return
	var screen=get_global_transform_with_canvas().affine_inverse()*event.position
	if panel.get_global_rect().has_point(screen):return
	var point=trial.field.unproject(trial.field_point(screen))
	var r=trial.rules
	if event.button_index==MOUSE_BUTTON_LEFT and mode in ['build','rain','face']:
		if mode=='build':r.build(build_kind,point,trial.selected_people())
		elif mode=='rain':r.arrow_rain(trial.selected_people(),point)
		else:
			var people=r.Soldiers.members(r,trial.selected_people())
			if not people.is_empty():r.set_formation(trial.selected_people(),people[0].actor.get('formation','default'),people[0].unit.pos.direction_to(point))
		mode='';get_viewport().set_input_as_handled()
	elif event.button_index==MOUSE_BUTTON_RIGHT and r.phase=='battle':
		if r.interact(trial.selected_people(),point):get_viewport().set_input_as_handled()
		elif trial.soldier_at(screen,'enemy').is_empty():
			if not r.Soldiers.command(r,trial.selected_people(),'move',point):r.report='无法到达此处；原命令保留'
			trial.selected='';get_viewport().set_input_as_handled()
func _draw():
	if not trial.rules.has_method('strategy_paths'):return
	var r=trial.rules
	# UI-space markers are scaled with the same camera as existing pixel sprites.
	for u in r.alive('ally'):
		if u.unit_type not in ['villager','engineer']:continue
		var p=(trial.field.project(u.pos)-trial.camera_offset)*trial.zoom
		draw_string(get_theme_default_font(),p+Vector2(-12,-45)*trial.zoom,'采' if u.unit_type=='villager' else '工',HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color('#eedca4'))

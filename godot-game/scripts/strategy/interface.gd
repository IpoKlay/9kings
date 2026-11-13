extends Control
## Selection owns the command surface; no global build/train menu or deployment phase.
const Paper=preload('res://scripts/rpg_ui.gd')
const INK=Color('#382f25')
const StaticArt=preload('res://scripts/strategy/static_art.gd')
var static_art=StaticArt.new()
var trial
var mode=''
var build_kind=''
var selected_building=-1
var panel: PanelContainer
var box: VBoxContainer
var info: Label
var title: Label
var detail: Label
var health_label: Label
var health_bar: ProgressBar
var construction_bar: ProgressBar
var message: Label
var queue_note: Label
var pause_button: Button
var result_panel: PanelContainer
var result_label: Label
var actions={}
var signature=''
var rules_instance
var dragging=false
var drag_from=Vector2.ZERO
var drag_to=Vector2.ZERO
var additive=false
var ctrl_select=false
var mouse_world=Vector2.ZERO
var report_age=0.
var last_report=''
var camera_pan=preload('res://scripts/strategy/camera_pan.gd').new()
var formation_panel: PanelContainer
var formation_label: Label
var formation_bar: ProgressBar
var formation_members=[]
var formation_name=''
var formation_revision=0
var formation_notice_left=0.
var fog_texture: ImageTexture


func label(text: String,size: int=22) -> Label:
	var l=Label.new();l.text=text;l.add_theme_color_override('font_color',INK);l.add_theme_font_size_override('font_size',size)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return l
func button(parent: Node,text: String,callback: Callable) -> Button:
	var b=Button.new();b.focus_mode=Control.FOCUS_NONE;b.text=text;b.custom_minimum_size=Vector2(100,42);b.add_theme_font_size_override('font_size',20)
	b.pressed.connect(callback);parent.add_child(b)
	return b
func meter(tint: Color) -> ProgressBar:
	var bar=ProgressBar.new();bar.custom_minimum_size=Vector2(120,16);bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER;bar.show_percentage=false;bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var background=StyleBoxFlat.new();background.bg_color=Color('#4b493b');background.set_border_width_all(2);background.border_color=Color('#756444')
	var fill=StyleBoxFlat.new();fill.bg_color=tint
	bar.add_theme_stylebox_override('background',background);bar.add_theme_stylebox_override('fill',fill)
	return bar
func surface(at: Vector2,dimensions: Vector2) -> PanelContainer:
	var p=PanelContainer.new();p.position=at;p.custom_minimum_size=dimensions;p.add_theme_stylebox_override('panel',Paper.box('paper'));add_child(p)
	return p
func _ready():
	make_fog_texture()
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rules_instance=trial.rules
	var top=surface(Vector2(22,18),Vector2(1430,64))
	info=label('',25);top.add_child(info)
	var controls=HBoxContainer.new();controls.position=Vector2(1485,20);controls.add_theme_constant_override('separation',12);add_child(controls)
	pause_button=button(controls,'暂停',func():trial.paused=not trial.paused)
	button(controls,'总览',trial.toggle_overview)
	button(controls,'菜单',trial.closed.emit)
	formation_panel=surface(Vector2(660,92),Vector2(600,72))
	formation_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var formation_box=VBoxContainer.new();formation_box.mouse_filter=Control.MOUSE_FILTER_IGNORE;formation_panel.add_child(formation_box)
	formation_label=label('',24);formation_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;formation_box.add_child(formation_label)
	formation_bar=ProgressBar.new();formation_bar.custom_minimum_size=Vector2(580,14);formation_bar.show_percentage=false;formation_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;formation_box.add_child(formation_bar)
	formation_panel.hide()
	panel=surface(Vector2(1500,125),Vector2(398,0))
	var margin=MarginContainer.new()
	for edge in ['left','right','top','bottom']:margin.add_theme_constant_override('margin_'+edge,14)
	panel.add_child(margin)
	var scroll=ScrollContainer.new();scroll.custom_minimum_size=Vector2(370,0);scroll.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	box=VBoxContainer.new();box.custom_minimum_size.x=360;box.add_theme_constant_override('separation',12);scroll.add_child(box)
	# A capped scroll viewport allows the 13-building grid at 1280x720 and smaller windows.
	scroll.custom_minimum_size.y=790
	message=label('',23);message.position=Vector2(30,1000);message.size=Vector2(1420,60);message.add_theme_color_override('font_color',Color('#ffefbc'));add_child(message)
	result_panel=surface(Vector2(680,350),Vector2(560,230))
	var end=VBoxContainer.new();result_panel.add_child(end)
	result_label=label('',34);end.add_child(result_label)
	if not trial.has_meta('cassius_journey'):
		button(end,'重新开始',func():clear_selection();trial.retry())
	button(end,'返回远征' if trial.has_meta('cassius_journey') else '返回主菜单',trial.closed.emit)
	result_panel.hide();panel.hide()
	trial.selected=''
	trial.set_meta('strategy_interface',self)

func clear_selection():
	mode='';build_kind='';selected_building=-1;dragging=false
	trial.soldier_ids.clear();trial.squad_ids.clear();trial.draft_waypoints.clear()
	trial.selected='';trial.gesture=false;trial.drag_select=false;trial.drawing_wall=false;trial.placing_rank=false;trial.notice_seconds=0
	signature='';panel.hide();message.text='';trial.rules.report='';last_report='';report_age=0.
	trial.field.queue_redraw();queue_redraw()
func selected_people() -> Array:return trial.rules.Soldiers.members(trial.rules,trial.selected_people())
func selected_structure() -> Dictionary:
	if selected_building<0 or selected_building>=trial.rules.buildings.size():return {}
	var b: Dictionary=trial.rules.buildings[selected_building]
	return b if b.hp>0 and b.side=='ally' else {}
func show_commands():
	var r=trial.rules
	var b=selected_structure()
	var people=selected_people()
	var key=str(selected_building)+'|'+str(trial.selected_people())+'|'+str(r.level)+'|'+str(r.town_level)+'|'+str(r.researches)
	if not b.is_empty():key+='|'+str(b.remaining<=0)+'|'+str(b.queue.map(func(q):return q.type))
	if key==signature:return
	signature=key;actions.clear();queue_note=null;construction_bar=null
	for child in box.get_children():box.remove_child(child);child.queue_free()
	if b.is_empty() and people.is_empty():panel.hide();return
	panel.show()
	title=label('');box.add_child(title)
	var health_row=HBoxContainer.new();health_row.add_theme_constant_override('separation',12);box.add_child(health_row)
	health_label=label('',20);health_row.add_child(health_label)
	health_bar=meter(Color('#65884f'));health_row.add_child(health_bar)
	detail=label('',20);detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(detail)
	if not b.is_empty():
		title.text=r.strategy.buildings[b.kind].name
		if b.remaining>0:
			box.add_child(label('建造进度',20));construction_bar=meter(Color('#c69543'));box.add_child(construction_bar);return
		var grid=GridContainer.new();grid.columns=3;grid.add_theme_constant_override('h_separation',7);grid.add_theme_constant_override('v_separation',7);box.add_child(grid)
		for type in r.strategy.units:
			var data: Dictionary=r.strategy.units[type]
			if data.producer!=b.kind:continue
			icon_button(grid,'train:'+type,data.name+'\n%d/%d/%d'%[data.food,data.get('wood',0),data.get('iron',0)],unit_icon(type,data.art),func():r.train(type,selected_building))
		if not b.queue.is_empty():
			queue_note=label('',20);box.add_child(queue_note)
			for i in b.queue.size():
				button(box,'取消 '+str(i+1)+' · '+r.strategy.units[b.queue[i].type].name,func():r.cancel_training(selected_building,i);signature='')
		var research_ids={'town':['town_upgrade'],'barracks':['promotion'],'house':['economy'],'factory':['military'],'academy':['direction_economy','direction_military']}.get(b.kind,[])
		for id in research_ids:
			var names={'town_upgrade':'城镇升级至 '+str(r.town_level+1)+' 级','towncraft':'农民生产加速','promotion':'晋升至 '+str(r.level+1)+' 级','economy':'经济研究','military':'军事研究','direction_economy':'选择经济方向','direction_military':'选择军事方向'}
			var cost=r.town_cost() if id=='town_upgrade' else r.promotion_cost() if id=='promotion' else {'food':60,'wood':40,'iron':40}
			var btn=button(box,names[id]+'\n%d 食物 · %d 木材 · %d 铁矿'%[cost.food,cost.wood,cost.iron],func():r.research(id,selected_building))
			btn.tooltip_text=r.town_upgrade_description() if id=='town_upgrade' else '在这座建筑研究，完成后提升全军或经济能力'
			actions['research:'+id]=btn
		if b.kind=='gate':button(box,'打开 / 关闭城门',func():r.interact([],b.pos))
	else:
		title.text=r.strategy.units[people[0].unit.unit_type].name+' × '+str(people.size())
		if people.any(func(row):return row.unit.unit_type=='villager'):
			var grid=GridContainer.new();grid.columns=3;grid.add_theme_constant_override('h_separation',7);grid.add_theme_constant_override('v_separation',7);box.add_child(grid)
			for kind in r.strategy.buildings:
				var data: Dictionary=r.strategy.buildings[kind]
				icon_button(grid,'build:'+kind,data.name+'\n%.1f 木材'%r.building_cost(kind),static_art.icon(static_art.building_id(kind,r.town_level)),func():mode='build';build_kind=kind;r.report='放置'+data.name+'：左键确认，右键取消，Esc清空选择')
		else:
			button(box,'坚守 H',func():trial.command_selection('hold',Vector2.ZERO))
			button(box,'攻击移动 X',func():mode='attack_move')
			if people.any(func(row):return r.Charges.ready(r,row.unit,row.actor)):button(box,'冲锋 C',func():mode='charge')
			if people.any(func(row):return row.unit.unit_type=='shield'):button(box,'举盾 / 放下盾',func():r.shield(trial.selected_people()))
			if people.any(func(row):return row.unit.unit_type=='archer'):button(box,'箭雨 V',func():mode='rain')
			var forms=OptionButton.new()
			for form in r.strategy.formations:
				if people.all(func(row):return form in r.permitted(row.unit.unit_type)):
					forms.add_item(r.strategy.formations[form].name);forms.set_item_metadata(forms.item_count-1,form)
			box.add_child(forms)
			button(box,'切换阵型',func():request_formation(forms.get_item_metadata(forms.selected)))
			button(box,'调整朝向',func():mode='face')
	var help=label('右键下令 · Esc 清空选择',18);box.add_child(help)
func unit_icon(type: String,art: String) -> Texture2D:
	var id=StaticArt.unit_id(type,trial.rules.level)
	if id!='':return static_art.icon(id)
	var icon=AtlasTexture.new();icon.atlas=load('res://assets/rts-armies/'+art+'_ally.png');icon.region=Rect2(0,0,64,64);return icon
func icon_button(parent: Node,id: String,text: String,texture: Texture2D,callback: Callable):
	var b=Button.new();b.focus_mode=Control.FOCUS_NONE;b.custom_minimum_size=Vector2(112,118);b.tooltip_text=text.replace('\n',' · ');b.pressed.connect(callback);parent.add_child(b)
	var content=VBoxContainer.new();content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.offset_top=5;content.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(content)
	var icon=TextureRect.new();icon.texture=texture;icon.custom_minimum_size=Vector2(48,48);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;content.add_child(icon)
	var name_label=label(text,17);name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;name_label.add_theme_color_override('font_color',Color('#fff0c5'));content.add_child(name_label)
	actions[id]=b
func _process(dt: float):
	var r=trial.rules
	if rules_instance!=r:
		rules_instance=r;clear_selection();formation_members.clear();formation_panel.hide();camera_pan.stop()
	pan_camera(dt)
	update_formation_notice(dt)
	info.text='  食物 %d    木材 %d    铁矿 %d       人口 %d / %d       科技 %d / 5       %02d:%02d'%[r.stock.food,r.stock.wood,r.stock.iron,r.population(),r.population_cap(),r.level,int(r.elapsed)/60,int(r.elapsed)%60]
	pause_button.text='继续' if trial.paused else '暂停'
	result_panel.visible=r.phase in ['victory','defeat']
	if result_panel.visible:
		panel.hide();result_label.text='胜利 · 敌方城镇中心已摧毁' if r.phase=='victory' else '战败 · 城镇中心已失守';return
	if selected_building>=0 and selected_structure().is_empty():clear_selection()
	show_commands()
	var b=selected_structure()
	if panel.visible:
		if not b.is_empty():
			update_health(b.hp,b.max_hp);detail.text=''
			if b.kind=='town':detail.text='城镇 %d 级'%r.town_level
			if r.strategy.units.values().any(func(d):return d.producer==b.kind):detail.text+='\n右键地图设置集结点 · 费用：食/木/铁'
			if b.remaining>0:
				detail.text+='\n村民施工中'
				if construction_bar!=null:construction_bar.value=100.*(1.-b.remaining/r.strategy.buildings[b.kind].seconds)
			elif not b.queue.is_empty():
				detail.text+='\n生产 %s · %.1f秒'%[r.strategy.units[b.queue[0].type].name,maxf(0,b.queue[0].remaining)]
				if r.population()>=r.population_cap():detail.text+='\n人口已满：请建造房屋'
			if queue_note!=null:queue_note.text='生产队列 %d / 5'%b.queue.size()
			if r.research_queue.get('building_id',-1)==b.id:detail.text+='\n研究剩余 %.1f秒'%r.research_queue.remaining
		else:
			var people=selected_people()
			if not people.is_empty():
				var a: Dictionary=people[0].actor
				update_health(a.hp,a.max_hp);detail.text=''
				if people.size()==1:
					var n=r.unit_numbers(people[0].unit)
					detail.text+='\n伤害 %.1f · 近甲 %d / 远甲 %d\n攻击间隔 %.2f 秒\n指令：%s'%[n.damage,n.melee,n.ranged,n.interval,r.current_order(people[0].unit).name]
					var bonus: float=r.strategy.units[people[0].unit.unit_type].get('bonus_damage',0)
					if bonus>0:detail.text+='\n对%s额外伤害 +%d'%['骑兵' if people[0].unit.unit_type=='spear' else '弓箭手',bonus]
				if people[0].unit.unit_type=='villager':detail.text+='\n右键资源采集；点击下方图标建造'
				else:detail.text+='\n'+r.strategy.formations[a.get('formation','default')].name
		detail.text=detail.text.strip_edges()
		for id in actions:
			if id.begins_with('research:'):
				var tech: String=id.trim_prefix('research:')
				actions[id].disabled=not r.research_queue.is_empty() or r.researches.has(tech) or tech=='town_upgrade' and r.town_level>=5 or tech=='promotion' and r.level>=5 or tech.begins_with('direction_') and r.direction!=''
	if r.report!=last_report:last_report=r.report;report_age=5.;message.text=r.report
	report_age=maxf(0,report_age-dt)
	if report_age<=0:message.text=''
	queue_redraw()
func update_health(hp: float,maximum: float):
	health_label.text='生命 %d / %d'%[hp,maximum]
	health_bar.max_value=maxf(1.,maximum);health_bar.value=hp
func to_world(screen: Vector2) -> Vector2:return trial.field.unproject(trial.field_point(screen))
func select_at(screen: Vector2):
	var r=trial.rules
	var hit=trial.soldier_at(screen,'ally')
	var target=r.entity_at(to_world(screen))
	if not hit.is_empty():
		selected_building=-1
		if not additive:trial.soldier_ids.clear();trial.squad_ids.clear()
		for u in r.alive('ally'):
			if u.id==hit.unit.id or ctrl_select and u.unit_type==hit.unit.unit_type:
				var id=Vector2i(u.id,0)
				if id not in trial.soldier_ids:trial.soldier_ids.append(id)
	elif target.get('kind','')=='building' and r.buildings[target.id].side=='ally':
		clear_selection();selected_building=target.id
	else:clear_selection()
	trial.selected='';signature='';show_commands();trial.field.queue_redraw()
func map_click(screen: Vector2):
	var r=trial.rules
	var point=to_world(screen)
	if mode=='build':
		if r.build(build_kind,point,trial.selected_people()):mode=''
	elif mode=='rain':r.arrow_rain(trial.selected_people(),point);mode=''
	elif mode=='charge':r.Charges.issue(r,trial.selected_people(),point);mode=''
	elif mode=='attack_move':trial.command_selection('attack_move',point);mode=''
	elif mode=='face':
		var people=selected_people()
		if not people.is_empty():request_formation(people[0].actor.formation,people[0].unit.pos.direction_to(point))
		mode=''
	else:select_at(screen)
func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode==KEY_ESCAPE or event.physical_keycode==KEY_ESCAPE):
		clear_selection();get_viewport().set_input_as_handled();return
	if dragging and event is InputEventMouseMotion:
		drag_to=get_global_transform_with_canvas().affine_inverse()*event.position
		trial.drag_select=drag_from.distance_to(drag_to)>7;trial.drag_origin=drag_from;trial.drag_end=drag_to;trial.field.queue_redraw()
	if dragging and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		dragging=false
		var screen=get_global_transform_with_canvas().affine_inverse()*event.position
		if drag_from.distance_to(screen)>7 and mode=='':
			selected_building=-1;trial.drag_origin=drag_from;trial.drag_select=true;trial.type_gesture=false;trial.regiment_gesture=false
			trial.select_squads(screen,additive);trial.selected=''
		else:map_click(screen)
		trial.drag_select=false;trial.field.queue_redraw();get_viewport().set_input_as_handled()
func _unhandled_input(event):
	if trial.rules.phase!='battle':return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode if event.physical_keycode else event.keycode:
			KEY_SPACE:trial.paused=not trial.paused
			KEY_TAB:trial.toggle_overview()
			KEY_H:trial.command_selection('hold',Vector2.ZERO)
			KEY_A:trial.command_selection('auto',Vector2.ZERO)
			KEY_C:mode='charge' if not selected_people().is_empty() else ''
			KEY_V:mode='rain' if not selected_people().is_empty() else ''
			KEY_X:mode='attack_move' if not selected_people().is_empty() else ''
	if event is InputEventMouseMotion:
		var screen=get_global_transform_with_canvas().affine_inverse()*event.position
		mouse_world=to_world(screen)
		if event.button_mask&MOUSE_BUTTON_MASK_MIDDLE:trial.set_camera(trial.camera_offset-event.relative/trial.zoom)
	if not event is InputEventMouseButton or not event.pressed:return
	var screen=get_global_transform_with_canvas().affine_inverse()*event.position
	var point=to_world(screen);mouse_world=point
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var anchor=trial.field_point(screen)
		trial.zoom=clampf(trial.zoom+(.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.2),trial.overview_zoom(),5./3.)
		trial.set_camera(anchor-screen/trial.zoom)
	elif event.button_index==MOUSE_BUTTON_LEFT:
		dragging=true;drag_from=screen;drag_to=screen;additive=event.shift_pressed;ctrl_select=event.ctrl_pressed
	elif event.button_index==MOUSE_BUTTON_RIGHT:
		if mode!='':mode='';return
		var building=selected_structure()
		if not building.is_empty():
			trial.rules.set_rally(building,point);queue_redraw();get_viewport().set_input_as_handled();return
		if trial.selected_people().is_empty():return
		if trial.rules.interact(trial.selected_people(),point):return
		var enemy=trial.soldier_at(screen,'enemy')
		if not enemy.is_empty():trial.command_selection('attack',point,enemy.unit.id,enemy.slot)
		elif not trial.command_selection('move',point):trial.rules.report='无法到达，原命令继续'
	get_viewport().set_input_as_handled()
func _draw():
	draw_fog()
	draw_orders()
	if selected_building>=0 and not selected_structure().is_empty():
		var b=selected_structure();var size: float=trial.rules.strategy.buildings[b.kind].size
		var p=(trial.field.project(b.pos)-trial.camera_offset)*trial.zoom
		draw_rect(Rect2(p-Vector2.ONE*size*trial.zoom*.6,Vector2.ONE*size*trial.zoom*1.2),Color('#ffe1a1'),false,3)
	if mode=='build':
		var size: float=trial.rules.strategy.buildings[build_kind].size
		var p=(trial.field.project(mouse_world)-trial.camera_offset)*trial.zoom
		if build_kind in ['wall','gate']:
			var fort=trial.field.pass_layout.fortifications
			var key=fort.frame_key({'kind':build_kind,'open':false})
			var frame: Dictionary=fort.manifest.frames[key]
			var anchor=Vector2(frame.anchor[0],frame.anchor[1])
			draw_texture_rect(fort.texture(key),Rect2(p-anchor*trial.zoom,fort.texture(key).get_size()*trial.zoom),false,Color(1,1,1,.5))
		else:
			var id=static_art.building_id(build_kind,trial.rules.town_level)
			draw_texture_rect(static_art.texture(id),static_art.sprite_rect(id,p,size*1.6*trial.zoom),false,Color(1,1,1,.5))
		draw_rect(Rect2(p-Vector2.ONE*size*trial.zoom*.5,Vector2.ONE*size*trial.zoom),Color('#e9e1a866'))
		draw_string(get_theme_default_font(),p+Vector2(15,-15),trial.rules.strategy.buildings[build_kind].name,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color('#fff1c7'))

func pan_camera(dt: float):
	if trial.rules.phase!='battle' or not is_visible_in_tree() or not get_window().has_focus() or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		camera_pan.stop();return
	var point=get_local_mouse_position()
	var direction=Vector2(Input.get_axis('ui_left','ui_right'),Input.get_axis('ui_up','ui_down'))
	if direction==Vector2.ZERO:
		var over_panel=panel.visible and panel.get_rect().has_point(point)
		if not over_panel:direction=camera_pan.edge_direction(point,size)
	var movement=camera_pan.advance(direction,dt)/trial.zoom
	trial.set_camera(trial.camera_offset+movement)

func request_formation(form: String,heading: Vector2=Vector2.ZERO):
	if not trial.rules.set_formation(trial.selected_people(),form,heading):return
	formation_revision=trial.rules.formation_revision
	formation_members=selected_people().map(func(row):return row.actor)
	formation_name=trial.rules.strategy.formations[form].name
	formation_notice_left=0.
	update_formation_notice(0.)

func update_formation_notice(dt: float):
	if formation_members.is_empty():
		formation_notice_left=maxf(0.,formation_notice_left-dt)
		if formation_notice_left==0.:formation_panel.hide()
		return
	var left=0.;var pending=0;var interrupted=0
	for actor in formation_members:
		if actor.hp<=0 or actor.get('formation_revision',-1)!=formation_revision:
			interrupted+=1
		elif actor.has('form_left'):
			left=maxf(left,actor.form_left);pending+=1
		elif not actor.get('formation_ready',false):interrupted+=1
	formation_panel.show();formation_bar.show()
	formation_bar.value=(1.-left/5.)*100.
	formation_label.text='切换至%s · %.1f / 5秒'%[formation_name,5.-left]
	if trial.paused:formation_label.text+='（暂停）'
	elif left<=0 and pending>0:formation_label.text+=' · 正在就位'
	if pending==0:
		formation_label.text=('阵型切换已中断' if interrupted>0 else '已切换至'+formation_name)
		formation_bar.visible=interrupted==0
		formation_members.clear();formation_notice_left=2.

func screen_point(point: Vector2) -> Vector2:return (trial.field.project(point)-trial.camera_offset)*trial.zoom
func make_fog_texture():
	# Cached, world-anchored pixel clouds: no per-frame noise work or hidden terrain leaks.
	var noise=FastNoiseLite.new();noise.seed=20261110;noise.frequency=.07;noise.fractal_octaves=3
	var cloud=Image.create(256,256,false,Image.FORMAT_RGBA8)
	for x in 256:
		for y in 256:
			var shade=(noise.get_noise_2d(x,y)+1.)*.5
			cloud.set_pixel(x,y,Color(.14+shade*.12,.16+shade*.12,.18+shade*.12,1.))
	fog_texture=ImageTexture.create_from_image(cloud)
func draw_fog():
	if trial==null:return
	var world=trial.rules.world
	var low=world.cell(to_world(Vector2.ZERO));var high=world.cell(to_world(size))
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			var key=Vector2i(x,y)
			if world.sight.has(key):continue
			# Adjacent cells share exact screen-pixel edges; alpha must not overlap into dark grid seams.
			var at=screen_point(Vector2(key)*world.CELL).floor()
			var end=screen_point((Vector2(key)+Vector2.ONE)*world.CELL).floor()
			var region=Rect2(Vector2(posmod(x,64),posmod(y,64))*4.,Vector2(4,4))
			draw_texture_rect_region(fog_texture,Rect2(at,end-at),region,Color(1,1,1,.68 if world.explored.has(key) else 1.),false,false)
	var city=screen_point(world.enemy_city)
	if not world.visible(world.enemy_city):
		draw_rect(Rect2(city-Vector2(8,8),Vector2(16,16)),Color('#c86050'),false,2)
		draw_string(get_theme_default_font(),city+Vector2(15,5),'敌方城邦（位置已知）',HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color('#e5ba98'))
func order_representatives() -> Array:
	var groups={}
	for row in selected_people():
		var team: int=row.actor.get('team',-1)
		var key=str(team) if team>=0 else 'unit'+str(row.unit.id)
		# A member with a new job or command is no longer part of the old order group.
		var order=trial.rules.current_order(row.unit)
		key+=':'+order.name
		if not groups.has(key):groups[key]=[]
		groups[key].append(row)
	var result=[]
	for group in groups.values():
		var center=Vector2.ZERO
		for row in group:center+=row.unit.pos
		center/=group.size()
		var representative=group[0]
		for row in group:
			if row.unit.pos.distance_squared_to(center)<representative.unit.pos.distance_squared_to(center):representative=row
		result.append(representative)
	return result
func draw_flag(origin: Vector2,goal: Vector2,tint: Color):
	var start=screen_point(origin);var end=screen_point(goal)
	draw_dashed_line(start,end,tint,2.,10.)
	draw_line(end,end-Vector2(0,30),Color('#f0dfad'),3.)
	draw_colored_polygon(PackedVector2Array([end-Vector2(0,30),end+Vector2(22,-25),end+Vector2(0,-17)]),tint)
	draw_arc(end,6,0,TAU,12,tint,2.)
func draw_orders():
	var b=selected_structure()
	if not b.is_empty() and b.has('rally'):draw_flag(b.pos,b.rally,Color('#e6c468'))
	for row in order_representatives():
		var order=trial.rules.current_order(row.unit)
		var tint=Color('#ec6155') if order.attack else Color('#6fe68c')
		if row.unit.pos.distance_to(order.point)>8.:draw_flag(row.unit.pos,order.point,tint)
		draw_string(get_theme_default_font(),screen_point(row.unit.pos)+Vector2(15,-55),order.name,HORIZONTAL_ALIGNMENT_LEFT,-1,18,tint)

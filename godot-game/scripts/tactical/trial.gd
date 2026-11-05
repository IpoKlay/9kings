extends Control
signal closed
const Paper=preload('res://scripts/rpg_ui.gd')
const INK=Color('#382f25')
const PassBattle=preload('res://scripts/tactical/pass_battle.gd')
var defender_button: Button
var assault_button: Button
var flag_alert: Label
var strength_bar: ColorRect
var ally_bar: ColorRect
var pace_button: Button
var slow=false
var oil_index=-1
var roster: Array=[]
const Field=preload('res://scripts/tactical/trial_field.gd')
var rules=PassBattle.new()
var app
var field
var pointer=Vector2(-1000,-1000)
var squad_ids: Array=[]
var camera_offset=Vector2.ZERO
var zoom=1.0
var drag_select=false
var drag_origin=Vector2.ZERO
var drag_end=Vector2.ZERO
var gesture=false
var placing_rank=false
var rank_dragged=false
var rank_start=Vector2.ZERO
var rank_end=Vector2.ZERO
var rank_screen_start=Vector2.ZERO
var setup_button: Button
var combined_button: Button
var box_gesture=false
var dragged=false
var camera_at_press=Vector2.ZERO
var controls: Label
var draft_waypoints: Array[Vector2]=[]
var selected='legion':
	set(value):
		draft_waypoints.clear()
		selected=value
var paused=false
var status: Label
var hint: Label
var buttons={}
var character_picker: OptionButton
var character_ids: Array[String]=[]
var power_note: Label
var portrait_id=''
var portrait: TextureRect
var start_button: Button
var result: Label
var accumulator=0.0
var notice=''
var notice_seconds=0.0
var myth_audio=preload('res://scripts/tactical/myth_audio.gd').new()
func words(zh: String,en: String) -> String:
	return zh if app==null or app.language=='zh' else en
func skill_text(zh: String, en: String) -> String:
	var values=rules.power_config().duplicate()
	values.reduction_percent=roundi(float(values.get('reduction',0))*100)
	values.bonus_percent=roundi((float(values.get('archer_bonus',1))-1)*100)
	values.slow_percent=roundi((1-float(values.get('slow',1)))*100)
	return words(zh,en).format(values)
func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	theme=preload('res://assets/fonts/game_pixel_theme.tres')
	var viewport=SubViewport.new()
	viewport.size=Vector2i(960,540)
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	field=Field.new()
	field.trial=self
	field.scale=Vector2(.5,.5)
	viewport.add_child(field)
	var screen=TextureRect.new()
	screen.texture=viewport.get_texture()
	screen.size=Vector2(1920,1080)
	screen.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	status=label('',Vector2(18,12),Vector2(352,52),22)
	status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_stylebox_override('normal',Paper.box('toolbar'))
	status.add_theme_color_override('font_color',INK)
	flag_alert=label('',Vector2(382,16),Vector2(360,46),22)
	flag_alert.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	flag_alert.add_theme_stylebox_override('normal',Paper.box('toolbar'))
	flag_alert.add_theme_color_override('font_color',INK)
	hint=label('',Vector2(28,66),Vector2(1280,36),21)
	outline(hint)
	button('?',Vector2(1634,12),Vector2(56,54),func():
		controls.visible=not controls.visible
		power_note.visible=controls.visible)
	button(words('暂停','Pause'),Vector2(1696,12),Vector2(99,54),func():paused=not paused)
	button(words('菜单','Menu'),Vector2(1801,12),Vector2(101,54),func():closed.emit())
	character_picker=OptionButton.new()
	character_picker.position=Vector2(1406,12)
	character_picker.size=Vector2(218,56)
	character_picker.focus_mode=Control.FOCUS_NONE
	character_picker.add_theme_font_size_override('font_size',22)
	Paper.button(character_picker,'toolbar')
	character_picker.get_popup().add_theme_stylebox_override('panel',Paper.box('paper'))
	character_picker.get_popup().add_theme_stylebox_override('hover',Paper.box('toolbar','selected'))
	character_picker.get_popup().add_theme_color_override('font_color',INK)
	character_picker.get_popup().add_theme_color_override('font_hover_color',Color('#fff0c5'))
	character_picker.get_popup().add_theme_color_override('font_separator_color',INK)
	character_picker.get_popup().add_theme_font_size_override('font_size',22)
	var last_category=''
	for row in rules.characters:
		if row.category!=last_category:
			character_picker.add_separator(words(row.category,{'神明':'Gods','英雄':'Heroes','怪物':'Creatures'}[row.category]))
			character_ids.append('')
			last_category=row.category
		character_picker.add_item(words(row.name,row.name_en))
		character_ids.append(row.id)
	character_picker.item_selected.connect(func(index):choose_deity(character_ids[index]))
	add_child(character_picker)
	portrait=TextureRect.new()
	portrait.position=Vector2(1342,8)
	portrait.size=Vector2(60,62)
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	power_note=label('',Vector2(1060,72),Vector2(834,72),22)
	power_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	outline(power_note)
	power_note.hide()
	var kinds=['legion','archer','cavalry','spear','guard','medic','siege']
	for i in kinds.size():
		var kind=kinds[i]
		buttons[kind]=button('',Vector2(18+i*153,1006),Vector2(148,56),func():arm_reserve(kind))
	combined_button=button(words('七兵种布阵','All seven arms'),Vector2(18,938),Vector2(210,54),func():
		if rules.deploy_combined():
			selected=''
			set_camera(Vector2(100,100)))
	setup_button=button(words('标准布阵','Vanguard'),Vector2(240,938),Vector2(180,56),func():
		if rules.deploy_vanguard():selected='')
	setup_button.tooltip_text=words('步兵在前，弓兵在后，骑兵守侧翼。各留一队弓兵和骑兵。','Infantry front, archers behind, cavalry on the wing. Keep one archer and one cavalry in reserve.')
	defender_button=button(words('山口守阵','Defensive line'),Vector2(434,938),Vector2(215,56),func():
		if rules.deploy_defenders():
			selected=''
			set_camera(Vector2(-120,110)))
	defender_button.tooltip_text=words('指挥军阵守住山口，火箭可点燃油桶','Command the defending regiments. Fire arrows ignite oil barrels.')
	strength_bar=ColorRect.new()
	strength_bar.position=Vector2(754,30)
	strength_bar.size=Vector2(412,12)
	strength_bar.color=Color('#597f92')
	strength_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(strength_bar)
	ally_bar=ColorRect.new()
	ally_bar.color=Color('#c36649')
	ally_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	strength_bar.add_child(ally_bar)
	pace_button=button('1×',Vector2(1226,12),Vector2(88,54),func():slow=not slow)
	assault_button=button(words('全军进攻','All attack'),Vector2(1348,1006),Vector2(185,56),func():
		if selected=='route':selected=''
		rules.command(rules.alive('ally').map(func(u):return u.id),'auto',Vector2.ZERO))
	var roster_size=0
	for stock in rules.reserve.values():roster_size+=int(stock)
	for i in roster_size:
		var tab=button('',Vector2(18+i*115,938),Vector2(111,56),func():
			var army=rules.units.filter(func(u):return u.side=='ally')
			if i<army.size() and not army[i].routing and army[i].hp>0:
				squad_ids=[army[i].id]
				selected='route' if rules.phase=='battle' else '')
		roster.append(tab)
	buttons.lightning=button('',Vector2(1550,1006),Vector2(175,56),arm_power)
	start_button=button(words('开战','Begin'),Vector2(1738,1006),Vector2(164,56),func():
		if rules.start():
			oil_index=-1
			placing_rank=false
			selected=''
			if app!=null:app.sound.play_rally()
		elif rules.phase=='battle':
			if selected=='route':selected=''
			rules.command(squad_ids,'hold',Vector2.ZERO))
	controls=label('',Vector2(28,843),Vector2(1080,80),21)
	outline(controls)
	controls.hide()
	result=label('',Vector2(410,440),Vector2(1100,150),46)
	result.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_color_override('font_shadow_color',Color('#162c31'))
	result.add_theme_constant_override('shadow_offset_x',4)
	result.add_theme_constant_override('shadow_offset_y',4)
	add_child(myth_audio)
	refresh()
func arm_reserve(kind: String):
	if rules.reserve.get(kind,0)<=0:return
	selected=kind
	squad_ids.clear()
	placing_rank=false

func rank_slots() -> Dictionary:
	return rules.layout_positions(squad_ids,rank_start,rank_end,rank_dragged)

func outline(text_label: Label):
	text_label.add_theme_color_override('font_outline_color',Color('#212c28'))
	text_label.add_theme_constant_override('outline_size',5)

func label(value: String,pos: Vector2,dimensions: Vector2,font_size: int) -> Label:
	var l=Label.new()
	l.text=value
	l.position=pos
	l.size=dimensions
	l.add_theme_font_size_override('font_size',font_size)
	l.add_theme_color_override('font_color',Color('#f1dc9f'))
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l
func button(value: String,pos: Vector2,dimensions: Vector2,action: Callable) -> Button:
	var b=Button.new()
	b.text=value
	b.position=pos
	b.size=dimensions
	b.add_theme_font_size_override('font_size',22)
	b.focus_mode=Control.FOCUS_NONE
	Paper.button(b,'toolbar')
	b.pressed.connect(action)
	add_child(b)
	return b
func refresh():
	var character=rules.characters.filter(func(c):return c.id==rules.deity)[0]
	if portrait_id!=rules.deity:
		portrait_id=rules.deity
		var frame: AtlasTexture=field.animations[rules.deity].get_frame_texture('action',2)
		var cropped=AtlasTexture.new()
		cropped.atlas=frame.atlas
		var used=frame.atlas.get_image().get_region(Rect2i(frame.region)).get_used_rect()
		cropped.region=Rect2(frame.region.position+Vector2(used.position),Vector2(used.size))
		portrait.texture=cropped
		character_picker.select(character_ids.find(rules.deity))
	character_picker.disabled=rules.phase not in ['deploy','battle']
	power_note.text=words(character.power,character.power_en)+'\n'+skill_text(character.summary,character.summary_en)
	character_picker.tooltip_text=skill_text(character.description,character.description_en)
	buttons.lightning.tooltip_text=character_picker.tooltip_text
	status.text='%02d:%02d   '%[int(rules.elapsed)/60,int(rules.elapsed)%60]+words('我军 %d · 敌军 %d','Allies %d · Foes %d')%[rules.alive('ally').size(),rules.alive('enemy').size()]
	hint.text=words('在虚线区点击部署','Click inside the marked zone to deploy') if rules.phase=='deploy' else ''
	if selected=='lightning' and rules.phase=='battle':
		hint.text=words(character.power,character.power_en)+words(' · 点击落点',' · Choose a target')
	setup_button.visible=rules.phase=='deploy' and rules.alive('ally').is_empty()
	combined_button.visible=setup_button.visible
	defender_button.visible=setup_button.visible
	if rules.phase=='deploy' and not squad_ids.is_empty():
		hint.text=words('右键移动 · 右拖拉出阵线 · R 收回','Right click to reposition · Right drag a line · R to reserve')
	elif rules.phase=='deploy' and not setup_button.visible:
		hint.text=words('点选或 Shift 框选已部署部队，可重新布阵','Select or Shift-box deployed squads to reposition')
	if notice_seconds>0:hint.text=notice
	if paused:hint.text=words('已暂停 · 空格继续','PAUSED · Space to resume')
	var names={'legion':words('步兵','Infantry'),'archer':words('弓兵','Archers'),'cavalry':words('骑兵','Cavalry'),'spear':words('长矛兵','Spears'),'guard':words('重盾卫','Guards'),'medic':words('军医','Medics'),'siege':words('投石机','Onagers')}
	for kind in names:
		var active: bool=selected==kind
		if buttons[kind].get_meta('active',false)!=active:
			Paper.button(buttons[kind],'toolbar',active)
			buttons[kind].set_meta('active',active)
		buttons[kind].text=names[kind]+' ×'+str(int(rules.reserve.get(kind,0)))
		buttons[kind].disabled=rules.reserve.get(kind,0)<=0 or rules.phase not in ['deploy','battle']
	var aiming=selected=='lightning'
	if buttons.lightning.get_meta('active',false)!=aiming:
		Paper.button(buttons.lightning,'toolbar',aiming)
		buttons.lightning.set_meta('active',aiming)
	buttons.lightning.text=words('神力','Cast')+(' ∞' if rules.unlimited_powers else ' ×'+str(rules.charges)+(' %ds'%ceili(rules.cooldown) if rules.cooldown>0 else ''))
	buttons.lightning.disabled=rules.phase in ['victory','defeat','timeout']
	start_button.disabled=rules.phase=='deploy' and rules.alive('ally').is_empty()
	controls.text=words('左拖移图 · Shift 拖框选队 · 右键移动或集火\nH 坚守 · A 自动 · 方向键／中键移镜 · 滚轮缩放','Drag to pan · Shift-drag select · RMB move / focus\nH hold · A auto · Arrows / MMB pan · Wheel zoom')
	if rules.phase=='battle':
		start_button.tooltip_text=words('短三角为阵面。盾兵坚守时保持当前朝向。','The triangle marks the front. Holding shield infantry keep their heading.')
		start_button.text=words('坚守','Hold')+' ×'+str(squad_ids.size())
		start_button.disabled=squad_ids.is_empty()
	if rules.phase in ['victory','defeat','timeout']:
		match rules.outcome:
			'enemy_routed':result.text=words('敌军已被击溃 · 胜利','Victory · Enemy army routed')
			'time_held':result.text=words('守城时间已到 · 军旗守住了','Victory · Standard held until time expired')
			'flag_lost':result.text=words('罗马军旗失守 · 战败','Defeat · The Roman standard fell')
			'defenders_routed':result.text=words('守军溃败 · 战败','Defeat · Defenders routed')
		start_button.disabled=false
		start_button.text=words('重新试战','Retry')
		if not start_button.has_meta('retry'):
			start_button.set_meta('retry',true)
			start_button.pressed.connect(retry)
	assault_button.visible=rules.phase=='battle'
	pace_button.text='0.5×' if slow else '1×'
	var strength=rules.strength('ally')
	ally_bar.size=Vector2(412*strength/maxf(1,strength+rules.strength('enemy')),12)
	var army=rules.units.filter(func(u):return u.side=='ally')
	for i in roster.size():
		var tab: Button=roster[i]
		tab.visible=i<army.size() and rules.phase in ['battle','deploy']
		if not tab.visible:continue
		var u=army[i]
		tab.disabled=u.routing or u.hp<=0
		tab.text=str(i+1)+' '+names[u.kind]
		if tab.get_meta('chosen',false)!=(u.id in squad_ids):
			tab.set_meta('chosen',u.id in squad_ids)
			Paper.button(tab,'toolbar',u.id in squad_ids)
		tab.tooltip_text=words('士气 %d','Morale %d')%ceili(u.morale)
	if notice_seconds<=0 and not paused and selected!='lightning':
		if rules.phase=='deploy' and squad_ids.is_empty():
			hint.text=words('保护鹰旗 · 敌军独占 %s 秒即失守 · 选择布阵或手动部署','Guard the standard · Enemy captures in %s s · Choose a formation or deploy')%str(rules.capture_seconds).trim_suffix('.0')
		elif rules.phase=='battle':
			hint.text=words('守住军旗三分钟或击溃敌军 · 右键油桶发射火箭','Guard the standard for 3 min or rout the enemy · Right-click oil for fire arrows')
	flag_alert.visible=rules.flag_state!='secure' and rules.phase=='battle'
	if flag_alert.visible:
		var state=words('军旗告急','Flag threatened') if rules.flag_state=='capturing' else words('旗区争夺','Contested')
		flag_alert.text=state+'  %.1f / %s s'%[floorf((rules.capture_time+1e-8)*10)/10,str(rules.capture_seconds).trim_suffix('.0')]
		flag_alert.modulate=Color('#ffd294') if rules.flag_state=='contested' else Color('#ffac88')
	if selected=='route' and rules.phase=='battle' and notice_seconds<=0:
		hint.text=words('Shift＋点击添加途经点 · 左键确认终点 · Esc 取消','Shift-click for waypoints · Click to march · Esc to cancel')
		if paused:hint.text=words('已暂停 · ','Paused · ')+hint.text
func retry():
	myth_audio.stop_all()
	var deity=rules.deity
	rules=PassBattle.new()
	slow=false
	oil_index=-1
	rules.select_deity(deity)
	field.effects.clear()
	squad_ids.clear()
	gesture=false
	placing_rank=false
	drag_select=false
	zoom=1.0
	set_camera(Vector2.ZERO)
	selected='legion'
	paused=false
	accumulator=0
	result.text=''
	notice_seconds=0
	notice=''
	start_button.text=words('开战','Begin')
	if start_button.pressed.is_connected(retry):start_button.pressed.disconnect(retry)
	start_button.remove_meta('retry')
	refresh()
func _process(dt: float):
	notice_seconds=maxf(0,notice_seconds-dt)
	var pan=Vector2(Input.get_axis('ui_left','ui_right'),Input.get_axis('ui_up','ui_down'))
	if pan!=Vector2.ZERO and not character_picker.get_popup().visible:
		set_camera(camera_offset+pan.normalized()*920*dt/zoom)
	pointer=field.unproject(field_point(get_local_mouse_position()))
	if paused:field.queue_redraw()
	if not squad_ids.is_empty():
		squad_ids=squad_ids.filter(func(id):return rules.units.any(func(u):return u.id==id and u.hp>0 and not u.get('routing',false)))
		if squad_ids.is_empty() and selected=='route':selected=''
	myth_audio.advance(minf(dt,.1),paused,bool(app.prefs.enabled) if app!=null else true,float(app.prefs.volume) if app!=null else .7)
	if not paused:
		var battle_dt=minf(dt,.1)*(.5 if slow else 1.0)
		accumulator+=battle_dt
		while accumulator>=1.0/60:
			rules.step(1.0/60)
			accumulator-=1.0/60
		field.advance(battle_dt)
		for event in rules.events:
			field.effect(event)
			if myth_audio.handle_event(event):continue
			if app!=null and event.kind!='heal':app.sound.play('arrow' if event.kind=='arrow' else 'impact',.5)
		rules.events.clear()
	refresh()
func field_point(screen: Vector2) -> Vector2:
	return camera_offset+screen/zoom

func set_camera(offset: Vector2):
	var surface_rect: Rect2=field.LANDSCAPE
	var maximum=surface_rect.end-Vector2(1920,1080)/zoom
	camera_offset=offset.clamp(surface_rect.position,maximum).snapped(Vector2(2,2))
	field.get_viewport().canvas_transform=Transform2D(0,Vector2.ONE*zoom,0,-camera_offset*.5*zoom)
	field.queue_redraw()

func squad_at(screen: Vector2, side: String, centers_only: bool=false) -> Dictionary:
	var found: Dictionary={}
	var best=INF
	for unit in rules.alive(side):
		var feet: Vector2=(field.project(unit.pos)-camera_offset)*zoom
		var local=(screen-feet)/zoom
		var distance=Vector2(local.x,(local.y+35)*1.3).length()
		if (not centers_only or distance<90) and field.regiment_bounds(unit).has_point(local) and distance<best:
			found=unit
			best=distance
	return found

func select_squads(screen: Vector2, additive: bool):
	selected=''
	if not additive:squad_ids.clear()
	if drag_select:
		var box=Rect2(drag_origin,screen-drag_origin).abs()
		for squad in rules.alive('ally'):
			if box.has_point((field.project(squad.pos)-Vector2(0,35)-camera_offset)*zoom) and squad.id not in squad_ids:
				squad_ids.append(squad.id)
	else:
		var squad=squad_at(screen,'ally')
		if not squad.is_empty():
			if squad.id not in squad_ids:squad_ids.append(squad.id)
			if rules.phase=='battle' and not additive:
				selected='route'
				notice_seconds=0
	field.queue_redraw()

func _notification(what):
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		placing_rank=false
		gesture=false
		drag_select=false

func _input(event):
	if placing_rank:
		if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed):
			var screen: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
			rank_end=field.unproject(field_point(screen))
			rank_dragged=rank_dragged or screen.distance_to(rank_screen_start)>7
			if event is InputEventMouseButton:
				if not rules.place_layout(rank_slots()):
					notice=words('阵位重叠或超出部署区','Formation overlaps or leaves the zone')
					notice_seconds=2
				placing_rank=false
			field.queue_redraw()
			get_viewport().set_input_as_handled()
		return
	if not gesture:return
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed):
		var screen: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
		drag_end=screen
		var delta=screen-drag_origin
		dragged=dragged or delta.length()>7
		drag_select=dragged and box_gesture
		if dragged and not box_gesture:
			set_camera(camera_at_press-delta/zoom)
		if event is InputEventMouseButton:
			gesture=false
			if drag_select:select_squads(screen,false)
			elif not dragged:click_ground(screen,box_gesture)
			drag_select=false
		field.queue_redraw()
		get_viewport().set_input_as_handled()

func squad_at_id() -> Dictionary:
	for u in rules.alive('ally'):
		if u.id in squad_ids:return u
	return {}

func click_ground(screen: Vector2, additive: bool):
	pointer=field.unproject(field_point(screen))
	if rules.phase not in ['battle','deploy']:return
	if oil_index>=0 and rules.phase=='deploy':
		if rules.move_oil(oil_index,pointer):oil_index=-1
		else:
			notice=words('请在标记区域内分开布置两组油桶','Place oil inside the marked strip, apart from other oil')
			notice_seconds=2
		return
	if selected=='lightning':
		if paused:return
		if rules.strike(pointer):notice=words('神力已施放','Power released')
		else:
			notice=power_block_reason()
			if notice=='':notice=words('请选择战场内的目标','Aim inside the battlefield')
		notice_seconds=2
	elif selected=='route' and squad_at(screen,'ally',true).is_empty():
		var squad=squad_at_id()
		if squad.is_empty():return
		if not rules.bounds.has_point(pointer):
			notice=words('请选择战场边界内的行军落点','Choose a destination inside the battlefield')
			notice_seconds=2
		elif additive and rules.plan_route(squad,draft_waypoints,pointer).ok:
			draft_waypoints.append(pointer)
			notice_seconds=0
		elif not additive and squad_ids.size()==1 and rules.march_route(squad_ids[0],draft_waypoints,pointer):
			selected=''
			notice_seconds=0
		else:
			notice=words('此处无法通过 · 请换一个落点','Formation cannot pass · Choose another point')
			notice_seconds=2
	elif selected in ['','route'] or not squad_at(screen,'ally').is_empty():
		select_squads(screen,additive)
	elif not paused and rules.deploy(selected,pointer):
		if app!=null:app.sound.play('horn',.5)
		if rules.phase=='battle':selected=''
	else:
		notice=words('在部署区的空地投入部队','Deploy on open ground inside the marked zone')
		notice_seconds=2

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		var code=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		match code:
			KEY_1:arm_reserve('legion')
			KEY_2:arm_reserve('archer')
			KEY_3:arm_reserve('cavalry')
			KEY_4:arm_reserve('spear')
			KEY_5:arm_reserve('guard')
			KEY_6:arm_reserve('medic')
			KEY_7:arm_reserve('siege')
			KEY_R:
				if rules.phase=='deploy':
					rules.reserve_squads(squad_ids)
					squad_ids.clear()
					placing_rank=false
			KEY_Q:arm_power()
			KEY_H,KEY_A:
				if selected=='route':selected=''
				rules.command(squad_ids,'hold' if code==KEY_H else 'auto',Vector2.ZERO)
			KEY_ESCAPE:
				if selected=='route':
					selected=''
					notice_seconds=0
				else:paused=not paused
			KEY_SPACE:paused=not paused
	if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_MIDDLE:
		set_camera(camera_offset-get_global_transform_with_canvas().basis_xform_inv(event.relative)/zoom)
	if not event is InputEventMouseButton or not event.pressed:return
	var screen: Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
	pointer=field.unproject(field_point(screen))
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var anchor=field_point(screen)
		zoom=clampf(zoom+(.25 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.25),.5,5.0/3.0)
		set_camera(anchor-screen/zoom)
		return
	if event.button_index==MOUSE_BUTTON_LEFT:
		gesture=true
		dragged=false
		drag_select=false
		box_gesture=rules.phase in ['deploy','battle'] and event.shift_pressed
		camera_at_press=camera_offset
		drag_origin=screen
		drag_end=screen
		return
	if rules.phase not in ['battle','deploy']:return
	if event.button_index==MOUSE_BUTTON_RIGHT:
		if selected=='lightning':
			selected=''
			return
		if selected=='route':selected=''
		if rules.phase=='deploy':
			var oil=rules.barrel_at(pointer)
			oil_index=rules.barrels.find(oil)
			if oil_index>=0:
				selected=''
				return
		if rules.phase=='battle':
			var barrel=rules.barrel_at(pointer)
			if not barrel.is_empty():
				var lit=not paused and rules.ignite(barrel)
				notice=words('火箭已发射','Fire arrow away') if lit else words('需要未暂停且射程内有弓兵','Resume with archers in range')
				notice_seconds=2
				return
		if selected!='':
			selected=''
			if rules.phase=='battle':return
		if rules.phase=='deploy':
			if not squad_ids.is_empty():
				placing_rank=true
				rank_dragged=false
				rank_screen_start=screen
				rank_start=pointer
				rank_end=pointer
				return
			var squad=squad_at(screen,'ally')
			if not squad.is_empty():
				rules.reserve_squads([squad.id])
		elif not squad_ids.is_empty():
			var enemy=squad_at(screen,'enemy')
			if not enemy.is_empty():rules.command(squad_ids,'attack',enemy.pos,enemy.id)
			elif rules.bounds.has_point(pointer) and not rules.command(squad_ids,'move',pointer):
				notice=words('队形无法到达 · 原命令继续','Formation cannot reach · Previous orders retained')
				notice_seconds=2
	field.queue_redraw()


func choose_deity(id: String):
	if not rules.select_deity(id):return
	if rules.phase=='battle':arm_power()
	else:
		notice=words('已选择角色。部署部队并开战后，按 Q 或点击技能，再点击战场释放。','Character selected. Deploy and begin, then press Q and click the battlefield.')
		notice_seconds=4
	refresh()

func power_block_reason() -> String:
	if paused:return words('当前已暂停，请先继续战斗。','Paused. Resume the battle first.')
	if rules.phase=='deploy':return words('先部署至少一队并点击「开战」，随后才能施放神力。','Deploy a squad and press Begin before using divine power.')
	if rules.phase!='battle':return words('战斗已经结束。','Battle has ended.')
	if not rules.unlimited_powers and rules.charges<=0:return words('本场神力次数已用完。','No divine charges remain.')
	if not rules.unlimited_powers and rules.cooldown>0:return words('神力冷却中，还需 %d 秒。','Power recharging: %d seconds remaining.')%ceili(rules.cooldown)
	return ''

func arm_power():
	notice=power_block_reason()
	if notice=='':
		selected='lightning'
		var character=rules.characters.filter(func(c):return c.id==rules.deity)[0]
		notice=skill_text(character.summary,character.summary_en)+words(' · 点击落点释放',' · Click a target location')
	notice_seconds=4

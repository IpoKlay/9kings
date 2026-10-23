extends Control
const Campaign = preload('res://scripts/campaign.gd')
const Field = preload('res://scripts/battlefield.gd')
const Sound = preload('res://scripts/sound.gd')
const CardHand = preload('res://scripts/card_hand.gd')
const Expedition = preload('res://scripts/expedition.gd')
const MapIcon = preload('res://scripts/map_icon.gd')
const ExpeditionMap = preload('res://scenes/expedition_map.tscn')
var card_hand
var dealt_year = -1
var campaign = Campaign.new()
var expedition = Expedition.new(campaign)
var expedition_map
var battle_screen: TextureRect
var world
var sound
var ui: Control
var modal: Control
var dialog_kind = ''
var language = 'zh'
var paused = false
var speed = 1
var accumulator = 0.0
var hit_stop = 0.0
var result_delay = -1.0
var elapsed_label: Label
var toast_label: Label
var toast_time = 0.0
var prefs = {'language':'zh','enabled':true,'volume':.7,'voices':.55,'impact':true}
var font = SystemFont.new()
var input_locked = false

func _ready():
	load_prefs()
	language = prefs.language
	font.font_names = PackedStringArray(['Songti SC','Noto Serif CJK SC','Georgia','serif'])
	var theme_data = Theme.new()
	theme_data.default_font = font
	theme_data.default_font_size = 24
	theme = theme_data
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport = SubViewport.new()
	viewport.size = Vector2i(960,540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(viewport)
	world = Field.new()
	world.game = campaign
	world.translated = campaign.rules.zh
	world.scale = Vector2(.5,.5)
	viewport.add_child(world)
	var screen = TextureRect.new()
	battle_screen = screen
	screen.texture = viewport.get_texture()
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.position = Vector2.ZERO
	screen.size = Vector2(1920,1080)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	sound = Sound.new()
	add_child(sound)
	apply_prefs()
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	expedition_map = ExpeditionMap.instantiate()
	expedition_map.app = self
	add_child(expedition_map)
	world.refresh()
	render_ui()
	if '--render-test' in OS.get_cmdline_user_args(): call_deferred('run_render_test')
	if '--smoke-test' in OS.get_cmdline_user_args(): call_deferred('run_smoke_test')

func tr_text(value: String) -> String:
	return campaign.rules.zh.get(value,value) if language=='zh' else value
func tx(zh: String,en: String) -> String:
	return zh if language=='zh' else en
func year_text() -> String:
	if expedition.state.target != '': return expedition.node_text(expedition.state.target)+' · '+tx('远征战斗','Battle')
	return tx('鹰旗之下 · 军营','Under the Eagle · Camp')
func load_prefs():
	var config = ConfigFile.new()
	if config.load('user://settings.cfg') != OK: return
	for key in prefs: prefs[key] = config.get_value('settings',key,prefs[key])
	if prefs.language not in ['zh','en']: prefs.language='zh'
	prefs.volume = clampf(float(prefs.volume),0,1)
	prefs.voices = clampf(float(prefs.voices),0,1)
func save_prefs():
	var config = ConfigFile.new()
	for key in prefs: config.set_value('settings',key,prefs[key])
	config.save('user://settings.cfg')
func apply_prefs():
	if sound == null: return
	sound.enabled = prefs.enabled
	sound.volume = prefs.volume
	sound.voices = prefs.voices
	world.impact = prefs.impact
	world.language = language
	if not prefs.enabled: sound.stop()
func style(material: String) -> StyleBoxTexture:
	var box = StyleBoxTexture.new()
	box.texture = world.tex('panel_'+material)
	for edge in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		box.set_texture_margin(edge,8)
		box.set_content_margin(edge,14)
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return box
func label(parent: Node,value: String,pos: Vector2,sz: Vector2,font_size: int = 24,color: Color = Color('#ece1bd')) -> Label:
	var l = Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = value
	l.position = pos
	l.size = sz
	l.add_theme_font_size_override('font_size',font_size)
	l.add_theme_color_override('font_color',color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
func button(parent: Node,value: String,pos: Vector2,sz: Vector2,action: Callable,gold: bool = false) -> Button:
	var b = Button.new()
	b.text = value
	b.position = pos
	b.size = sz
	b.add_theme_stylebox_override('normal',style('gold' if gold else 'wood'))
	b.add_theme_stylebox_override('hover',style('gold'))
	b.add_theme_stylebox_override('pressed',style('wood'))
	b.add_theme_stylebox_override('focus',StyleBoxEmpty.new())
	b.add_theme_color_override('font_color',Color('#f2e4bc'))
	b.add_theme_color_override('font_hover_color',Color('#fff1c5'))
	b.add_theme_color_override('font_pressed_color',Color('#dcc582'))
	b.add_theme_font_size_override('font_size',24)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		sound.play('click')
		action.call())
	b.mouse_entered.connect(func():sound.play('hover'))
	parent.add_child(b)
	return b
func picture(parent: Node,id: String,pos: Vector2,sz: Vector2):
	var art = TextureRect.new()
	art.texture = world.tex(id)
	art.position = pos
	art.size = sz
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	return art
func remove_children(parent: Node):
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
func render_ui():
	expedition.language = language
	expedition.finish_supply()
	var on_map = expedition.state.mode == 'map'
	ui.visible = not on_map
	battle_screen.visible = not on_map
	expedition_map.visible = on_map
	if on_map: expedition_map.render()
	card_hand=null
	remove_children(ui)
	elapsed_label = null
	var yr = label(ui,year_text(),Vector2(700,25),Vector2(520,55),38)
	yr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yr.add_theme_color_override('font_shadow_color',Color('#12251e'))
	yr.add_theme_constant_override('shadow_offset_x',3)
	yr.add_theme_constant_override('shadow_offset_y',3)
	var wave = campaign.current_encounter()
	if expedition.state.target != '' and campaign.g.phase in ['reward','place','prepare']:
		var counts = {}
		for type in wave.roster: counts[type]=counts.get(type,0)+1
		var names: Array[String] = []
		for type in counts: names.append(tr_text(campaign.enemies[type].name)+' ×'+str(counts[type]))
		var threat = label(ui,'  ·  '.join(names),Vector2(450,82),Vector2(1020,30),20,Color('#bdd0ad'))
		threat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var map_button = button(ui,'',Vector2(1735,25),Vector2(65,60),open_map)
	map_button.name = 'MapButton'
	map_button.tooltip_text = tx('远征地图','Expedition map')
	var icon = MapIcon.new()
	icon.position = Vector2(12,10)
	icon.size = Vector2(40,40)
	map_button.add_child(icon)
	button(ui,'⚙',Vector2(1820,25),Vector2(65,60),func():open_dialog('settings')).tooltip_text=tr_text('Settings')
	button(ui,tr_text('BUILD'),Vector2(35,25),Vector2(142,55),func():open_dialog('build')).tooltip_text=tr_text('View army and doctrines')
	var phase = campaign.g.phase
	if phase in ['reward','place']:
		var hint = label(ui,tx('选择补给并完成建造；点击右上角地图继续远征。','Choose supplies and finish building; open the map at the top right to continue.'),Vector2(490,86),Vector2(940,40),24,Color('#dbc89f'))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if phase=='reward':
		var hand = campaign.offers()
		card_hand=CardHand.new()
		ui.add_child(card_hand)
		card_hand.allowed=func():return expedition.state.mode!='map' and dialog_kind=='' and campaign.g.phase=='reward' and not input_locked
		card_hand.picked.connect(choose_card)
		card_hand.cue.connect(func(gesture):sound.play_card(gesture))
		for i in hand.size(): card_button(hand[i],i)
		card_hand.reveal(dealt_year!=int(campaign.g.round))
		dealt_year=int(campaign.g.round)
		button(ui,'↪',Vector2(1360,970),Vector2(65,55),skip_supply).tooltip_text=tr_text('Skip supply')
	elif phase=='place':
		var p = Panel.new()
		p.position=Vector2(580,950)
		p.size=Vector2(760,80)
		p.add_theme_stylebox_override('panel',style('wood'))
		ui.add_child(p)
		picture(p,'card_'+str(campaign.g.pending),Vector2(10,4),Vector2(72,72))
		label(p,tr_text(campaign.cards[campaign.g.pending].name)+'  ·  '+tr_text('BUILD / UPGRADE'),Vector2(100,18),Vector2(580,45),26)
		button(ui,'↪',Vector2(1360,966),Vector2(65,55),skip_supply).tooltip_text=tr_text('Skip supply')
	elif phase=='battle':
		button(ui,'Ⅱ' if not paused else '▶',Vector2(797,975),Vector2(72,60),toggle_pause)
		elapsed_label = label(ui,'00:00',Vector2(880,984),Vector2(140,40),28)
		elapsed_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		button(ui,str(speed)+'×',Vector2(1030,975),Vector2(90,60),change_speed)
	elif has_battle_report():
		var report_button = button(ui,tr_text('View report'),Vector2(790,970),Vector2(340,65),func():open_dialog('result'))
		report_button.name = 'ReportButton'
	toast_label = label(ui,'',Vector2(460,650),Vector2(1000,45),26,Color('#f0d6a2'))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	world.refresh()
	if campaign.g.battle==null:
		world.preview=world.preview.filter(func(unit):return unit.side=='ally')

func card_button(id: String,index: int):
	var data = campaign.cards[id]
	var origin = Vector2(582+index*258,728)
	var b = Button.new()
	b.position = origin
	b.size = Vector2(240,334)
	b.pivot_offset = b.size/2
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override('normal',style('paper'))
	b.add_theme_stylebox_override('hover',style('paper'))
	b.add_theme_stylebox_override('pressed',style('gold'))
	b.add_theme_stylebox_override('focus',StyleBoxEmpty.new())
	b.tooltip_text = tr_text(data.text)+(tx(' 可建于空地，或升级同类建筑，最高三级。',' Build or upgrade the same camp, max level III.') if data.kind=='Building' else '')
	ui.add_child(b)
	label(b,str(index+1),Vector2(15,10),Vector2(30,30),24,Color('#665333'))
	var suit = '◆' if data.kind=='Building' else '♠' if data.kind=='Permanent' else '♣'
	label(b,suit,Vector2(205,12),Vector2(25,25),23,Color('#7a3b32'))
	picture(b,'card_'+id,Vector2(64,27),Vector2(112,112))
	var title = label(b,tr_text(data.name),Vector2(13,140),Vector2(214,32),25 if language=='zh' else 22,Color('#28392d'))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var amount = label(b,tr_text(data.impact),Vector2(13,176),Vector2(214,35),28,Color('#7e3c2e'))
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var desc = label(b,tr_text(data.text),Vector2(17,214),Vector2(206,78),16 if language=='zh' else 15,Color('#3d4734'))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size = Vector2(206,78)
	desc.add_theme_constant_override('line_spacing',-2)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kind = label(b,tr_text(data.kind),Vector2(15,299),Vector2(210,25),17,Color('#6e6043'))
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_instance_valid(card_hand): card_hand.add_card(b,id,index)
	else: b.pressed.connect(func():choose_card(id))

func choose_card(id: String):
	if input_locked or dialog_kind!='' or campaign.g.phase!='reward' or id not in campaign.offers(): return
	input_locked=true
	if is_instance_valid(card_hand): await card_hand.commit(id)
	if campaign.choose(id):
		world.selected_cell = -1
		input_locked=false
		render_ui()
	else: input_locked=false

func skip_supply():
	if input_locked: return
	if campaign.skip(): render_ui()
func march():
	open_map()

func open_map():
	if input_locked or dialog_kind!='': return
	expedition.state.mode = 'map'
	accumulator=0
	render_ui()

func show_camp():
	if dialog_kind!='' or input_locked: return
	expedition.state.mode = 'battle' if campaign.g.phase=='battle' else 'camp'
	accumulator=0
	render_ui()

func travel_to(id: String):
	if input_locked or dialog_kind!='': return
	if not expedition.travel(id): return
	expedition_map.selected = ''
	if campaign.g.phase != 'battle':
		world.clear_battle()
		render_ui()
		return
	begin_battle_feedback()

func begin_battle_feedback():
	paused = false
	accumulator = 0
	hit_stop = 0
	result_delay = -1
	world.clear_battle()
	sound.play('horn')
	sound.play('cry')
	render_ui()
	toast(tr_text('LEGION, ADVANCE!'))
func toggle_pause():
	paused=not paused
	accumulator=0
	render_ui()
func change_speed():
	speed = 2 if speed==1 else 4 if speed==2 else 1
	render_ui()
func toast(message: String):
	toast_label.text=message
	toast_time=2
func _process(delta):
	if world==null: return
	if expedition.state.mode == 'map': return
	if dialog_kind!='' or paused: return
	if toast_time>0:
		toast_time-=delta
		if toast_time<=0 and is_instance_valid(toast_label): toast_label.text=''
	if result_delay>=0:
		result_delay-=delta
		if result_delay<0: open_dialog('result')
	var sim_delta = minf(delta,.1)*speed
	world.tick(sim_delta if campaign.g.phase=='battle' else delta)
	if campaign.g.phase!='battle': return
	if hit_stop>0:
		hit_stop-=delta
		return
	accumulator+=sim_delta
	while accumulator>=1.0/60 and campaign.g.phase=='battle':
		campaign.step(1.0/60)
		world.events(campaign.g.battle.events)
		play_events(campaign.g.battle.events)
		accumulator-=1.0/60
		if hit_stop>0: break
	if is_instance_valid(elapsed_label):
		var seconds=int(campaign.g.battle.time)
		elapsed_label.text='%02d:%02d'%[int(seconds/60.0),seconds%60]
	if campaign.g.phase in ['result','defeat']:
		accumulator=0
		sound.play('win' if campaign.g.battle.report.won else 'bad')
		render_ui()
		result_delay=.9
func play_events(events: Array):
	for e in events:
		match e.kind:
			'attack': sound.play('arrow' if e.ranged else 'swing',.6)
			'hit':
				sound.play('shield' if e.absorbed>0 else 'sword',.7)
				if e.get('broken',false): sound.play('break')
			'blast': sound.play('impact',1)
			'death':
				sound.play('kill')
				if prefs.impact: hit_stop=.045
				if e.side=='enemy': sound.play('cry',.55)
			'breach': sound.play('bad')

func _unhandled_input(event):
	if input_locked: return
	if expedition.state.mode == 'map':
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			if dialog_kind != '': close_dialog()
			elif expedition_map.selected != '': expedition_map.close_info()
			else: show_camp()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if dialog_kind!='': close_dialog()
			else: open_dialog('settings')
		elif dialog_kind=='':
			if event.keycode in [KEY_1,KEY_2,KEY_3] and campaign.g.phase=='reward':
				choose_card(campaign.offers()[event.keycode-KEY_1])
			elif event.keycode==KEY_SPACE:
				if campaign.g.phase=='battle': toggle_pause()
				elif campaign.g.phase=='prepare': march()
			elif event.keycode==KEY_M:
				prefs.enabled=not prefs.enabled
				apply_prefs()
				save_prefs()
	if dialog_kind!='': return
	if event is InputEventMouseMotion:
		world.hover_cell=world.cell_at(get_global_mouse_position()) if campaign.g.battle==null else -1
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and campaign.g.battle==null:
		var cell=world.cell_at(get_global_mouse_position())
		if cell<0: return
		if campaign.g.phase=='place':
			var existing=campaign.building_at(cell)!=null
			if campaign.place(cell):
				sound.play('upgrade' if existing else 'build')
				world.selected_cell=-1
				render_ui()
			else:
				sound.play('bad',.3)
				toast(tr_text('Cannot build here'))
		elif campaign.building_at(cell)!=null:
			world.selected_cell=cell
			open_dialog('building')
func close_dialog():
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal=null
	dialog_kind=''
	accumulator=0
func has_battle_report() -> bool:
	return campaign.g.phase in ['result','defeat'] and campaign.g.battle != null and campaign.g.battle.get('report') != null

func open_dialog(kind: String):
	if input_locked: return
	if kind=='result':
		result_delay=-1
		if not has_battle_report(): return
	close_dialog()
	dialog_kind=kind
	if is_instance_valid(card_hand): card_hand.set_active(-1,false)
	modal=Control.new()
	modal.z_index=100
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var shade=ColorRect.new()
	shade.color=Color(.02,.07,.05,.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var panel=Panel.new()
	panel.position=Vector2(600,205)
	panel.size=Vector2(720,650)
	panel.add_theme_stylebox_override('panel',style('paper'))
	modal.add_child(panel)
	button(panel,'×',Vector2(642,18),Vector2(56,50),close_dialog)
	match kind:
		'settings': settings_content(panel)
		'build': build_content(panel)
		'result': result_content(panel)
		'building': building_content(panel)
func heading(parent: Node,value: String):
	label(parent,value,Vector2(38,27),Vector2(580,50),34,Color('#293b2f'))
func settings_content(panel: Control):
	heading(panel,tr_text('Settings'))
	label(panel,tr_text('Language'),Vector2(40,104),Vector2(260,40),26,Color('#384832'))
	button(panel,'中文',Vector2(350,95),Vector2(130,54),func():set_language('zh'),language=='zh')
	button(panel,'English',Vector2(500,95),Vector2(165,54),func():set_language('en'),language=='en')
	setting_check(panel,'Sound effects','enabled',185)
	setting_slider(panel,'Master volume','volume',268)
	setting_slider(panel,'War cries','voices',360)
	setting_check(panel,'Impact effects','impact',452)
	button(panel,tr_text('Close'),Vector2(250,550),Vector2(220,60),close_dialog,true)
func set_language(value: String):
	language=value
	prefs.language=value
	apply_prefs()
	save_prefs()
	render_ui()
	open_dialog('settings')
func setting_check(panel: Control,title: String,key: String,y: float):
	label(panel,tr_text(title),Vector2(40,y),Vector2(440,40),25,Color('#384832'))
	button(panel,tx('开','ON') if prefs[key] else tx('关','OFF'),Vector2(520,y-5),Vector2(145,52),func():
		prefs[key]=not prefs[key]
		apply_prefs()
		save_prefs()
		open_dialog('settings'),prefs[key])
func setting_slider(panel: Control,title: String,key: String,y: float):
	label(panel,tr_text(title),Vector2(40,y),Vector2(270,40),25,Color('#384832'))
	var slider=HSlider.new()
	slider.position=Vector2(330,y+8)
	slider.size=Vector2(270,30)
	slider.min_value=0
	slider.max_value=1
	slider.step=.05
	slider.value=prefs[key]
	panel.add_child(slider)
	var number=label(panel,str(int(prefs[key]*100))+'%',Vector2(615,y),Vector2(85,40),22,Color('#384832'))
	slider.value_changed.connect(func(value):
		prefs[key]=value
		number.text=str(int(value*100))+'%'
		apply_prefs()
		save_prefs())
func build_content(panel: Control):
	heading(panel,tr_text('LEGION DOCTRINES'))
	var scroll=ScrollContainer.new()
	scroll.position=Vector2(38,100)
	scroll.size=Vector2(644,500)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list=VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override('separation',12)
	scroll.add_child(list)
	add_build_text(list,tr_text('ARMY'),27)
	for b in campaign.g.buildings:
		var stats=campaign.stats(b)
		var info='  +%d%%'%int(stats.bonus*100) if b.type=='training' else '  ♥ %d   ⚔ %d'%[stats.hp,stats.attack]
		add_build_text(list,tr_text(campaign.types[b.type].name)+' '+['','I','II','III'][int(b.level)]+info,23)
	add_build_text(list,'\n'+tr_text('PERMANENT UPGRADES'),27)
	if campaign.g.upgrades.is_empty(): add_build_text(list,tr_text('No doctrines yet. Your choices last for this campaign.'),20)
	for id in campaign.g.upgrades: add_build_text(list,tr_text(campaign.cards[id].name)+' ×'+str(campaign.rank(id))+'\n'+tr_text(campaign.cards[id].text),22)
	add_build_text(list,'\n'+tr_text('NEXT BATTLE'),27)
	for id in campaign.g.orders: add_build_text(list,tr_text(campaign.cards[id].name)+' — '+tr_text(campaign.cards[id].text),22)
	for synergy in campaign.synergies():
		add_build_text(list,('◆ ' if synergy.active else '◇ ')+tr_text(synergy.name)+'\n'+tr_text(synergy.text),22,Color('#36563c') if synergy.active else Color('#746b52'))
func add_build_text(list: VBoxContainer,value: String,font_size: int,color: Color = Color('#344331')):
	var l=Label.new()
	l.text=value
	l.custom_minimum_size.x=590
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override('font_size',font_size)
	l.add_theme_color_override('font_color',color)
	list.add_child(l)
func result_content(panel: Control):
	if campaign.g.battle==null: return
	var report=campaign.g.battle.report
	var ended=campaign.g.phase=='defeat'
	heading(panel,tx('远征结束' if ended else '城邦已夺取' if report.won else '进攻失利','Campaign ended' if ended else 'City secured' if report.won else 'Attack repelled'))
	label(panel,year_text(),Vector2(40,95),Vector2(400,45),27,Color('#6d5a3c'))
	picture(panel,'card_shield' if ended else 'card_legion',Vector2(295,140),Vector2(130,130))
	var rows=[['ENEMY LOSSES','%d / %d'%[report.enemyLosses,report.enemyCount]],['SURVIVORS','%d / %d'%[report.surviving,report.deployed]],['CAMP LIVES','%d / 3'%campaign.g.defense]]
	for i in rows.size():
		label(panel,tr_text(rows[i][0]),Vector2(65,300+i*60),Vector2(390,45),26,Color('#344331'))
		label(panel,rows[i][1],Vector2(520,300+i*60),Vector2(150,45),29,Color('#71392d'))
	button(panel,tx('重新远征' if ended else '远征告捷' if report.won and expedition.state.target=='727070' else '领取奖励' if report.won else '返回地图','New campaign' if ended else 'Victory' if report.won and expedition.state.target=='727070' else 'Claim reward' if report.won else 'Return to map')+' →',Vector2(185,535),Vector2(350,70),advance,true)
func advance():
	if not has_battle_report(): return
	close_dialog()
	if campaign.g.phase=='defeat':
		restart_expedition()
		return
	if not expedition.settle(): return
	world.clear_battle()
	world.selected_cell=-1
	paused=false
	result_delay=-1
	speed=1
	render_ui()
func restart_expedition():
	if input_locked: return
	close_dialog()
	campaign.reset()
	expedition.reset()
	expedition_map.selected=''
	expedition_map.history_open=false
	dealt_year=-1
	result_delay=-1
	paused=false
	speed=1
	hit_stop=0
	toast_time=0
	accumulator=0
	world.selected_cell=-1
	world.hover_cell=-1
	world.clear_battle()
	render_ui()

func building_content(panel: Control):
	var b=campaign.building_at(world.selected_cell)
	if b==null: return
	heading(panel,tr_text(campaign.types[b.type].name)+' '+['','I','II','III'][int(b.level)])
	picture(panel,'building_'+b.type+'_'+str(int(b.level)),Vector2(265,100),Vector2(190,190))
	var s=campaign.stats(b)
	var info=tr_text(campaign.cards[b.type].text)
	if b.type!='training': info+='\n\n'+tr_text('Health')+'  %d     '%s.hp+tr_text('Attack')+'  %d'%s.attack
	else: info+='\n\n+%d%%'%int(s.bonus*100)
	var detail=label(panel,info,Vector2(60,320),Vector2(600,160),27,Color('#344331'))
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	detail.size=Vector2(600,160)
	button(panel,tr_text('Close'),Vector2(250,545),Vector2(220,65),close_dialog,true)

func run_smoke_test():
	# Run by the native test harness; normal play never enables this path.
	var saved_prefs=prefs.duplicate(true)
	var before=campaign.g.duplicate(true)
	open_dialog('settings')
	set_language('en')
	assert(campaign.g==before,'Changing language mutated campaign')
	set_language('zh')
	close_dialog()
	skip_supply()
	assert(expedition.state.mode=='camp')
	open_map()
	assert(expedition.state.mode=='map')
	travel_to('148127')
	skip_supply()
	travel_to('246349')
	open_dialog('settings')
	var battle_time=campaign.g.battle.time
	await get_tree().process_frame
	assert(campaign.g.battle.time==battle_time,'Settings must suspend battle')
	close_dialog()
	paused=false
	speed=4
	while campaign.g.phase=='battle':
		campaign.step(1.0/60)
		world.events(campaign.g.battle.events)
	assert(campaign.g.battle.report.won,'Opening battle should be gentle')
	render_ui()
	open_dialog('result')
	await get_tree().process_frame
	advance()
	assert(campaign.g.round==3 and campaign.g.phase=='reward')
	assert(expedition.state.current=='246349')
	skip_supply()
	assert(expedition.state.mode=='camp')
	open_map()
	assert(expedition.state.mode=='map' and expedition.can_travel('256177'))
	prefs=saved_prefs
	save_prefs()
	sound.stop()
	print('NATIVE UI SMOKE PASSED: settings, language, initial cards, port, city battle, reward and next route.')
	await get_tree().process_frame
	get_tree().quit()

func capture_test_image(name: String):
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image=get_viewport().get_texture().get_image()
	image.save_png('res://tests/'+name+'.png')
func run_render_test():
	DisplayServer.window_set_title('Under the Eagle — visual verification')
	var saved_prefs=prefs.duplicate(true)
	sound.enabled=false
	campaign.reset(42)
	expedition.reset()
	campaign.offers()
	campaign.g.offered=['spear','crossfire','legionTrain']
	render_ui()
	card_hand.input_enabled=false
	await get_tree().create_timer(.5).timeout
	await capture_test_image('native-cards-zh')
	card_hand.set_active(1,false)
	await get_tree().create_timer(.3).timeout
	await capture_test_image('native-card-hover')
	card_hand.set_active(-1,false)
	# All descriptions must wrap within their card, in both languages.
	for lang in ['zh','en']:
		language=lang
		world.language=lang
		for id in campaign.cards:
			card_hand=null
			remove_children(ui)
			card_button(id,0)
			await get_tree().process_frame
			var card=ui.get_child(0)
			for child in card.get_children():
				if child is Label:
					assert(child.position.x+child.size.x<=card.size.x+1,'Card label overflows: '+id+' '+child.text+' '+str(child.position)+' '+str(child.size))
					assert(child.position.y+child.size.y<=card.size.y+1,'Card height overflows: '+id)
					if child.position.y==214: assert(child.position.y+child.size.y<=299,'Description overlaps footer: '+id+' '+lang+' '+str(child.size))
	language='en'
	world.language=language
	render_ui()
	await capture_test_image('native-cards-en')
	open_dialog('settings')
	await capture_test_image('native-settings')
	close_dialog()
	language='zh'
	world.language=language
	render_ui()
	await choose_card('spear')
	assert(campaign.g.phase=='place')
	assert(campaign.place(1))
	world.refresh()
	render_ui()
	await capture_test_image('native-built')
	travel_to('148127')
	skip_supply()
	travel_to('246349')
	sound.enabled=false
	paused=true
	for i in 480:
		campaign.step(1.0/60)
		world.tick(1.0/60)
		world.events(campaign.g.battle.events)
	elapsed_label.text='00:08'
	toast_label.text=''
	await capture_test_image('native-battle')
	open_dialog('build')
	await capture_test_image('native-build-panel')
	close_dialog()
	while campaign.g.phase=='battle': campaign.step(1.0/60)
	render_ui()
	open_dialog('result')
	await capture_test_image('native-result')
	close_dialog()
	prefs=saved_prefs
	sound.stop()
	print('VISUAL TEST PASSED: 48 bilingual cards fit; build, battle, settings and report captured.')
	get_tree().quit()

extends Control
const Catalog=preload('res://scripts/data/catalog.gd')
const RunStore=preload('res://scripts/data/run_store.gd')
var last_saved_run={}
var run_path_override=''
var save_error=false
const SettingsStore=preload('res://scripts/data/settings_store.gd')
var contracts: Dictionary=Catalog.data('schema/contracts')
var feedback: Dictionary=Catalog.presentation('feedback')
var ui_preset: Dictionary=Catalog.presentation('ui')
const MainMenu = preload('res://scripts/main_menu.gd')
const Campaign = preload('res://scripts/campaign.gd')
const Field = preload('res://scripts/battlefield.gd')
const Sound = preload('res://scripts/sound.gd')
const Music = preload('res://scripts/music.gd')
const CardHand = preload('res://scripts/card_hand.gd')
const CardFace = preload('res://scripts/card_face.gd')
const Expedition = preload('res://scripts/expedition.gd')
const MapIcon = preload('res://scripts/map_icon.gd')
const RomanUI = preload('res://scripts/roman_ui.gd')
const RPGUI = preload('res://scripts/rpg_ui.gd')
var documents=preload('res://scripts/expedition_documents.gd').new()
const ExpeditionMap = preload('res://scenes/expedition_map.tscn')
var card_hand
var dealt_year = -1
var campaign = Campaign.new()
var expedition = Expedition.new(campaign)
var expedition_map
var battle_screen: TextureRect
var world
var sound
var music
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
var wave_label: Label
var toast_label: Label
var toast_time = 0.0
var prefs = Catalog.new_state('settings')
var settings_path = SettingsStore.DEFAULT_PATH
var font: Font = preload('res://assets/fonts/game_pixel_font.tres')
var input_locked = false
var departure: Control
var main_menu = true
var has_run = false
var menu_view: Control
var start_rng = RandomNumberGenerator.new()
var starting_theaters: Array[int] = []
var camp_action = ''
var moving_building_id = -1
var camp_preview: Label

func _ready():
	documents.app=self
	start_rng.randomize()
	load_prefs()
	load_run()
	language = prefs.language
	theme = preload('res://assets/fonts/game_pixel_theme.tres')
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport = SubViewport.new()
	viewport.size = Vector2i(contracts.battle_render_size[0],contracts.battle_render_size[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
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
	screen.size = Vector2(contracts.viewport_size[0],contracts.viewport_size[1])
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	sound = Sound.new()
	add_child(sound)
	music = Music.new()
	add_child(music)
	apply_prefs()
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	expedition_map = ExpeditionMap.instantiate()
	expedition_map.app = self
	add_child(expedition_map)
	menu_view=MainMenu.new()
	menu_view.app=self
	add_child(menu_view)
	if '--render-test' in OS.get_cmdline_user_args() or '--smoke-test' in OS.get_cmdline_user_args(): main_menu=false
	world.refresh()
	render_ui()
	if '--render-test' in OS.get_cmdline_user_args(): call_deferred('run_render_test')
	if '--smoke-test' in OS.get_cmdline_user_args(): call_deferred('run_smoke_test')

func tr_text(value: String) -> String:
	return campaign.rules.zh.get(value,value) if language=='zh' else value
func tx(zh: String,en: String) -> String:
	return zh if language=='zh' else en
func theater_name(act: int) -> String:
	return [loc('main.western_sea_rocky_scrub'),loc('main.north_africa_oasis'),loc('main.eastern_sea_harbor')][clampi(act-1,0,2)]

func year_text() -> String:
	if expedition.state.opening=='card': return expedition.node_text(expedition.state.target)+' · '+loc('main.deployment')
	if expedition.state.target != '': return expedition.node_text(expedition.state.target)+' · '+loc('main.battle')
	return loc('main.under_the_eagle_camp')
func load_prefs():
	prefs=SettingsStore.read_settings(settings_path)
func save_prefs():
	var error=SettingsStore.write_settings(prefs,settings_path)
	if error!=OK: push_warning('Could not save player settings: '+error_string(error))
func apply_prefs():
	Engine.max_fps=int(prefs.fps_limit)
	if DisplayServer.get_name()!='headless' and DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if sound == null: return
	sound.enabled = prefs.enabled
	sound.volume = prefs.volume
	sound.voices = prefs.voices
	if music!=null: music.set_volume(prefs.volume,prefs.music_volume)
	world.impact = prefs.impact
	world.language = language
	if not prefs.enabled or prefs.volume<=0: sound.stop()
func style(material: String) -> StyleBoxTexture:
	var box = StyleBoxTexture.new()
	box.texture = world.tex('panel_'+material)
	for edge in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		box.set_texture_margin(edge,ui_preset.panel_texture_margin)
		box.set_content_margin(edge,ui_preset.panel_content_margin)
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
	sync_music()
	if main_menu or expedition.state.mode=='map' or campaign.g.phase not in ['reward','prepare']: camp_action=''
	world.camp_action=camp_action
	expedition.language = language
	world.environment_act=expedition.battlefield_act()
	world.menu_mode=main_menu
	menu_view.visible=main_menu
	if main_menu:
		ui.visible=false
		expedition_map.visible=false
		battle_screen.visible=false
		if is_instance_valid(card_hand): card_hand.set_active(-1,false)
		menu_view.render()
		world.queue_redraw()
		save_run()
		return
	var opening_card = expedition.state.opening=='card'
	expedition.finish_supply()
	if opening_card and campaign.g.phase=='battle':
		begin_battle_feedback()
		return
	var on_map = expedition.state.mode == 'map'
	ui.visible = not on_map
	battle_screen.visible = not on_map
	expedition_map.visible = on_map
	if on_map: expedition_map.render()
	card_hand=null
	remove_children(ui)
	elapsed_label = null
	wave_label = null
	var yr = label(ui,year_text(),Vector2(700,25),Vector2(520,55),38)
	yr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yr.add_theme_color_override('font_shadow_color',Color('#12251e'))
	yr.add_theme_constant_override('shadow_offset_x',3)
	yr.add_theme_constant_override('shadow_offset_y',3)
	var region = label(ui,theater_name(world.environment_act),Vector2(35,92),Vector2(380,40),21,Color('#e1c78f'))
	region.name='TheaterName'
	region.add_theme_color_override('font_shadow_color',Color('#12251e'))
	region.add_theme_constant_override('shadow_offset_x',2)
	region.add_theme_constant_override('shadow_offset_y',2)
	var wave = campaign.current_encounter()
	if expedition.state.target != '' and campaign.g.phase in ['reward','place','prepare']:
		var counts = {}
		for type in wave.roster: counts[type]=counts.get(type,0)+1
		var names: Array[String] = []
		for type in counts: names.append(tr_text(campaign.enemies[type].name)+' ×'+str(counts[type]))
		var threat = label(ui,'  ·  '.join(names),Vector2(450,134),Vector2(1020,30),20,Color('#bdd0ad'))
		threat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		threat.add_theme_color_override('font_shadow_color',Color('#12251e'))
		threat.add_theme_constant_override('shadow_offset_x',2)
		threat.add_theme_constant_override('shadow_offset_y',2)
	var map_button = button(ui,'',Vector2(1735,25),Vector2(65,60),open_map)
	map_button.name = 'MapButton'
	map_button.tooltip_text = loc('main.expedition_map')
	var icon = MapIcon.new()
	icon.position = Vector2(12,10)
	icon.size = Vector2(40,40)
	map_button.add_child(icon)
	var settings_button=button(ui,'',Vector2(1820,25),Vector2(65,60),func():open_dialog('settings'))
	settings_button.name='SettingsButton'
	settings_button.tooltip_text=tr_text('Settings')
	RomanUI.on_button(settings_button,'gear')
	var army_button=button(ui,tr_text('BUILD'),Vector2(35,25),Vector2(190,60),func():open_dialog('build'))
	army_button.name='ArmyButton'
	army_button.tooltip_text=tr_text('View army and doctrines')
	RomanUI.on_button(army_button,'helmet',48,true)
	var phase = campaign.g.phase
	var supply_hint: Label
	if phase in ['reward','place'] and camp_action=='':
		var hint_text = loc('main.click_a_highlighted_plot_to_build_or_a_matching') if phase=='place' else loc('main.choose_your_supplies')
		if expedition.state.opening=='card':
			hint_text=loc('main.place_or_upgrade_the_building_to_begin_the_first') if phase=='place' else loc('main.choose_one_starting_card_combat_begins_after_deployment')
		var hint = label(ui,hint_text,Vector2(490,86),Vector2(940,40),24,Color('#dbc89f'))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_color_override('font_shadow_color',Color('#12251e'))
		hint.add_theme_constant_override('shadow_offset_x',2)
		hint.add_theme_constant_override('shadow_offset_y',2)
		if phase=='reward': supply_hint=hint
	if camp_action!='':
		var action_hint=label(ui,loc('camp.expanding' if camp_action=='expand' else 'camp.moving'),Vector2(400,630),Vector2(1100,70),26,Color('#ecd08b'))
		action_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		button(ui,loc('camp.cancel'),Vector2(780,970),Vector2(360,65),cancel_camp_action)
	elif phase=='reward':
		var hand = campaign.offers()
		card_hand=CardHand.new()
		ui.add_child(card_hand)
		card_hand.allowed=func():return not main_menu and expedition.state.mode!='map' and dialog_kind=='' and campaign.g.phase=='reward' and camp_action=='' and not input_locked
		card_hand.picked.connect(choose_card)
		card_hand.cue.connect(func(gesture):sound.play_card(gesture))
		if campaign.g.reward_context=='recovery':supply_hint.text=tx('战败整备：上滑选择一张临时军令，仅限下次进攻','Regroup: swipe one temporary order for the next assault')
		elif campaign.g.reward_context=='elite':
			supply_hint.text=tx('精英战利品：可用强化保底','Elite spoils: available upgrade guaranteed')
			supply_hint.text+=tx(' · 可重抽一次',' · 1 redraw') if campaign.g.reward_rerolls>0 else tx(' · 重抽已用完',' · redraw used')
		var resting_hint=supply_hint.text
		card_hand.drag_changed.connect(func(dragging: bool,ready: bool):
			supply_hint.text=loc('cards.release_to_use' if ready else 'cards.drag_to_use') if dragging else resting_hint
			supply_hint.add_theme_color_override('font_color',Catalog.presentation('card_hand').face_palette.highlight if ready else Color('#dbc89f')))
		for i in hand.size(): card_button(hand[i],i)
		if campaign.g.reward_rerolls>0:
			var redraw=button(ui,tx('重抽一次','Redraw once'),Vector2(1415,880),Vector2(330,60),func():
				if input_locked:return
				if campaign.reroll_reward():render_ui())
			redraw.name='EliteReroll';RPGUI.button(redraw,'strip')
		card_hand.reveal(dealt_year!=int(campaign.g.round))
		dealt_year=int(campaign.g.round)
		if expedition.state.opening!='card': button(ui,'↪',Vector2(1360,970),Vector2(65,55),skip_supply).tooltip_text=tr_text('Skip supply')
	elif phase=='place':
		var p = Panel.new()
		p.position=Vector2(580,950)
		p.size=Vector2(760,80)
		p.add_theme_stylebox_override('panel',style('wood'))
		ui.add_child(p)
		deployment_art(p,str(campaign.g.pending),1,Rect2(4,-8,96,96))
		label(p,tr_text(campaign.cards[campaign.g.pending].name)+'  ·  '+tr_text('BUILD / UPGRADE'),Vector2(100,18),Vector2(580,45),26)
		if expedition.state.opening!='card': button(ui,'↪',Vector2(1360,966),Vector2(65,55),skip_supply).tooltip_text=tr_text('Skip supply')
	elif phase=='prepare':
		var next_button = button(ui,loc('main.continue_expedition') if not expedition.state.finished else loc('main.campaign_complete'),Vector2(750,970),Vector2(420,65),continue_expedition,true)
		next_button.name = 'ContinueButton'
		if expedition.can_reorganize():
			var regroup=button(ui,tx('领取临时军令 · 每城一次','Temporary order · once per city'),Vector2(700,880),Vector2(520,60),func():
				if expedition.reorganize():render_ui())
			regroup.name='RecoveryOrder';RPGUI.button(regroup,'strip',true)
	elif phase=='battle':
		wave_label = label(ui,'',Vector2(460,82),Vector2(1000,64),23,Color('#ecd08b'))
		wave_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		wave_label.add_theme_color_override('font_shadow_color',Color('#12251e'))
		wave_label.add_theme_constant_override('shadow_offset_x',2)
		wave_label.add_theme_constant_override('shadow_offset_y',2)
		wave_label.tooltip_text=loc('main.between_waves_survivors_recover_50_max_health_minimum_70')
		refresh_wave_label()
		button(ui,'Ⅱ' if not paused else '▶',Vector2(797,975),Vector2(72,60),toggle_pause)
		var elapsed=int(campaign.g.battle.time)
		elapsed_label = label(ui,'%02d:%02d'%[int(elapsed/60.0),elapsed%60],Vector2(880,984),Vector2(140,40),28)
		elapsed_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		button(ui,str(speed)+'×',Vector2(1030,975),Vector2(90,60),change_speed)
	elif has_battle_report():
		var report_button = button(ui,tr_text('View report'),Vector2(790,970),Vector2(340,65),func():open_dialog('result'))
		report_button.name = 'ReportButton'
	toast_label = label(ui,'',Vector2(460,650),Vector2(1000,45),26,Color('#f0d6a2'))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	world.refresh()
	if campaign.g.battle==null and not on_map:
		var progress=int(campaign.g.cities_captured)%int(campaign.camp.expansion_every_victories)
		var status_text=loc('camp.progress')%[campaign.g.unlocked_cells.size(),campaign.camp.max_buildings,campaign.g.cities_captured,int(campaign.camp.expansion_every_victories)-progress,campaign.g.expansion_credits]
		if campaign.g.unlocked_cells.size()==int(campaign.camp.max_buildings): status_text=loc('camp.full')%[campaign.g.unlocked_cells.size(),campaign.g.cities_captured]
		var status=label(ui,status_text,Vector2(1360,155),Vector2(500,140),23,Color('#ecd08b'))
		status.add_theme_color_override('font_shadow_color',Color('#12251e'));status.add_theme_constant_override('shadow_offset_x',2);status.add_theme_constant_override('shadow_offset_y',2)
		var rules_label=label(ui,loc('camp.positions'),Vector2(1360,310),Vector2(500,190),22,Color('#e6d9a6'))
		rules_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		rules_label.add_theme_color_override('font_shadow_color',Color('#12251e'));rules_label.add_theme_constant_override('shadow_offset_x',2);rules_label.add_theme_constant_override('shadow_offset_y',2)
		if phase in ['reward','prepare'] and camp_action=='' and campaign.g.expansion_credits>0:
			var expand_button=button(ui,loc('camp.expand')%campaign.g.expansion_credits,Vector2(1390,520),Vector2(420,65),begin_camp_expansion,true)
			expand_button.name='ExpandCamp'
		camp_preview=label(ui,'',Vector2(1320,600),Vector2(560,65),22,Color('#f0d6a2'))
		camp_preview.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if campaign.g.battle==null and expedition.state.opening!='card':
		world.preview=world.preview.filter(func(unit):return unit.side=='ally')

	save_run()

func card_button(id: String,index: int):
	var data = campaign.cards[id]
	var copy = campaign.card_copy(id,language)
	var rank_text = 'I–III' if campaign.types.has(id) else ['','I','II','III'][campaign.offered_level(id)]
	var preset = Catalog.presentation('card_hand')
	var colors = preset.face_palette
	var origin = Vector2(582+index*258,728)
	var b = Button.new()
	b.position = origin
	b.size = preset.card_size
	b.pivot_offset = b.size/2
	b.focus_mode = Control.FOCUS_NONE
	for state in ['normal','hover','pressed','focus']:
		b.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	b.tooltip_text = copy.detail
	ui.add_child(b)
	var face = CardFace.new()
	face.name = 'CardFrame'
	face.kind = 'Building' if data.kind=='Troop' else data.kind
	face.size = b.size
	b.add_child(face)
	var kind_text = ({'Troop':'军团','Building':'建筑','Permanent':'强化','Battle order':'军令'} if language=='zh' else {'Troop':'TROOP','Building':'FACILITY','Permanent':'UPGRADE','Battle order':'ORDER'})[data.kind]
	card_label(b,'CardKind',kind_text+' · '+rank_text,16,colors.muted)
	deployment_art(b,id,1,CardFace.ICON_RECT)
	card_label(b,'CardTitle',copy.name,25 if language=='zh' else 22,colors.title)
	card_label(b,'CardImpact',copy.impact,28,colors.highlight)
	var desc = card_label(b,'CardDescription',copy.text,15,colors.description)
	desc.add_theme_constant_override('line_spacing',-2)
	desc.size = CardFace.TEXT_RECTS.CardDescription.size
	if is_instance_valid(card_hand): card_hand.add_card(b,id,index)

func deployment_art(parent: Control,id: String,level: int,rect: Rect2):
	if campaign.is_troop(id):
		var art=preload('res://scripts/squad_art.gd').new()
		art.troop_type=id;art.level=level;art.position=rect.position;art.size=rect.size
		parent.add_child(art)
	elif id in ['siege','medic']:
		# Integer asset scale preserves the authored 96-pixel silhouette.
		var art_size=Vector2(192,192) if rect.size.x>=190 else Vector2(96,96)
		picture(parent,'facilities/'+id+'_'+str(level),rect.position+(rect.size-art_size)*.5,art_size)
	else:
		picture(parent,'card_'+id,rect.position,rect.size)

func card_label(card: Button,field: String,value: String,font_size: int,color: Color) -> Label:
	var rect: Rect2 = CardFace.TEXT_RECTS[field]
	var control = label(card,value,rect.position,rect.size,font_size,color)
	control.name = field
	control.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	control.size = rect.size # Reapply after the inherited pixel font replaces the default font.
	return control

func begin_camp_expansion():
	if input_locked or dialog_kind!='' or campaign.g.battle!=null or campaign.g.phase not in ['reward','prepare'] or campaign.g.expansion_credits<=0: return
	camp_action='expand'
	world.selected_cell=-1
	render_ui()

func cancel_camp_action():
	camp_action=''
	moving_building_id=-1
	world.moving_cell=-1
	render_ui()

func begin_reposition():
	var b=campaign.building_at(world.selected_cell)
	if b==null or campaign.g.battle!=null or campaign.g.phase not in ['reward','prepare']: return
	moving_building_id=int(b.id)
	world.moving_cell=int(b.cell)
	close_dialog()
	camp_action='move'
	render_ui()

func refresh_camp_preview():
	if not is_instance_valid(camp_preview): return
	var cell=world.hover_cell
	if not campaign.is_unlocked(cell): camp_preview.text='';return
	var b=campaign.building_at(cell)
	if campaign.g.phase=='place': b={'type':campaign.g.pending,'cell':cell,'level':1}
	elif camp_action=='move':
		var moving=campaign.g.buildings.filter(func(item):return item.id==moving_building_id)
		if not moving.is_empty(): b={'type':moving[0].type,'cell':cell,'level':moving[0].level}
	if b==null: camp_preview.text='';return
	var bonuses=campaign.site_bonuses(b,world.moving_cell if camp_action=='move' else -1)
	camp_preview.text=loc('camp.preview')%[roundi(bonuses.attack*100),roundi(bonuses.health*100)]

func choose_card(id: String):
	if main_menu or input_locked or dialog_kind!='' or camp_action!='' or campaign.g.phase!='reward' or id not in campaign.offers(): return
	input_locked=true
	if is_instance_valid(card_hand): await card_hand.commit(id)
	if campaign.choose(id):
		world.selected_cell = -1
		input_locked=false
		render_ui()
	else: input_locked=false

func skip_supply():
	if input_locked or camp_action!='' or expedition.state.opening!='done': return
	if campaign.skip(): render_ui()
func march():
	continue_expedition()

func continue_expedition():
	if input_locked or dialog_kind!='' or camp_action!='' or campaign.g.phase!='prepare': return
	var destinations = expedition.destinations().filter(func(id):return expedition.can_travel(id))
	expedition_map.view_act = expedition.current_act()
	expedition_map.last_current = expedition.state.current
	expedition_map.selected = destinations[0] if destinations.size()==1 else ''
	expedition_map.history_open = false
	expedition_map.focus_local=true
	open_map()

func open_map():
	if main_menu: return
	if input_locked or dialog_kind!='': return
	expedition.state.mode = 'map'
	accumulator=0
	render_ui()

func show_camp():
	if dialog_kind!='' or input_locked: return
	if expedition.state.opening=='destination': return
	expedition.state.mode = 'battle' if campaign.g.phase=='battle' else 'camp'
	accumulator=0
	render_ui()

func depart_to(id: String):
	if input_locked or dialog_kind!='' or main_menu or not expedition.can_travel(id): return
	departure=preload('res://scripts/expedition_departure.gd').new()
	departure.app=self
	add_child(departure)
	departure.begin(id)

func travel_to(id: String,arrival_call: bool=true):
	if input_locked or dialog_kind!='': return
	var previous_lives=campaign.g.defense
	if not expedition.travel(id): return
	expedition_map.selected = ''
	if campaign.g.phase != 'battle':
		world.clear_battle()
		render_ui()
		if expedition.nodes[id].roster==null:
			sound.play('reward',.7)
			documents.event_city=id
			documents.event_recovered=campaign.g.defense-previous_lives
			open_dialog('event')
		return
	begin_battle_feedback(arrival_call)

func begin_battle_feedback(arrival_call: bool=true):
	paused = false
	accumulator = 0
	hit_stop = 0
	result_delay = -1
	world.clear_battle()
	if arrival_call:
		sound.play('horn')
		sound.play('equip',.7)
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
	sync_music()
	if is_instance_valid(departure): return # No simulation or damage behind the travel/cloud curtain.
	if main_menu:
		return
	if expedition.state.mode == 'map': return
	if dialog_kind!='' or paused: return
	world.tick_environment(delta)
	if toast_time>0:
		toast_time-=delta
		if toast_time<=0 and is_instance_valid(toast_label): toast_label.text=''
	if result_delay>=0:
		result_delay-=delta
		if result_delay<0: open_dialog('result')
	var sim_delta = minf(delta,float(contracts.maximum_delta_seconds))*speed
	if campaign.g.phase=='battle' and hit_stop>0:
		# Freeze attack/walk poses with the existing simulation pause; impact sparks still settle.
		world.tick(0.0,delta)
		hit_stop=maxf(0,hit_stop-delta)
		return
	world.tick(sim_delta if campaign.g.phase=='battle' else delta,delta)
	if campaign.g.phase!='battle': return
	accumulator+=sim_delta
	while accumulator>=float(contracts.simulation_step_seconds) and campaign.g.phase=='battle':
		campaign.step(float(contracts.simulation_step_seconds))
		world.events(campaign.g.battle.events)
		play_events(campaign.g.battle.events)
		accumulator-=float(contracts.simulation_step_seconds)
		if hit_stop>0: break
	refresh_wave_label()
	if campaign.g.phase=='battle' and campaign.g.battle.rest_remaining<=0 and campaign.g.battle.units.any(func(u):return u.side=='ally' and u.hp>0 and u.get('moving',false)):
		sound.play('foot')
	if is_instance_valid(elapsed_label):
		var seconds=int(campaign.g.battle.time)
		elapsed_label.text='%02d:%02d'%[int(seconds/60.0),seconds%60]
	if campaign.g.phase in ['result','defeat']:
		accumulator=0
		sound.play('win' if campaign.g.battle.report.won else 'bad')
		render_ui()
		result_delay=feedback.report_delay_seconds
func sync_music():
	if music==null: return
	var track='camp'
	if main_menu: track='menu'
	elif dialog_kind=='archive': track='archive'
	elif campaign.g.phase in ['battle','result','defeat']:
		var city=expedition.nodes.get(expedition.state.target,{})
		track='boss' if city.get('kind','') in ['boss','final'] else 'battle'
	elif expedition.state.mode=='map': track='map'
	music.play_track(track)
	music.set_quiet((dialog_kind!='' and dialog_kind!='archive') or (not main_menu and (paused or campaign.g.phase in ['result','defeat'])))
	var ambience=''
	if not main_menu and dialog_kind!='archive':
		if expedition.state.mode=='map': ambience='sea'
		elif campaign.g.phase in ['reward','place','prepare']: ambience='fire'
	sound.set_ambience(ambience,dialog_kind!='' or paused)
func refresh_wave_label():
	if not is_instance_valid(wave_label) or campaign.g.battle==null: return
	var b = campaign.g.battle
	if not b.has('waves'): return
	if b.rest_remaining>0:
		wave_label.text=loc('main.wave_d_d_cleared_regroup_1fs_reinforce_and_recover')%[b.wave_index+1,b.waves.size(),b.rest_remaining]
	else:
		wave_label.text=loc('main.city_assault_wave_d_d_repel_every_wave_to')%[b.wave_index+1,b.waves.size()]

func play_events(events: Array):
	for e in events:
		match e.kind:
			'wave_start': sound.play('horn',.6)
			'attack': sound.play('arrow' if e.ranged else 'swing',.6)
			'hit':
				sound.play('shield' if e.absorbed>0 else 'sword',.7)
				if e.get('broken',false): sound.play('break')
			'blast': sound.play('impact',1)
			'death':
				sound.play('kill')
				if prefs.impact: hit_stop=feedback.hit_stop_seconds
				if e.side=='enemy': sound.play('cry',.55)
			'breach': sound.play('bad')

func _input(event):
	if input_locked: return
	# The title menu owns navigation before GUI focus can consume the same key.
	if main_menu and dialog_kind=='' and event is InputEventKey:
		if menu_view.handle_key(event): get_viewport().set_input_as_handled()
		return
	if dialog_kind!='archive': return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_LEFT,KEY_PAGEUP,KEY_RIGHT,KEY_PAGEDOWN]:
			documents.turn_page(-1 if event.keycode in [KEY_LEFT,KEY_PAGEUP] else 1)
			get_viewport().set_input_as_handled()

func _unhandled_input(event):
	if input_locked: return
	if main_menu:
		if event is InputEventKey:
			if event.pressed and not event.echo and event.keycode==KEY_ESCAPE and dialog_kind!='':
				close_dialog()
				get_viewport().set_input_as_handled()
		return
	if expedition.state.mode == 'map':
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			if dialog_kind != '': close_dialog()
			elif expedition_map.selected != '': expedition_map.close_info()
			elif expedition.state.opening=='destination': return_to_menu()
			else: show_camp()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if dialog_kind!='': close_dialog()
			elif camp_action!='': cancel_camp_action()
			else: open_dialog('settings')
		elif dialog_kind=='':
			if event.keycode in [KEY_1,KEY_2,KEY_3] and campaign.g.phase=='reward':
				if is_instance_valid(card_hand): card_hand.set_active(event.keycode-KEY_1)
			elif event.keycode==KEY_SPACE:
				if campaign.g.phase=='battle': toggle_pause()
				elif campaign.g.phase=='prepare': march()
			elif event.keycode==KEY_M:
				prefs.enabled=not prefs.enabled
				apply_prefs()
				save_prefs()
	if dialog_kind!='': return
	if event is InputEventMouseMotion:
		world.hover_cell=world.cell_at(event.position) if campaign.g.battle==null else -1
		refresh_camp_preview()
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and campaign.g.battle==null:
		# Use this click's canvas position; the polled OS cursor can still be at
		# an earlier event when a fast move and click arrive in the same frame.
		var cell=world.cell_at(event.position)
		if cell<0: return
		if camp_action=='expand':
			if campaign.expand(cell):
				cancel_camp_action();sound.play('build');toast(loc('camp.expanded'))
		elif camp_action=='move':
			if campaign.relocate(moving_building_id,cell):
				cancel_camp_action();sound.play('equip');toast(loc('camp.repositioned'))
		elif campaign.g.phase=='place':
			var existing=campaign.building_at(cell)!=null
			if campaign.place(cell):
				sound.play('upgrade' if existing else 'build')
				sound.play('equip',.6)
				world.selected_cell=-1
				render_ui()
			else:
				sound.play('bad',.3)
				toast(tr_text('Cannot build here'))
		elif campaign.building_at(cell)!=null:
			world.selected_cell=cell
			open_dialog('building')
func draw_starting_theater() -> int:
	# Random order, without replacement: all three backgrounds appear per batch.
	# This session-only bag never changes card rolls or a running campaign.
	if starting_theaters.is_empty():
		starting_theaters.assign(Catalog.data('balance/expedition_rules').starting_theaters)
		for i in range(starting_theaters.size()-1,0,-1):
			var other=start_rng.randi_range(0,i)
			var value=starting_theaters[i]
			starting_theaters[i]=starting_theaters[other]
			starting_theaters[other]=value
	return starting_theaters.pop_back()

func start_game():
	if input_locked or (not main_menu and not expedition.state.finished and campaign.g.phase!='defeat'): return
	var already_on_map=expedition_map.is_visible_in_tree()
	has_run=true
	main_menu=false
	restart_expedition(draw_starting_theater())
	if already_on_map: expedition_map.present()

func resume_game():
	if not has_run: return
	close_dialog()
	main_menu=false
	render_ui()

func return_to_menu():
	if is_instance_valid(departure): departure.cancel()
	expedition_map.settle_entry()
	close_dialog()
	main_menu=true
	accumulator=0
	sound.stop()
	render_ui()

func close_dialog():
	documents.cancel_turn()
	if dialog_kind=='archive': expedition_map.history_open=false
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal=null
	dialog_kind=''
	accumulator=0
	sync_music()
	if main_menu and is_instance_valid(menu_view): menu_view.render()
func has_battle_report() -> bool:
	return campaign.g.phase in ['result','defeat'] and campaign.g.battle != null and campaign.g.battle.get('report') != null

func open_dialog(kind: String):
	if input_locked: return
	expedition_map.settle_entry()
	if kind=='result':
		result_delay=-1
		if not has_battle_report(): return
	close_dialog()
	dialog_kind=kind
	sync_music()
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
	if kind=='archive':
		documents.archive_content(panel)
		return
	if kind=='event':
		documents.event_content(panel)
		return
	button(panel,'×',Vector2(642,18),Vector2(56,50),close_dialog)
	match kind:
		'settings': settings_content(panel)
		'music_credits': music_credits_content(panel)
		'build': build_content(panel)
		'result': result_content(panel)
		'building': building_content(panel)
		'new_run':
			panel.add_theme_stylebox_override('panel',RPGUI.box('paper'))
			heading(panel,tx('开始新的远征？','Start a new expedition?'))
			label(panel,tx('当前远征将被新局替换。选择继续游戏可保留进度。','A new run replaces your current expedition. Continue to keep your progress.'),Vector2(60,150),Vector2(600,150),28,ui_preset.rpg_ink)
			var confirm=button(panel,tx('替换并开始','Replace and start'),Vector2(100,420),Vector2(260,65),func():close_dialog();start_game(),true)
			confirm.name='ConfirmNewRun';RPGUI.button(confirm,'strip',true)
			RPGUI.button(button(panel,tx('取消','Cancel'),Vector2(400,420),Vector2(220,65),close_dialog),'strip')
func heading(parent: Node,value: String):
	label(parent,value,Vector2(38,27),Vector2(580,50),34,Color('#293b2f'))
func settings_content(panel: Control):
	heading(panel,tr_text('Settings'))
	label(panel,tr_text('Language'),Vector2(40,104),Vector2(260,40),26,Color('#384832'))
	button(panel,'中文',Vector2(350,95),Vector2(130,54),func():set_language('zh'),language=='zh')
	button(panel,'English',Vector2(500,95),Vector2(165,54),func():set_language('en'),language=='en')
	setting_slider(panel,'Master volume','volume',175)
	setting_slider(panel,'Music volume','music_volume',243)
	setting_check(panel,'Sound effects','enabled',311)
	setting_slider(panel,'War cries','voices',379)
	setting_check(panel,'Impact effects','impact',447)
	label(panel,loc('settings.frame_limit'),Vector2(40,516),Vector2(170,40),25,Color('#384832'))
	for i in SettingsStore.FRAME_LIMITS.size():
		var limit: int=SettingsStore.FRAME_LIMITS[i]
		var caption=loc('settings.unlimited') if limit==0 else str(limit)
		if int(prefs.fps_limit)==limit: caption='✓ '+caption
		var option=button(panel,caption,Vector2(220+i*100,510),Vector2(145 if limit==0 else 90,54),func():set_frame_limit(limit),int(prefs.fps_limit)==limit)
		option.name='FrameLimit_'+str(limit)
		option.focus_mode=Control.FOCUS_ALL
		option.add_theme_stylebox_override('focus',style('gold'))
	label(panel,loc('settings.frame_limit_hint'),Vector2(40,580),Vector2(640,40),20,Color('#384832'))
	var credits=button(panel,loc('settings.music_credits'),Vector2(40,652),Vector2(640,60),func():open_dialog('music_credits'))
	credits.name='MusicCredits'
	credits.focus_mode=Control.FOCUS_ALL
	credits.add_theme_stylebox_override('focus',style('gold'))
	var bottom_y=728
	panel.size.y=816
	if not main_menu and expedition.state.mode=='map' and (expedition.state.finished or expedition.state.opening!='destination'):
		var map_action=expedition_map.navigation_action()
		var context_button=button(panel,map_action.text,Vector2(40,728),Vector2(640,60),func():
			close_dialog()
			map_action.callback.call())
		context_button.name='MapContextAction'
		bottom_y=804
		panel.size.y=892
	panel.position.y=(float(contracts.viewport_size[1])-panel.size.y)*.5
	if not main_menu:
		button(panel,loc('expedition_map.main_menu'),Vector2(40,bottom_y),Vector2(280,60),return_to_menu)
	button(panel,tr_text('Close'),Vector2(380 if not main_menu else 250,bottom_y),Vector2(220,60),close_dialog,true)
func set_frame_limit(value: int):
	if not value in SettingsStore.FRAME_LIMITS: return
	prefs.fps_limit=value
	apply_prefs()
	save_prefs()
	open_dialog('settings')
	modal.get_child(1).get_node('FrameLimit_'+str(value)).grab_focus()
func set_language(value: String):
	language=value
	prefs.language=value
	apply_prefs()
	save_prefs()
	render_ui()
	open_dialog('settings')
func setting_check(panel: Control,title: String,key: String,y: float):
	label(panel,tr_text(title),Vector2(40,y),Vector2(440,40),25,Color('#384832'))
	button(panel,loc('main.on') if prefs[key] else loc('main.off'),Vector2(520,y-5),Vector2(145,52),func():
		prefs[key]=not prefs[key]
		apply_prefs()
		save_prefs()
		open_dialog('settings'),prefs[key])
func setting_slider(panel: Control,title: String,key: String,y: float):
	label(panel,tr_text(title),Vector2(40,y),Vector2(270,40),25,Color('#384832'))
	var slider=HSlider.new()
	slider.name='Volume_'+key
	slider.tooltip_text=tr_text(title)
	slider.position=Vector2(330,y+8)
	slider.size=Vector2(270,40)
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
func music_credits_content(panel: Control):
	heading(panel,loc('settings.music_credits'))
	var copy=RichTextLabel.new()
	copy.name='MusicAttribution'
	copy.position=Vector2(40,100)
	copy.size=Vector2(640,440)
	copy.bbcode_enabled=true
	copy.add_theme_font_size_override('normal_font_size',25)
	copy.add_theme_color_override('default_color',Color('#293b2f'))
	copy.text=''
	for id in music.preset.tracks:
		var track=music.preset.tracks[id]
		copy.text+='[url=%s]%s[/url] — [url=%s]%s[/url]\n'%[track.source,track.title,track.author_url,track.author]
	copy.text+='\n[url=https://creativecommons.org/licenses/by/4.0/]Creative Commons Attribution 4.0 (CC BY 4.0)[/url]\n\n'+loc('settings.music_edits')
	copy.meta_clicked.connect(func(url):OS.shell_open(str(url)))
	panel.add_child(copy)
	var back=button(panel,loc('settings.back'),Vector2(230,560),Vector2(260,58),func():open_dialog('settings'),true)
	back.name='BackToSettings'
	back.focus_mode=Control.FOCUS_ALL
	back.add_theme_stylebox_override('focus',style('gold'))
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
		if campaign.is_troop(b.type):info='  ×%d'%campaign.Formation.count(b.type,int(b.level))+info
		add_build_text(list,tr_text(campaign.types[b.type].name)+' '+['','I','II','III'][int(b.level)]+info,23)
	add_build_text(list,'\n'+tr_text('PERMANENT UPGRADES'),27)
	if campaign.g.upgrades.is_empty(): add_build_text(list,tr_text('No doctrines yet. Your choices last for this campaign.'),20)
	for id in campaign.g.upgrades:
		if campaign.cards[id].kind=='Battle order':continue
		var copy=campaign.card_copy(id,language,campaign.rank(id))
		add_build_text(list,copy.name+' '+['','I','II','III'][campaign.rank(id)]+'\n'+copy.text,22)
	add_build_text(list,'\n'+tr_text('NEXT BATTLE'),27)
	for id in (campaign.g.orders.keys()+campaign.g.temporary_orders.keys()):
		var copy=campaign.card_copy(id,language,campaign.order_rank(id))
		add_build_text(list,copy.name+' '+['','I','II','III'][campaign.order_rank(id)]+' — '+copy.text,22)
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
	panel.add_theme_stylebox_override('panel',RPGUI.box('scroll'))
	panel.size=Vector2(720,740);panel.position=Vector2(600,170)
	var close=panel.get_child(0)
	close.position=Vector2(610,60);close.size=Vector2(48,48)
	RPGUI.button(close,'button')
	label(panel,tx('远征结束' if ended else '城邦已夺取' if report.won else '进攻失利','Campaign ended' if ended else 'City secured' if report.won else 'Attack repelled'),Vector2(90,118),Vector2(540,50),34,ui_preset.rpg_ink)
	label(panel,year_text(),Vector2(90,172),Vector2(540,40),27,Color('#6d5a3c'))
	if report.won: RomanUI.icon(panel,'laurels',Vector2(300,222),Vector2(120,120))
	else: picture(panel,'card_shield' if ended else 'card_legion',Vector2(300,222),Vector2(120,120))
	if report.has('waveCount'):
		var waves_text = label(panel,loc('main.waves_cleared_d_d')%[report.wavesCleared,report.waveCount],Vector2(60,558),Vector2(600,34),24,Color('#344331'))
		waves_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var rows=[['ENEMY LOSSES','%d / %d'%[report.enemyLosses,report.enemyCount]],['SURVIVORS','%d / %d'%[report.surviving,report.deployed]],['CAMP LIVES','%d / %d'%[campaign.g.defense,campaign.camp.max_lives]]]
	for i in rows.size():
		label(panel,tr_text(rows[i][0]),Vector2(90,366+i*58),Vector2(390,45),26,Color('#344331'))
		label(panel,rows[i][1],Vector2(520,366+i*58),Vector2(120,45),29,Color('#71392d'))
	var claim=button(panel,tx('重新远征' if ended else '远征告捷' if report.won and expedition.state.target==expedition.data.final else '领取奖励' if report.won else '整备后再战','New campaign' if ended else 'Victory' if report.won and expedition.state.target==expedition.data.final else 'Claim reward' if report.won else 'Regroup')+' →',Vector2(185,626),Vector2(350,62),advance,true)
	claim.name='ReportContinue'
	RPGUI.button(claim,'strip',true)
func advance():
	if not has_battle_report(): return
	var won=campaign.g.battle.report.won
	close_dialog()
	if campaign.g.phase=='defeat':
		start_game()
		return
	if not expedition.settle(): return
	if not won: expedition.state.mode='camp'
	if won: sound.play('reward')
	world.clear_battle()
	world.selected_cell=-1
	paused=false
	result_delay=-1
	speed=1
	render_ui()
func restart_expedition(first_act: int = 1):
	if input_locked: return
	expedition_map.settle_entry()
	close_dialog()
	main_menu=false
	has_run=true
	campaign.reset()
	expedition.reset(first_act)
	expedition_map.selected=''
	expedition_map.view_act=first_act
	expedition_map.last_current=''
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
	var copy=campaign.card_copy(b.type,language,int(b.level))
	heading(panel,copy.name+' '+['','I','II','III'][int(b.level)])
	deployment_art(panel,b.type,int(b.level),Rect2(265,100,190,190))
	var s=campaign.stats(b)
	var info=copy.text
	if campaign.is_troop(b.type):info+='\n'+('当前人数：' if language=='zh' else 'Troops: ')+str(campaign.Formation.count(b.type,int(b.level)))
	if b.type!='training': info+='\n\n'+tr_text('Health')+'  %d     '%s.hp+tr_text('Attack')+'  %d'%s.attack
	else: info+='\n\n+%d%%'%int(s.bonus*100)
	if b.type=='medic':info+='\n'+('治疗：' if language=='zh' else 'Healing: ')+'%d / %.1fs'%[s.heal,s.interval]
	if b.type!='training':
		var placement=campaign.site_bonuses(b)
		info+='\n'+loc('camp.preview')%[roundi(placement.attack*100),roundi(placement.health*100)]
	var detail=label(panel,info,Vector2(60,300),Vector2(600,225),23,Color('#344331'))
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	detail.size=Vector2(600,225)
	if campaign.g.phase in ['reward','prepare']:
		var move_button=button(panel,loc('camp.move'),Vector2(110,545),Vector2(240,65),begin_reposition,true)
		move_button.name='RepositionBuilding'
		button(panel,tr_text('Close'),Vector2(380,545),Vector2(220,65),close_dialog)
	else: button(panel,tr_text('Close'),Vector2(250,545),Vector2(220,65),close_dialog,true)

func run_smoke_test():
	# Run by the native test harness; normal play never enables this path.
	var saved_prefs=prefs.duplicate(true)
	var before=campaign.g.duplicate(true)
	open_dialog('settings')
	set_language('en')
	assert(campaign.g==before,'Changing language mutated campaign')
	set_language('zh')
	close_dialog()
	assert(expedition.state.mode=='map' and card_hand==null)
	travel_to('246349')
	assert(campaign.g.phase=='battle' and card_hand==null)
	assert(campaign.g.buildings.size()==1 and campaign.g.unlocked_cells.size()==9)
	open_dialog('settings')
	var battle_time=campaign.g.battle.time
	await get_tree().process_frame
	assert(campaign.g.battle.time==battle_time,'Settings must suspend battle')
	close_dialog()
	paused=false
	speed=4
	while campaign.g.phase=='battle':
		campaign.step(float(contracts.simulation_step_seconds))
		world.events(campaign.g.battle.events)
	assert(campaign.g.battle.report.won,'Opening battle should be gentle')
	render_ui()
	open_dialog('result')
	await get_tree().process_frame
	advance()
	assert(campaign.g.round==2 and campaign.g.phase=='reward')
	assert(expedition.state.current=='246349')
	skip_supply()
	assert(expedition.state.mode=='camp')
	open_map()
	assert(expedition.state.mode=='map' and expedition.can_travel('246369'))
	prefs=saved_prefs
	save_prefs()
	sound.stop()
	print('NATIVE UI SMOKE PASSED: settings, language, destination, infantry-only battle, victory reward and next route.')
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
	travel_to('246349')
	campaign.finish(true)
	advance()
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
					var region: Rect2 = CardFace.TEXT_RECTS[String(child.name)]
					assert(child.position.y+child.size.y<=region.end.y+.1,'Card text overlaps next region: '+id+' '+lang+' '+str(child.size))
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
	assert(campaign.place(6))
	world.refresh()
	render_ui()
	await capture_test_image('native-built')
	assert(campaign.g.phase=='prepare')
	continue_expedition()
	travel_to(expedition.destinations()[0])
	assert(campaign.g.phase=='battle')
	sound.enabled=false
	paused=true
	for i in 480:
		campaign.step(float(contracts.simulation_step_seconds))
		world.tick(float(contracts.simulation_step_seconds))
		world.events(campaign.g.battle.events)
	elapsed_label.text='00:08'
	toast_label.text=''
	await capture_test_image('native-battle')
	open_dialog('build')
	await capture_test_image('native-build-panel')
	close_dialog()
	while campaign.g.phase=='battle': campaign.step(float(contracts.simulation_step_seconds))
	render_ui()
	open_dialog('result')
	await capture_test_image('native-result')
	close_dialog()
	prefs=saved_prefs
	sound.stop()
	print('VISUAL TEST PASSED: 48 bilingual cards fit; build, battle, settings and report captured.')
	get_tree().quit()

func loc(id: String) -> String:
	return Catalog.text(id,language)

func run_path() -> String:
	return run_path_override if run_path_override!='' else 'user://expedition.cfg' if settings_path==SettingsStore.DEFAULT_PATH else ''

func load_run():
	if run_path()=='':return
	var data=RunStore.read_run(run_path())
	if data.is_empty():return
	expedition.configure_route(data.first_act)
	campaign.g=data.campaign;expedition.state=data.expedition
	has_run=true;last_saved_run=data.duplicate(true)

func save_run():
	if not has_run or run_path()=='':return
	var data=RunStore.snapshot(campaign,expedition)
	if data==last_saved_run:return
	var error=RunStore.write_run(run_path(),data)
	save_error=error!=OK
	if not save_error:last_saved_run=data
	else:
		push_warning('Expedition save failed: '+error_string(error))
		if is_instance_valid(toast_label):toast(tx('保存失败，请勿退出游戏','Save failed. Keep the game open.'))

func request_new_game():
	if has_run and not expedition.state.finished and campaign.g.phase!='defeat':open_dialog('new_run')
	else:start_game()

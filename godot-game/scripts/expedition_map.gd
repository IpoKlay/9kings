extends Control
const Catalog=preload('res://scripts/data/catalog.gd')
const RPGUI=preload('res://scripts/rpg_ui.gd')
const CityIntel=preload('res://scripts/city_intel_panel.gd')
const PaperWear=preload('res://scripts/map_paper_wear.gd')
const TOOLBAR_Y=44.0
const TOOLBAR_HEIGHT=60.0

class ZoomButton extends Button:
	var glyph='+'
	func _draw():
		# Center the visible strokes, without the font's asymmetric ascent/descent.
		var color_name='font_color'
		match get_draw_mode():
			DRAW_HOVER: color_name='font_hover_color'
			DRAW_PRESSED,DRAW_HOVER_PRESSED: color_name='font_pressed_color'
			DRAW_DISABLED: color_name='font_disabled_color'
		var ink=get_theme_color(color_name)
		var center=size*.5
		draw_rect(Rect2((center-Vector2(7,1)).floor(),Vector2(14,2)),ink)
		if glyph=='+': draw_rect(Rect2((center-Vector2(1,7)).floor(),Vector2(2,14)),ink)

## A native Control scene; textures, paths, buttons and windows all run in Godot.
var app
var selected = ''
var history_open = false
var view_act = 1
var last_current = ''
var act_buttons: Array[Button] = []
var content: Control
var info: Control
var city_buttons: Dictionary = {}
var travel_button: Button
var textures = {}
const Atlas = preload('res://scripts/expedition_atlas.gd')
const Boundary = preload('res://scripts/map_boundary.gd')
var atlas: Control
var map_boundary: Control
var map_layer: Control
var paper_surface: TextureRect
var camera_zoom = Catalog.presentation('atlas').initial_zoom
var camera_center = Vector2(Catalog.data('schema/contracts').map_world_size[0],Catalog.data('schema/contracts').map_world_size[1])*.5
var rendered_act = 0
var origin = Vector2.ZERO
var sea = preload('res://scripts/atlas_sea.gd').new()
var saved_accumulated_input=true
var pins: Control
var briefing_view: Control
var focus_local=true
var full_network=false

func settle_entry():
	if is_instance_valid(pins): pins.settle()
	if app!=null and is_instance_valid(app.sound): app.sound.stop_map_entry()

func present():
	if is_instance_valid(pins): pins.begin(app.sound,RPGUI.reduced_motion())

func on_visibility_changed():
	sync_pointer_input()
	if is_visible_in_tree() and app!=null and not app.main_menu: present()
	else: settle_entry()

func sync_pointer_input():
	Input.use_accumulated_input=false if is_visible_in_tree() and app!=null and not app.main_menu else saved_accumulated_input

func _exit_tree():
	Input.use_accumulated_input=saved_accumulated_input

func _ready():
	saved_accumulated_input=Input.use_accumulated_input
	visibility_changed.connect(on_visibility_changed)
	sync_pointer_input()
	z_index = 30
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	render()
	pins=preload('res://scripts/map_pins.gd').new()
	pins.name='MapPins'
	add_child(pins)

func tex(id: String) -> Texture2D:
	if not textures.has(id): textures[id] = load('res://assets/expedition/'+id+'.png')
	return textures[id]

func paper_texture() -> Texture2D:
	if textures.has('aged_paper'): return textures.aged_paper
	var preset=Catalog.presentation('atlas').boundary
	var dimensions=Vector2i(Vector2(1920,1080)/preset.pixel_step)
	var paper=Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGB8)
	var stains=FastNoiseLite.new()
	stains.seed=int(preset.paper_seed)
	stains.frequency=1.0/preset.paper_stain_scale
	var grain=RandomNumberGenerator.new()
	grain.seed=int(preset.paper_seed)
	# Bake once: fixed pixel pigments, broad age stains and short paper fibres.
	for y in dimensions.y:
		for x in dimensions.x:
			var stain=stains.get_noise_2d(x,y)
			var edge_distance=minf(minf(x,dimensions.x-1-x),minf(y,dimensions.y-1-y))
			var worn=(1.0-clampf(edge_distance/7.0,0,1))*.15
			var tone=.64+stain*.55+grain.randf_range(-.07,.07)-worn
			if grain.randf()<.035: tone-=.20
			var index=clampi(roundi(tone*(preset.paper_palette.size()-1)),0,preset.paper_palette.size()-1)
			paper.set_pixel(x,y,preset.paper_palette[index])
	for i in 1200:
		var p=Vector2i(grain.randi_range(0,dimensions.x-4),grain.randi_range(0,dimensions.y-1))
		var fibre=paper.get_pixelv(p).darkened(.07)
		for dx in grain.randi_range(1,3): paper.set_pixelv(p+Vector2i(dx,0),fibre)
	textures.aged_paper=ImageTexture.create_from_image(paper)
	return textures.aged_paper

func box(id: String = 'panel') -> StyleBoxTexture:
	var s = StyleBoxTexture.new()
	s.texture = tex(id)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: s.set_texture_margin(side,5)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return s

func text(parent: Node,value: String,pos: Vector2,sz: Vector2,font_size: int = 24,color: Color = Color('#2e3830')) -> Label:
	var label=app.label(parent,value,pos,sz,font_size,color)
	# Reapply bounds after font assignment; the default font otherwise leaves a 32px minimum.
	label.size=sz
	return label

func btn(parent: Node,value: String,pos: Vector2,sz: Vector2,callback: Callable,gold: bool = false,paper_style: String = '') -> Button:
	var b: Button = ZoomButton.new() if value in ['−','+'] else Button.new()
	if b is ZoomButton:
		b.glyph=value
		b.tooltip_text=app.loc('expedition_map.zoom_in' if value=='+' else 'expedition_map.zoom_out')
		b.accessibility_name=b.tooltip_text
	else: b.text = value
	b.position = pos
	b.size = sz
	RPGUI.button(b,paper_style if paper_style!='' else 'strip' if sz.x>=120 else 'button',gold)
	var fitted_size=24
	while fitted_size>18 and app.font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,fitted_size).x>sz.x-20:
		fitted_size-=1
	b.add_theme_font_size_override('font_size',fitted_size)
	b.pressed.connect(func():
		app.sound.play('click')
		callback.call())
	parent.add_child(b)
	return b

func toolbar_button(value: String,x: float,width: float,callback: Callable,selected_tab: bool=false,font_size: int=21) -> Button:
	var dimensions=Vector2(width,TOOLBAR_HEIGHT)
	var b=btn(content,value,Vector2(x,TOOLBAR_Y),dimensions,callback,selected_tab,'toolbar' if width>=120 else 'button')
	b.add_theme_font_size_override('font_size',font_size)
	b.size=dimensions # Reapply after the inherited font has established its minimum size.
	return b

func point(id: String) -> Vector2:
	return atlas.markers[id]+origin if is_instance_valid(atlas) else Vector2.ZERO

func show_act(act: int):
	focus_local=false
	view_act = act
	last_current = app.expedition.state.current
	selected = ''
	history_open = false
	rendered_act = 0
	render()

func kind_text(kind: String) -> String:
	return {'home':app.loc('expedition_map.assembly'),'port':app.loc('expedition_map.rest'),
		'event':app.loc('expedition_map.supplies'),'battle':app.loc('expedition_map.battle'),
		'elite':app.loc('expedition_map.elite'),'boss':app.loc('expedition_map.boss'),
		'final':app.loc('expedition_map.final')}[kind]

func navigation_action() -> Dictionary:
	# Context actions live inside the gear's settings panel, leaving the map clear.
	var state=app.expedition.state
	if state.finished:
		return {'text':app.loc('expedition_map.new_campaign'),'callback':app.start_game}
	if state.opening=='destination':
		return {'text':app.loc('expedition_map.main_menu'),'callback':app.return_to_menu}
	if state.opening=='card':
		return {'text':app.loc('expedition_map.back_to_deployment'),'callback':app.show_camp}
	if app.has_battle_report():
		return {'text':app.tr_text('View report'),'callback':func():
			app.show_camp()
			app.open_dialog('result')}
	return {'text':app.loc('expedition_map.back_to_battle') if app.campaign.g.phase=='battle' else app.loc('expedition_map.back_to_camp'),'callback':app.show_camp}

func ui_obstacles() -> Array[Rect2]:
	var regions: Array[Rect2]=[]
	if not is_instance_valid(content) or not is_instance_valid(atlas): return regions
	for child in content.get_children():
		if child is Button or child is Panel or child.name in ['RouteHint','RouteLegend','RouteBriefing']:
			regions.append(Rect2(child.position-atlas.position,child.size).grow(4))
	return regions

func render():
	if app == null: return
	var exp = app.expedition
	var state = exp.state
	var moved = last_current != state.current
	if moved:
		focus_local=true
		view_act = exp.current_act()
		last_current = state.current
	if is_instance_valid(content):
		remove_child(content)
		content.queue_free()
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	city_buttons.clear()
	act_buttons.clear()
	travel_button = null
	var backing = TextureRect.new()
	backing.name='ParchmentBacking'
	backing.texture=paper_texture()
	backing.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	backing.size=Vector2(1920,1080)
	backing.mouse_filter=Control.MOUSE_FILTER_IGNORE
	content.add_child(backing)
	var wear=TextureRect.new()
	wear.name='PaperEdgeWear'
	wear.texture=PaperWear.edge_texture()
	wear.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	wear.size=backing.size
	wear.mouse_filter=Control.MOUSE_FILTER_IGNORE
	backing.add_child(wear)
	map_boundary=Boundary.new()
	map_boundary.name='PixelMapBoundary'
	map_boundary.size=Vector2(1920,1080)
	content.add_child(map_boundary)
	# Keep cached/live terrain in a stationary layer; the paper print shares its world transform.
	map_layer=Control.new()
	map_layer.name='MapSurface'
	map_layer.size=map_boundary.size
	map_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	map_boundary.add_child(map_layer)
	paper_surface=TextureRect.new()
	paper_surface.name='MapPaperSurface'
	paper_surface.texture=PaperWear.texture()
	paper_surface.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	paper_surface.size=map_boundary.size
	paper_surface.mouse_filter=Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(paper_surface)
	atlas=Atlas.new()
	atlas.owner_map=self
	atlas.position=origin
	atlas.size=Vector2(1920,1080)
	map_layer.add_child(atlas)
	var outline=Boundary.new(true)
	outline.name='PixelMapEdge'
	outline.size=map_boundary.size
	content.add_child(outline)
	if focus_local and view_act==exp.current_act():
		atlas.focus_frontier()
		focus_local=false
	elif rendered_act!=view_act:
		atlas.focus_act(view_act)
	elif moved:
		atlas.focus_city(state.current)
	rendered_act=view_act
	if selected!='':
		var p: Vector2=atlas.markers[selected]
		if p.x<100 or p.x>1370 or p.y<100 or p.y>820:
			atlas.focus_city(selected)
	var settings_button=btn(content,'',Vector2(1792,40),Vector2(80,58),func():app.open_dialog('settings'))
	settings_button.name='SettingsButton'
	settings_button.tooltip_text=app.tr_text('Settings')
	settings_button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state_name in ['normal','hover','pressed','disabled','focus']:
		settings_button.add_theme_stylebox_override(state_name,StyleBoxEmpty.new())
	app.RomanUI.on_button(settings_button,'gear')
	# These shortcuts move the camera; all three routes coexist on the same map.
	for act in exp.data.acts:
		var id = int(act.id)
		var stage=exp.stage_order.find(id)
		var caption = '%s  %s  %d/%d'%[['I','II','III'][stage],exp.act_text(id),exp.act_progress(id),exp.data.steps_per_act]
		var tab = toolbar_button(caption,48+stage*372,360,func():show_act(id),view_act==id,20)
		tab.tooltip_text=app.loc('route.tab_tip')
		var route_mark=ColorRect.new()
		route_mark.position=Vector2(21,tab.size.y-8)
		route_mark.size=Vector2(tab.size.x-42,3)
		route_mark.color=Atlas.COLORS[id-1]
		route_mark.mouse_filter=Control.MOUSE_FILTER_IGNORE
		tab.add_child(route_mark)
		act_buttons.append(tab)
	toolbar_button(app.loc('expedition_map.overview'),1164,180,func():
		focus_local=false
		close_info()
		atlas.overview())
	toolbar_button(app.loc('expedition_map.find_legion'),1356,200,func():
		close_info()
		view_act=exp.current_act()
		focus_local=true
		render()
		atlas.focus_frontier())
	toolbar_button('−',1568,64,func():atlas.zoom_at(atlas.size*.5,1.0/1.2)).name='ZoomOut'
	toolbar_button('+',1644,64,func():atlas.zoom_at(atlas.size*.5,1.2)).name='ZoomIn'
	var hint=text(content,exp.route_hint(view_act),Vector2(48,118),Vector2(1340,40),22,Color('#ffebbb'))
	hint.name='RouteHint'
	var legend=text(content,app.loc('route.legend'),Vector2(48,986),Vector2(900,42),20,Color('#e5d7b2'))
	legend.name='RouteLegend'
	for l in [hint,legend]:
		var plate=StyleBoxFlat.new()
		plate.bg_color=Color('#102a2be8');plate.anti_aliasing=false
		plate.set_content_margin_all(6)
		l.add_theme_stylebox_override('normal',plate)
	briefing_view=null
	if view_act==exp.current_act() and not state.finished:
		briefing_view=preload('res://scripts/route_briefing.gd').new()
		briefing_view.name='RouteBriefing'
		briefing_view.map=self
		briefing_view.position=Vector2(1468,126)
		content.add_child(briefing_view)
	if selected != '': render_info()
	# Reserve only real floating controls, so newly exposed map space stays usable.
	atlas.layout()

func select_city(id: String):
	selected = id
	view_act = maxi(1,int(app.expedition.nodes[id].act))
	last_current = app.expedition.state.current
	history_open = false
	app.sound.play('select')
	render()

func close_info():
	selected = ''
	history_open = false
	render()

func render_info():
	var exp = app.expedition
	var n = exp.nodes[selected]
	var known = exp.known(selected)
	var visited = selected in exp.state.visited
	var distance = exp.distances().get(selected,-1)
	var can = exp.can_travel(selected)
	info = CityIntel.new()
	info.position=Vector2(1468,554)
	info.size=Vector2(430,462)
	info.grain=paper_texture()
	content.add_child(info)
	info.name = 'CityInfo'
	var kind = app.loc('expedition_map.legion_camp') if selected==exp.state.current else app.loc('expedition_map.visited') if visited else app.loc('expedition_map.route_closed') if distance<0 else {'home':app.loc('expedition_map.assembly_point'),'port':app.loc('expedition_map.friendly_port'),'event':app.loc('expedition_map.city_event'),'battle':app.loc('expedition_map.battle_2'),'elite':app.loc('expedition_map.elite_battle'),'boss':app.loc('expedition_map.regional_showdown'),'final':app.loc('expedition_map.final_battle')}[n.kind] if known else app.loc('expedition_map.unknown')
	text(info,kind+(' · %d / %d'%[n.step,exp.data.steps_per_act] if n.kind!='home' else ''),Vector2(36,19),Vector2(322,26),18,CityIntel.MUTED)
	var city_name=exp.node_text(n.id)
	var title_size=32
	while title_size>24 and app.font.get_string_size(city_name,HORIZONTAL_ALIGNMENT_LEFT,-1,title_size).x>382: title_size-=1
	text(info,city_name,Vector2(24,54),Vector2(382,44),title_size,CityIntel.INK).name='CityTitle'
	# Latin is useful under Chinese names; in English use the encounter subtitle instead.
	var subtitle=n.latin if city_name.to_lower()!=String(n.latin).to_lower() else exp.node_text(n.id,'title') if known else app.loc('expedition_map.not_yet_scouted')
	if can:
		var from=exp.departure_port() if exp.state.opening=='destination' else exp.state.current
		var choice=exp.choice_text(selected)
		subtitle=app.loc('route.choice')%[choice,app.loc('route.'+exp.march_mode(from,selected)),kind_text(n.kind)] if choice!='' else subtitle+' · '+app.loc('route.'+exp.march_mode(from,selected))
	text(info,subtitle,Vector2(24,100),Vector2(382,24),18,CityIntel.MUTED).name='CitySubtitle'
	var close=CityIntel.CloseButton.new()
	close.name='CloseInfo'
	close.position=Vector2(366,12);close.size=Vector2(44,44)
	close.tooltip_text=app.loc('expedition_map.close_info')
	CityIntel.button(close,false,true)
	close.pressed.connect(func():app.sound.play('cancel');close_info())
	info.add_child(close)
	var wave = exp.encounter(selected) if known else {}
	info.show_stats=not wave.is_empty()
	var intel_heading=app.loc('expedition_map.enemy_forces') if wave.is_empty() else exp.doctrine_text(selected,'name')+' · '+app.loc('expedition_map.first_wave_d_waves_total')%wave.waves.size()
	var heading_size=18
	while heading_size>14 and app.font.get_string_size(intel_heading,HORIZONTAL_ALIGNMENT_LEFT,-1,heading_size).x>382:heading_size-=1
	var heading=text(info,intel_heading,Vector2(24,148),Vector2(382,26),heading_size,CityIntel.RED)
	heading.name='IntelHeading'
	heading.tooltip_text=exp.doctrine_text(selected,'threat')+'\n'+exp.doctrine_text(selected,'advice') if known else ''
	if not wave.is_empty():
		var counts = {}
		for type in wave.roster: counts[type]=counts.get(type,0)+1
		var index=0
		for type in counts:
			var troop_name={'enemy':app.loc('expedition_map.infantry'),'archer':app.loc('expedition_map.archers'),'guard':app.loc('expedition_map.shield_guards'),'cavalry':app.loc('expedition_map.cavalry'),'siege':app.loc('expedition_map.catapults')}[type]
			text(info,troop_name+' ×'+str(counts[type]),Vector2(24+(index%2)*198,178+(index/2)*26),Vector2(184,26),18,CityIntel.INK).name='Enemy_'+type
			index+=1
		text(info,app.loc('expedition_map.health_2f_attack_2f')%[wave.health,wave.attack],Vector2(32,258),Vector2(366,24),18,CityIntel.MUTED).name='IntelStats'
	else:
		var enemy_text=app.loc('expedition_map.no_enemies_peaceful_visit') if known else app.loc('expedition_map.awaiting_scout_reports')+'\n\n'+app.loc('expedition_map.enemies_and_rewards_are_revealed_within_two_stops')
		text(info,enemy_text,Vector2(24,182),Vector2(382,102),18,CityIntel.INK).name='EnemyText'
	var reward=exp.reward_text(selected) if known else app.loc('expedition_map.not_yet_scouted')
	var reward_heading=app.loc('expedition_map.reward_after_capture') if not wave.is_empty() else app.loc('expedition_map.rewards')
	var recovery=app.loc('expedition.legion_life_1_max_3')
	if reward.begins_with(recovery) or (known and n.kind=='elite'):
		reward_heading=app.loc('expedition_map.reward_recovery')
		reward=reward.trim_prefix(recovery)
	if known and n.kind not in ['home','final'] and not (exp.state.opening=='destination' and selected==exp.departure_port()):
		reward=app.loc('routeintel.elite_detail' if n.kind=='elite' else 'routeintel.reward_detail')
	text(info,reward_heading,Vector2(24,306),Vector2(382,28),20,CityIntel.RED).name='RewardHeading'
	text(info,reward,Vector2(24,338),Vector2(382,56),18,CityIntel.INK).name='RewardText'
	var history_button=btn(info,app.loc('expedition_map.history').strip_edges(),Vector2(24,398),Vector2(186,48),func():app.documents.open_archive(selected))
	history_button.name='HistoryButton'
	history_button.add_theme_font_size_override('font_size',20)
	CityIntel.button(history_button)
	app.RomanUI.icon(history_button,'scroll',Vector2(12,10),Vector2(28,28))
	for state in ['normal','hover','pressed','disabled']: history_button.get_theme_stylebox(state).set_content_margin(SIDE_LEFT,44)
	history_button.size=Vector2(186,48)
	travel_button=btn(info,(app.loc('expedition_map.battle_3') if n.roster!=null else app.loc('expedition_map.visit')) if can else app.loc('expedition_map.already_visited') if visited else app.loc('expedition_map.route_closed_2') if distance<0 else app.loc('expedition_map.not_reachable'),Vector2(224,398),Vector2(182,48),func():app.depart_to(selected),true)
	travel_button.name='Travel'
	if can and exp.state.opening=='destination': travel_button.text=app.loc('expedition_map.deploy')
	elif exp.state.opening=='destination' and selected==exp.departure_port(): travel_button.text=app.loc('expedition_map.departure_port')
	travel_button.disabled=not can
	CityIntel.button(travel_button,true)
	var action_size=20
	while action_size>14 and app.font.get_string_size(travel_button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,action_size).x>158: action_size-=1
	travel_button.add_theme_font_size_override('font_size',action_size)
	travel_button.size=Vector2(182,48)

extends Control
const Catalog=preload('res://scripts/data/catalog.gd')
var preset: Dictionary=Catalog.presentation('atlas')
var contracts: Dictionary=Catalog.data('schema/contracts')
## Native draggable geographic canvas. Screen-sized markers remain clickable at every zoom.
var WORLD = Vector2(contracts.map_world_size[0],contracts.map_world_size[1])
static var COLORS = Catalog.presentation('atlas').route_colors
var owner_map
var zoom = preset.initial_zoom
var center = WORLD*.5
var anchors = {}
var buttons = {}
var markers = {}
var names: Array[Label] = []
var drag_start = Vector2.ZERO
var drag_center = Vector2.ZERO
var holding = false
var dragged = false
var layout_pending = false
var elapsed = 0.0
var route_phase = 0
var font: Font
var legion_flag: TextureRect
var sea_surface: TextureRect
var sea_cache: TextureRect
var sea_life: Node2D
var paths: Dictionary=Catalog.data('generated/march_paths')
var route_ink: Dictionary=preset.route_ink
var draw_routes: Array=[]
var label_leaders: Array=[]
var joins: Dictionary={}
var full_network=false
var branch_badges={}

func _ready():
	clip_contents=true
	mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	font=owner_map.app.font
	var data=Catalog.data('generated/atlas_positions')
	for id in data: anchors[id]=Vector2(data[id][0],data[id][1])
	for id in paths.visual_sites: anchors[id]=Vector2(paths.visual_sites[id][0],paths.visual_sites[id][1])
	for branch in owner_map.app.expedition.march_choices.values(): joins[branch.merge]=true
	zoom=owner_map.camera_zoom
	center=owner_map.camera_center
	full_network=owner_map.full_network
	owner_map.sea.setup(owner_map.tex('atlas'))
	owner_map.sea.break_stroke()
	sea_cache=preload('res://scripts/atlas_sea_surface.gd').new()
	sea_cache.name='AtlasSea'
	sea_cache.size=size
	# Both cached and live terrain stay below world-anchored folds and routes.
	owner_map.map_layer.add_child(sea_cache)
	sea_cache.setup(owner_map.tex('atlas'),owner_map.sea)
	sea_surface=sea_cache.source
	sea_life=preload('res://scripts/atlas_sea_life.gd').new()
	sea_life.name='SeaLife'
	add_child(sea_life)
	sea_life.update_time(owner_map.sea.clock,owner_map.RPGUI.reduced_motion())
	mouse_exited.connect(owner_map.sea.break_stroke)
	for n in owner_map.app.expedition.data.nodes:
		var b=Button.new()
		b.name='City_'+n.id
		b.mouse_filter=Control.MOUSE_FILTER_IGNORE
		b.focus_mode=Control.FOCUS_NONE
		for key in ['normal','hover','pressed','focus']: b.add_theme_stylebox_override(key,StyleBoxEmpty.new())
		b.pressed.connect(func():owner_map.select_city(n.id))
		var art=TextureRect.new()
		var exp=owner_map.app.expedition
		art.texture=owner_map.tex(n.kind+'_'+('current' if n.id==exp.state.current else 'visited' if n.id in exp.state.visited else 'idle'))
		art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		art.mouse_filter=Control.MOUSE_FILTER_IGNORE
		b.add_child(art)
		add_child(b)
		buttons[n.id]=b
		var label=Label.new()
		label.add_theme_font_override('font',font)
		label.add_theme_font_size_override('font_size',int(route_ink.label_size))
		label.add_theme_color_override('font_color',Color('#fff0c5'))
		label.add_theme_color_override('font_shadow_color',Color('#152e3c'))
		label.add_theme_constant_override('shadow_offset_x',2)
		label.add_theme_constant_override('shadow_offset_y',2)
		var nameplate=StyleBoxFlat.new()
		nameplate.bg_color=route_ink.nameplate
		nameplate.anti_aliasing=false
		nameplate.set_content_margin_all(4)
		label.add_theme_stylebox_override('normal',nameplate)
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label.text=exp.node_text(n.id)
		label.name='Name_'+n.id
		add_child(label)
		names.append(label)
	owner_map.city_buttons=buttons
	legion_flag=owner_map.app.RomanUI.icon(self,'legion_flag',Vector2.ZERO,Vector2(72,72))
	legion_flag.z_index=1
	legion_flag.material=legion_flag.material.duplicate()
	legion_flag.material.set_shader_parameter('flutter',1.0)
	layout()

func screen_point(id: String) -> Vector2:
	return (anchors[id]-center)*zoom+size*.5

func world_at(p: Vector2) -> Vector2:
	return (p-size*.5)/zoom+center

func clamp_camera():
	var half=size*.5/zoom
	center.x=WORLD.x*.5 if half.x>=WORLD.x*.5 else clampf(center.x,half.x,WORLD.x-half.x)
	center.y=WORLD.y*.5 if half.y>=WORLD.y*.5 else clampf(center.y,half.y,WORLD.y-half.y)

func remember():
	owner_map.camera_zoom=zoom
	owner_map.camera_center=center

func minimum_zoom() -> float:
	# Fill the polygon's height; avoid the old 137px blank strips in overview.
	var image_margin=preset.boundary.inset-preset.boundary.pixel_step
	return maxf(preset.min_zoom,(size.y-image_margin*2)/WORLD.y)

func zoom_at(p: Vector2, factor: float):
	owner_map.sea.break_stroke()
	var before=world_at(p)
	zoom=clampf(zoom*factor,minimum_zoom(),preset.max_zoom)
	center=before-(p-size*.5)/zoom
	clamp_camera()
	layout()

func overview():
	full_network=true
	owner_map.full_network=true
	owner_map.sea.break_stroke()
	zoom=minimum_zoom()
	center=WORLD*.5
	clamp_camera()
	layout()

func focus_act(act: int):
	full_network=true
	owner_map.full_network=true
	owner_map.sea.break_stroke()
	var bounds=Rect2()
	var first=true
	for n in owner_map.app.expedition.data.nodes:
		if n.act!=act: continue
		if first: bounds=Rect2(anchors[n.id],Vector2.ONE); first=false
		else: bounds=bounds.expand(anchors[n.id])
	zoom=clampf(minf((size.x-preset.focus_screen_margin.x)/(bounds.size.x+preset.focus_world_margin.x),(size.y-preset.focus_screen_margin.y)/(bounds.size.y+preset.focus_world_margin.y)),preset.focus_min_zoom,preset.focus_max_zoom)
	center=bounds.get_center()
	clamp_camera()
	layout()

func focus_city(id: String):
	owner_map.sea.break_stroke()
	zoom=maxf(zoom,preset.city_zoom)
	center=anchors[id]
	clamp_camera()
	layout()

func focus_frontier():
	full_network=false
	owner_map.full_network=false
	var exp=owner_map.app.expedition
	var source=exp.departure_port() if exp.state.opening=='destination' else exp.state.current
	var bounds=Rect2(anchors[source],Vector2.ONE)
	for id in exp.destinations(): bounds=bounds.expand(anchors[id])
	var brief=exp.briefing()
	if not brief.is_empty():
		for id in brief.choices: bounds=bounds.expand(anchors[id])
		if brief.merge!='': bounds=bounds.expand(anchors[brief.merge])
	# Keep current, choices and merge inside the map's reading area, left of intel.
	var area=Rect2(130,230,1180,640)
	zoom=clampf(minf(area.size.x/(bounds.size.x+220),area.size.y/(bounds.size.y+190)),minimum_zoom(),minf(2.0,preset.max_zoom))
	center=bounds.get_center()-(area.get_center()-size*.5)/zoom
	clamp_camera()
	layout()

func layout():
	layout_pending=false
	zoom=clampf(zoom,minimum_zoom(),preset.max_zoom)
	clamp_camera()
	remember()
	sea_surface.position=size*.5-center*zoom
	sea_surface.size=WORLD*zoom
	sea_life.position=sea_surface.position
	sea_life.scale=Vector2.ONE*zoom
	owner_map.paper_surface.position=sea_surface.position
	owner_map.paper_surface.size=sea_surface.size
	sea_cache.size=size
	sea_cache.refresh()
	var compact=zoom<preset.compact_below_zoom
	var sz=preset.compact_marker_size if compact else preset.marker_size
	markers.clear()
	for id in anchors: markers[id]=screen_point(id)
	# Separate dense adjacent harbors without moving their geographic anchors.
	# Leaders below show the exact site; only the clickable illustrations move.
	for iteration in int(preset.separation_iterations):
		var changed=false
		var ids=markers.keys()
		for i in ids.size():
			for j in range(i+1,ids.size()):
				var delta: Vector2=markers[ids[j]]-markers[ids[i]]
				var overlap=sz+preset.marker_gap-delta.abs()
				if overlap.x<=0 or overlap.y<=0: continue
				var push=Vector2.ZERO
				if overlap.x<overlap.y: push.x=(overlap.x+.2)*.5*(1 if delta.x>=0 else -1)
				else: push.y=(overlap.y+.2)*.5*(1 if delta.y>=0 else -1)
				markers[ids[i]]-=push
				markers[ids[j]]+=push
				changed=true
		if not changed: break
	var exp=owner_map.app.expedition
	var distances=exp.distances()
	var options=exp.destinations()
	var brief=exp.briefing()
	branch_badges.clear()
	if not brief.is_empty() and brief.choices.size()>1:
		for i in brief.choices.size(): branch_badges[brief.choices[i]]=['A','B'][i]
	for id in buttons:
		var b: Button=buttons[id]
		b.position=markers[id]-sz*.5
		b.size=sz
		b.get_child(0).position=Vector2(2,0)
		b.get_child(0).size=sz-Vector2(4,8)
		b.modulate.a=.28 if not distances.has(id) and not id in exp.state.visited else .65 if exp.nodes[id].act!=owner_map.view_act and id!=exp.state.current else 1.0
		if not full_network and distances.get(id,99)>3 and id!=exp.state.current and id!=owner_map.selected: b.modulate.a=minf(b.modulate.a,.38)
		b.visible=Rect2(Vector2.ZERO,size).intersects(b.get_rect())
	var reserved: Array[Rect2]=owner_map.ui_obstacles()
	for id in buttons:
		if buttons[id].visible: reserved.append(buttons[id].get_rect().grow(20 if branch_badges.has(id) else 3))
	# Give the current city name priority, then fit its standard and other labels.
	legion_flag.visible=false
	label_leaders.clear()
	var ordered=names.duplicate()
	ordered.sort_custom(func(a,b):return label_priority(a)>label_priority(b))
	for label in ordered:
		var id=String(label.name).trim_prefix('Name_')
		label.visible=false
		var n=exp.nodes[id]
		var ready=exp.can_travel(id)
		label.text=exp.node_text(id)
		if branch_badges.has(id): label.text=branch_badges[id]+' · '+label.text
		elif id==exp.state.current: label.text=exp.loc('routeintel.current')+' · '+label.text
		elif not brief.is_empty() and id==brief.merge: label.text=exp.loc('routeintel.toward')+' · '+label.text
		var important=id==owner_map.selected or id==exp.state.current or ready or n.kind in ['boss','final'] or (n.act==owner_map.view_act and (exp.march_choices.has(id) or joins.has(id)))
		if compact and not important: continue
		if not full_network and distances.get(id,99)>3 and id!=exp.state.current and id!=owner_map.selected and n.kind not in ['boss','final']: continue
		if not distances.has(id) and id not in exp.state.visited and id!=owner_map.selected: continue
		label.add_theme_color_override('font_color',route_ink.ready_color if ready else Color('#fff0c5'))
		var width=font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,int(route_ink.label_size)).x+12
		var p: Vector2=markers[id]
		var offsets=[Vector2(-width*.5,sz.y*.5+3),Vector2(-width*.5,-sz.y*.5-36),Vector2(sz.x*.5+8,-16),Vector2(-sz.x*.5-width-8,-16),Vector2(sz.x*.5+6,-sz.y*.5-36),Vector2(-sz.x*.5-width-6,-sz.y*.5-36),Vector2(sz.x*.5+6,sz.y*.5+4),Vector2(-sz.x*.5-width-6,sz.y*.5+4)]
		# Dense ports may occupy every nearby slot. Give actionable names a wider
		# search ring and a leader back to their marker instead of silently hiding them.
		if ready or id==exp.state.current or id==owner_map.selected or branch_badges.has(id):
			for gap in [32,64,96]:
				offsets.append_array([Vector2(-width*.5,sz.y*.5+3+gap),Vector2(-width*.5,-sz.y*.5-36-gap),Vector2(sz.x*.5+8+gap,-16),Vector2(-sz.x*.5-width-8-gap,-16)])
		for offset in offsets:
			var candidate=Rect2(p+offset,Vector2(width,32))
			if not owner_map.map_boundary.label_bounds().encloses(candidate): continue
			if reserved.any(func(r):return r.intersects(candidate)): continue
			label.position=candidate.position
			label.size=candidate.size
			label.visible=true
			reserved.append(candidate.grow(3))
			var nearest=p.clamp(candidate.position,candidate.end)
			if p.distance_to(nearest)>sz.length()*.5+12:
				label_leaders.append([p.snapped(Vector2.ONE*2),nearest.snapped(Vector2.ONE*2)])
			break
		if id==exp.state.current: position_flag(reserved,sz,compact)
	cache_routes(distances)
	queue_redraw()

func cache_routes(distances: Dictionary):
	draw_routes.clear()
	var exp=owner_map.app.expedition
	var preview=exp.preview_edges(owner_map.selected)
	var brief=exp.briefing()
	var local_edges=[]
	if not brief.is_empty() and brief.merge!='':
		for choice in brief.choices:
			local_edges.append(brief.source+'>'+choice)
			local_edges.append(choice+'>'+brief.merge)
	for edge in exp.data.edges:
		var key=edge[0]+'>'+edge[1]
		var past=edge[0] in exp.state.visited and edge[1] in exp.state.visited
		var ready=edge[0]==exp.state.current and exp.can_travel(edge[1])
		if exp.state.opening=='destination': ready=(edge[0]==exp.data.start and edge[1]==exp.departure_port()) or (edge[0]==exp.departure_port() and exp.can_travel(edge[1]))
		# Both ends must remain reachable: a discarded sibling still points at a reachable merge.
		var closed=not past and (not distances.has(edge[0]) or not distances.has(edge[1]))
		var selected=key in preview
		var local_branch=key in local_edges and not closed
		var color=COLORS[maxi(0,int(exp.nodes[edge[1]].act)-1)]
		color=route_ink.selected_color if selected else route_ink.ready_color if ready or local_branch else color
		color.a=.10 if closed else .22 if past else .24 if exp.nodes[edge[1]].act!=owner_map.view_act else .65 if full_network else .18
		if local_branch: color.a=.82
		if ready or selected: color.a=1
		var points=PackedVector2Array()
		for p in paths.edges[key].points: points.append(((Vector2(p[0],p[1])-center)*zoom+size*.5).snapped(Vector2.ONE*route_ink.pixel_step))
		points[0]=markers[edge[0]].snapped(Vector2.ONE*route_ink.pixel_step)
		points[-1]=markers[edge[1]].snapped(Vector2.ONE*route_ink.pixel_step)
		if local_branch:
			var choice=edge[1] if edge[0]==brief.source else edge[0]
			points=separate_branch(points,-1 if brief.choices.find(choice)==0 else 1)
		draw_routes.append({'key':key,'points':points,'color':color,'sea':paths.edges[key].mode=='sea','width':route_ink.ready_width if ready or selected else 6.0 if local_branch else route_ink.future_width,'priority':3 if selected else 2 if ready else 1 if past or local_branch else 0})
	draw_routes.sort_custom(func(a,b):return a.priority<b.priority)

func separate_branch(points: PackedVector2Array,side: int) -> PackedVector2Array:
	# Parallel ink lanes expose shared coastal corridors; march waypoints stay untouched.
	if points.size()==2:
		points=PackedVector2Array([points[0],points[0].lerp(points[1],.2),points[0].lerp(points[1],.8),points[1]])
	var result=points.duplicate()
	for i in range(1,points.size()-1):
		var direction=(points[i+1]-points[i-1]).normalized()
		result[i]=(points[i]+Vector2(-direction.y,direction.x)*side*route_ink.branch_lane_offset).snapped(Vector2.ONE*route_ink.pixel_step)
	return result

func position_flag(reserved: Array[Rect2],marker_size: Vector2,compact: bool):
	var id=owner_map.app.expedition.state.current
	if not buttons[id].visible: return
	var side=48.0 if compact else 72.0
	var up=-marker_size.y/2-side-4
	var left=-marker_size.x/2-side-8
	var right=marker_size.x/2+8
	var bounds=owner_map.map_boundary.label_bounds()
	for offset in [Vector2(-side/2,up),Vector2(right,-side/2),Vector2(left,-side/2),Vector2(-side/2,marker_size.y/2+6),Vector2(left,up),Vector2(right,up),Vector2(-side/2,up-side/2)]:
		var candidate=Rect2((markers[id]+offset).round(),Vector2.ONE*side)
		if not bounds.encloses(candidate) or reserved.any(func(r):return r.intersects(candidate)): continue
		legion_flag.position=candidate.position
		legion_flag.size=candidate.size
		legion_flag.visible=true
		reserved.append(candidate.grow(3))
		return

func label_priority(label: Label) -> int:
	var id=String(label.name).trim_prefix('Name_')
	var exp=owner_map.app.expedition
	return 6 if id==exp.state.current else 5 if id==owner_map.selected else 3 if exp.can_travel(id) else 2 if exp.nodes[id].kind in ['boss','final'] else 1

func _gui_input(event):
	if (event is InputEventMouse or event is InputEventGesture) and not holding and not owner_map.map_boundary.contains_point(event.position):
		owner_map.sea.break_stroke()
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			zoom_at(event.position,1.18 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.18)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
			if event.pressed:
				holding=true
				dragged=false
				drag_start=event.position
				drag_center=center
				mouse_default_cursor_shape=Control.CURSOR_DRAG
			else:
				var was_holding=holding
				holding=false
				mouse_default_cursor_shape=Control.CURSOR_ARROW
				if was_holding and not dragged and event.button_index==MOUSE_BUTTON_LEFT:
					var hit=''
					for id in buttons:
						if buttons[id].visible and buttons[id].get_rect().has_point(event.position):
							hit=id
							break
					if hit=='':
						for label in names:
							if label.visible and label.get_rect().has_point(event.position):
								hit=String(label.name).trim_prefix('Name_');break
					if hit!='':owner_map.select_city(hit)
			accept_event()
	elif event is InputEventMouseMotion:
		var over_city=false
		for b in buttons.values():
			if b.visible and b.get_rect().has_point(event.position): over_city=true;break
		if over_city: owner_map.sea.break_stroke()
		elif owner_map.sea.move_pointer(world_at(event.position)): sea_cache.refresh_if_needed()
		if holding:
			if event.position.distance_to(drag_start)>7: dragged=true
			if dragged:
				center=drag_center-(event.position-drag_start)/zoom
				clamp_camera()
				remember()
				layout_pending=true # Raw pointer events may arrive several times per frame.
				owner_map.sea.break_stroke()
			accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position,event.factor)
		accept_event()
	elif event is InputEventPanGesture:
		owner_map.sea.break_stroke()
		center+=event.delta*30/zoom
		clamp_camera()
		remember()
		layout_pending=true
		accept_event()

func _process(delta):
	if not is_visible_in_tree():
		holding=false
		owner_map.sea.break_stroke()
		return
	if owner_map.app.main_menu or owner_map.app.dialog_kind!='':
		owner_map.sea.break_stroke()
		sea_cache.refresh_if_needed(false,true)
		return
	if layout_pending: layout()
	owner_map.sea.advance(delta)
	sea_life.update_time(owner_map.sea.clock,owner_map.RPGUI.reduced_motion())
	sea_cache.refresh_if_needed(holding and dragged)
	elapsed+=delta
	if elapsed>.45:
		elapsed=0
		route_phase=(route_phase+1)%4
		legion_flag.material.set_shader_parameter('flutter_phase',route_phase*TAU/4)

func draw_corridor(route: Dictionary):
	var color: Color=route.color
	var outline: Color=route_ink.outline
	outline.a=color.a
	var points: PackedVector2Array=route.points
	if route.sea:
		for i in range(1,points.size()):
			if points[i-1].distance_to(points[i])<3: continue
			draw_dashed_line(points[i-1],points[i],outline,route.width+route_ink.outline_extra,12,true)
			draw_dashed_line(points[i-1],points[i],color,route.width,12,true)
	else:
		draw_polyline(points,outline,route.width+route_ink.outline_extra,false)
		draw_polyline(points,color,route.width,false)
	# One direction marker on the longest segment, so coast bends do not fill with arrows.
	var longest=0.0;var start=Vector2.ZERO;var finish=Vector2.ZERO
	for i in range(1,points.size()):
		var length=points[i-1].distance_to(points[i])
		if length>longest: longest=length;start=points[i-1];finish=points[i]
	if longest>50 and (route.priority>0 or full_network):
		var position=start.lerp(finish,.55)
		var direction=(finish-start).normalized();var normal=Vector2(-direction.y,direction.x)
		var triangle=PackedVector2Array()
		for p in [position+direction*12,position-direction*8+normal*8,position-direction*8-normal*8]: triangle.append(p.snapped(Vector2.ONE*2))
		draw_colored_polygon(triangle,outline)
		triangle=PackedVector2Array()
		for p in [position+direction*9,position-direction*5+normal*5,position-direction*5-normal*5]: triangle.append(p.snapped(Vector2.ONE*2))
		draw_colored_polygon(triangle,color)

func _draw():
	if owner_map==null or anchors.is_empty(): return
	# Wind and sea texture share the native map surface below routes/labels.
	var exp=owner_map.app.expedition
	if legion_flag.visible:
		var base=legion_flag.position+legion_flag.size*Vector2(.32,.90)
		if base.distance_to(markers[exp.state.current])>60:
			draw_line(base,markers[exp.state.current],Color('#d9bd7b99'),1)
	for route in draw_routes: draw_corridor(route)
	for leader in label_leaders:
		draw_line(leader[0],leader[1],route_ink.outline,4)
		draw_line(leader[0],leader[1],route_ink.ready_color,2)
	for id in markers:
		var p: Vector2=markers[id]
		var anchor=screen_point(id)
		var n=exp.nodes[id]
		var color=COLORS[maxi(0,int(n.act)-1)]
		if anchor.distance_to(p)>6:
			draw_line(anchor,p,Color('#f4deb6a0'),1)
			draw_rect(Rect2(anchor-Vector2(2,2),Vector2(4,4)),color)
		var current=id==exp.state.current
		var ready=exp.can_travel(id)
		var r: Rect2=buttons[id].get_rect()
		if current or ready or id==owner_map.selected:
			draw_style_box(owner_map.box('gold' if current or id==owner_map.selected else 'panel'),r.grow(2))
		if branch_badges.has(id):
			var tag=Rect2(r.position-Vector2(18,12),Vector2(30,30))
			draw_rect(tag,route_ink.outline)
			draw_rect(tag.grow(-2),route_ink.ready_color)
			draw_string(font,tag.position+Vector2(8,23),branch_badges[id],HORIZONTAL_ALIGNMENT_LEFT,-1,24,route_ink.outline)
		var badge=Vector2(r.position.x+3,r.end.y-12)
		draw_rect(Rect2(badge,Vector2(r.size.x-6,12)),Color('#17394aee'))
		if zoom>=preset.compact_below_zoom:
			var badge_text='⚑' if current else '✓' if id in exp.state.visited else exp.loc('route.merge') if joins.has(id) else exp.loc('route.fork') if exp.march_choices.has(id) else '%02d'%n.step
			if ready and exp.destinations().size()>1: badge_text=['A','B','C'][exp.destinations().find(id)]
			draw_string(font,badge+Vector2(2,11),badge_text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,route_ink.ready_color if ready else color)
		else: draw_rect(Rect2(badge+Vector2(3,4),Vector2(r.size.x-12,3)),color)

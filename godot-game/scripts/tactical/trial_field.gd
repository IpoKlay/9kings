extends Node2D
const PassBattle=preload('res://scripts/tactical/pass_battle.gd')
const SquareBattle=preload('res://scripts/tactical/square_battle.gd')
const Scenery = preload('res://scripts/battle_environment.gd')
const PixelFX = preload('res://scripts/tactical/pixelfx_atlas.gd')
var pixelfx = PixelFX.new()
const PassLayout=preload("res://scenes/battlefields/roman_pass.tscn")
var LANDSCAPE: Rect2
var pass_layout
var environment
var trial
var textures = {}
var regiments: Dictionary={}
var clock = 0.0
var effects: Array = []
var debug_first_contact=false
var clean_capture=false
const Terrain=preload('res://scripts/tactical/pass_terrain.gd')
var characters: Dictionary={}
var animations: Dictionary={}
var apparition_bounds: Dictionary={}
var corpse_parts: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/presentation/corpse_parts.json'))

func _init():
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://data/content/myth_vfx.json'))
	for row in manifest.characters:
		characters[row.id]=row
		animations[row.id]=load(row.art.sprite_frames)
		var sheet: Image=animations[row.id].get_frame_texture('action',0).atlas.get_image()
		var bounds=Rect2()
		for i in 6:
			var frame: AtlasTexture=animations[row.id].get_frame_texture('action',i)
			var used=Rect2(sheet.get_region(Rect2i(frame.region)).get_used_rect())
			used.position+=frame.margin.position
			bounds=used if i==0 else bounds.merge(used)
		apparition_bounds[row.id]=bounds

func ground_transform() -> Transform2D:
	return trial.rules.projection

func project(p: Vector2) -> Vector2:
	return ground_transform()*p

func unproject(p: Vector2) -> Vector2:
	return ground_transform().affine_inverse()*p

func tex(id: String):
	if not textures.has(id): textures[id]=load('res://assets/'+id+'.png')
	return textures[id]
func _ready():
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	load_battlefield()
	var art_kinds=trial.rules.config.types.keys()
	for variant in trial.rules.config.unit_variants.values():
		if variant.has('art') and variant.art not in art_kinds:art_kinds.append(variant.art)
	for kind in art_kinds:
		var art := {}
		for side in ['ally','enemy','stone']:
			art[side]=load('res://assets/rts-armies/%s_%s.png' % [kind,side])
		regiments[kind]=art

func load_battlefield():
	if has_node('RomanSiege'):
		var old=get_node('RomanSiege');remove_child(old);old.queue_free()
	if is_instance_valid(pass_layout):
		remove_child(pass_layout)
		pass_layout.queue_free()
	if trial.rules is SquareBattle:
		pass_layout=preload('res://scripts/tactical/square_field.gd').new()
		pass_layout.trial=trial
		pass_layout.z_index=-2
		add_child(pass_layout)
		LANDSCAPE=pass_layout.landscape_rect
	else:
		pass_layout=PassLayout.instantiate()
		add_child(pass_layout)
		environment=pass_layout.environment
		LANDSCAPE=Rect2(pass_layout.landscape.position,environment.landscape_size)
	if not trial.rules.structures.is_empty():
		var fort=preload('res://scenes/battlefields/roman_siege.tscn').instantiate()
		fort.z_index=-1;add_child(fort)

func advance(dt: float):
	if has_node('RomanSiege'):
		for section in trial.rules.structures:get_node('RomanSiege').get_node(section.id).hits=section.hits
	clock+=dt
	trial.rules.advance_casualties(dt)
	pass_layout.advance(dt)
	for e in effects: e.age+=dt
	effects=effects.filter(func(e):return e.age<e.duration)
	queue_redraw()
func effect(event: Dictionary):
	var e=event.duplicate()
	e.age=0.0
	e.duration=.72 if e.kind=='flanking_charge' else .5
	if e.has('character'):
		e.duration=2.0 if e.character in ['medusa','odysseus'] else 1.0
		for fx in characters[e.character].cast_fx:
			e.duration=maxf(e.duration,float(fx.delay)+(pixelfx.duration(fx.id)-float(fx.start))/float(fx.speed))
	if e.get('mounted_contact',false) and not e.braced:
		var ground: Vector2=e.get('ground_pos',e.pos)
		effects.append({'kind':'hoof_marks','pos':ground,'from':ground+(e.from-e.pos),'age':0.0,'duration':3.6})
	if e.get('mounted_contact',false):
		effects.append({'kind':'wood_chips','pos':e.pos,'axis':project(e.from).direction_to(project(e.pos)),'age':0.,'duration':.22})
	if e.kind=='hoof_dust':e.duration=.22
	if e.kind in ['blink','scythe']:e.duration=.32
	effects.append(e)
	if effects.size()>80: effects.pop_front()
func _draw():
	if trial==null: return
	draw_set_transform(Vector2.ZERO)
	var rules=trial.rules
	if rules.terrain and not rules is SquareBattle:draw_pass_ground()
	draw_set_transform_matrix(ground_transform())
	draw_rect(rules.bounds,Color('#bea36c99'),false,3)
	if rules is PassBattle and not rules is SquareBattle:
		var tint=flag_color(rules)
		draw_circle(rules.flag_center,rules.flag_radius,Color(tint,.16))
		draw_arc(rules.flag_center,rules.flag_radius,0,TAU,48,tint,4)
	if rules.phase=='deploy' or (rules.phase=='battle' and rules.reserve.has(trial.selected)):
		var zone: Rect2=rules.deployment
		draw_rect(zone,Color('#dbc17e14'))
		var corners=[zone.position,Vector2(zone.end.x,zone.position.y),zone.end,Vector2(zone.position.x,zone.end.y)]
		for i in corners.size():
			draw_dashed_line(corners[i],corners[(i+1)%4],Color('#dfc689'),3,14)
	if trial.placing_rank:
		var slots: Dictionary=trial.rank_slots()
		var tint=Color('#d8eaab') if rules.layout_valid(slots) else Color('#ee886a')
		if trial.rank_dragged:draw_dashed_line(trial.rank_start,trial.rank_end,tint,4,14)
		for slot in slots.values():
			draw_rect(Rect2(slot-Vector2(39,28),Vector2(78,56)),tint,false,4)
			draw_circle(slot,5,tint)
	if trial.drawing_wall:
		var layout=trial.wall_preview()
		var tint=Color('#d8eaab') if not layout.is_empty() else Color('#ee886a')
		draw_dashed_line(trial.rank_start,trial.rank_end,tint,3,12)
		var center=(trial.rank_start+trial.rank_end)*.5
		var normal=trial.rank_start.direction_to(trial.rank_end).orthogonal()
		draw_line(center,center+normal*45,tint,3)
		draw_circle(center+normal*45,5,tint)
		for slot in layout.values():draw_arc(slot.goal,10,0,TAU,16,tint,2)
	for squad in rules.alive('ally'):
		if clean_capture or squad.id not in trial.squad_ids:continue
		draw_arc(squad.pos,34 if rules.square_battle else 57,0,TAU,32,Color('#ffe39d99') if rules.square_battle else Color('#ffe39d'),3 if rules.square_battle else 5)
		if squad.order in ['move','attack_move'] and trial.selected!='route':
			draw_dashed_line(squad.pos,squad.destination,Color('#f4da94'),3,12)
			var tail: Vector2=squad.destination
			for point in squad.waypoints:
				draw_dashed_line(tail,point,Color('#f4da94'),3,12)
				tail=point
			draw_arc(tail,14,0,TAU,16,Color('#ffe39d'),3)
		elif squad.order=='attack':
			for enemy in rules.units:
				if enemy.id==squad.target_id and enemy.hp>0:
					draw_arc(enemy.pos,53,0,TAU,24,Color('#e98965'),4)
					break
	for row in rules.Soldiers.members(rules,trial.soldier_ids):
		if clean_capture:break
		var foot: Vector2=rules.Soldiers.ground_position(rules,row.unit,row.slot)
		draw_arc(foot,13,0,TAU,20,Color('#ffe39d'),2)
		if row.actor.has('path') and not row.actor.path.is_empty():
			draw_dashed_line(foot,row.actor.path[0],Color('#f4da94'),2,10)
	draw_set_transform(Vector2.ZERO)
	if trial.drag_select:
		var rect=Rect2(trial.field_point(trial.drag_origin),trial.field_point(trial.drag_end)-trial.field_point(trial.drag_origin)).abs()
		draw_rect(rect,Color('#efcf862b'))
		draw_rect(rect,Color('#ffe39d'),false,2)
	var pass_battle=rules is PassBattle
	if pass_battle:
		draw_oil(rules)
		for squad in rules.alive('ally'):
			if not clean_capture and squad.id in trial.squad_ids:
				var boots=rules.Contact.feet(rules,squad)
				var occupied=PackedVector2Array()
				var scale: float=rules.contact_profiles[squad.kind].scale
				for slot in boots.size():
					if not rules.Contact.present(squad,slot,rules.Contact.count(squad,rules.config.types[squad.kind])):continue
					var foot: Vector2=project(squad.pos)+boots[slot]+rules.Contact.body_shift(squad,slot,rules.elapsed)
					for corner in [Vector2(-9,-5),Vector2(9,-5),Vector2(9,5),Vector2(-9,5)]:occupied.append(foot+corner*scale)
				if occupied.size()>2:draw_polyline(Geometry2D.convex_hull(occupied),Color('#ffe39d88'),2,false)
	for e in effects:
		if clean_capture or e.kind!='hoof_marks':continue
		var pos=project(e.pos)
		var axis=project(e.from).direction_to(pos)
		var fade=1.0-smoothstep(2.3,3.6,e.age)
		for i in 9:
			var offset=axis*(i*10-60)+axis.orthogonal()*((i%3-1)*9)
			var mark=(pos+offset).snapped(Vector2(2,2))
			draw_line(mark-axis*3,mark+axis*4,Color('#533c28')*Color(1,1,1,.67*fade),4)
	draw_casualties(rules)
	draw_regiments(rules,pass_battle)
	var labels=regiment_labels(rules) if not clean_capture else {}
	for u in rules.units:
		if clean_capture or u.hp<=0 or u.get('escaped',false):continue
		var p: Vector2=labels[u.id]
		draw_rect(Rect2(p,Vector2(88,8)),Color('#203638'))
		draw_rect(Rect2(p,Vector2(roundf(88*u.hp/u.max_hp),6)),Color('#d9bc79') if u.side=='ally' else Color('#b45440'))
		if pass_battle:
			var pole=p+Vector2(39,0)
			var flag_color=Color('#ce7653') if u.side=='ally' else Color('#7199aa')
			if u.routing:flag_color=Color('#aaa18c')
			draw_rect(Rect2(pole-Vector2(1,28),Vector2(4,28)),Color('#a38458'))
			draw_rect(Rect2(pole+Vector2(3,-28),Vector2(26,16 if not u.routing else 7)),flag_color)
			if u.general:draw_rect(Rect2(pole+Vector2(10,-24),Vector2(8,8)),Color('#ffdc80'))
			draw_rect(Rect2(p+Vector2(0,10),Vector2(88,4)),Color('#423a32'))
			draw_rect(Rect2(p+Vector2(0,10),Vector2(88*clampf(u.morale/100,0,1),4)),Color('#d3bd79'))
		if not u.get('routing',false):
			draw_front_marker(p+Vector2(108,5),u)
		if u.stun>0:
			for j in 3: draw_rect(Rect2(p+Vector2(25+j*16,-10+(int(clock*8+j)%2)*4),Vector2(6,6)),Color('#fff0ad'))
	if pass_battle and not rules is SquareBattle:
		draw_standard(rules)
		if rules.phase=='battle' and rules.flank_state in ['warning','crossing','divert']:
			var tip=project(rules.flank_entry()).round()
			draw_line(tip,tip-Vector2(0,58),Color('#543323'),7)
			draw_line(tip,tip-Vector2(0,58),Color('#e6bc79'),3)
			draw_colored_polygon(PackedVector2Array([tip+Vector2(0,-58),tip+Vector2(-38,-53),tip+Vector2(0,-36)]),Color('#bd4f37'))
			draw_rect(Rect2(tip+Vector2(-13,-53),Vector2(5,9)),Color('#ffe0a0'))
			var note=trial.words('敌骑集结','Riders forming')
			if rules.flank_state=='crossing':note=trial.words('侧道突击','Flank attack')
			elif rules.flank_state=='divert':note=trial.words('敌骑转攻正面','Riders divert')
			terrain_sign(tip+Vector2(-45,-66),note)
	for volley in rules.volleys:
		if volley.age<volley.get('release_delay',.23):continue
		if volley.kind=='ability_volley':
			var progress:=clampf((volley.age-volley.get('release_delay',.23))/float(volley.flight),0,1)
			var ground: Vector2=project(volley.from).lerp(project(volley.pos),progress)
			var height: float=4.*volley.peak*progress*(1.-progress)
			var arrow: Vector2=ground-Vector2(0,height)
			var velocity: Vector2=(project(volley.pos)-project(volley.from))/volley.flight-Vector2(0,4.*volley.peak*(1.-2.*progress)/volley.flight)
			var direction=velocity.normalized()
			var length=10.*clampf(1.-height/(volley.peak*2.),.4,1.)
			draw_line((arrow-direction*length).round(),arrow.round(),Color('#dfc58d'),2)
			continue
		var arrow: Vector2=project(volley.point)
		if volley.get('projectile_art','')=='sling_stone':
			draw_rect(Rect2(arrow.round()-Vector2(3,3),Vector2(6,6)),Color('#879da6'))
			draw_rect(Rect2(arrow.round()-Vector2(2,3),Vector2(3,2)),Color('#dce0d5'))
		else:
			var direction: Vector2=ground_transform().basis_xform(volley.direction).normalized()
			draw_line((arrow-direction*10).round(),arrow.round(),Color('#dfc58d'),2)
	for shot in rules.stones:
		if shot.age<0:continue
		var t: float=clampf(shot.age/float(shot.get('flight',rules.config.types.siege.flight)),0,1)
		var rock:=project(shot.from).lerp(project(shot.pos),t)-Vector2(0,4.*shot.get('peak',115.)*t*(1.-t))
		draw_rect(Rect2(rock.round()-Vector2(6,6),Vector2(12,10)),Color('#453d33'))
		draw_rect(Rect2(rock.round()-Vector2(4,5),Vector2(7,4)),Color('#b4a384'))
	draw_live_powers()
	# One brief foreground apparition keeps faces readable over dense squads; no input surface.
	for i in range(effects.size()-1,-1,-1):
		if effects[i].has('character') and effects[i].age<1.0:
			draw_apparition(effects[i])
			break
	for e in effects:
		if clean_capture:continue
		var p: Vector2=project(e.pos)
		if e.kind=='blink':
			var step=floori(e.age/.055)
			for origin in [project(e.from),p]:
				for j in 8:
					var delta=Vector2.from_angle(j*TAU/8)*(5+step*4)
					var point=(origin+delta-Vector2(0,20+step*3)).snapped(Vector2(2,2))
					draw_rect(Rect2(point,Vector2(4,6)),Color('#879da6') if step<3 else Color('#344957'))
		elif e.kind=='troll_slam':
			var step=floori(e.age/.06)
			for j in 16:
				var point=project(e.pos+Vector2.from_angle(j*TAU/16)*minf(80.,12.+step*16.)).snapped(Vector2(3,3))
				draw_rect(Rect2(point,Vector2(6,3)),Color('#c3a15a') if step<3 else Color('#75572e'))
		elif e.kind=='shaman_heal':
			var step=floori(e.age/.08)
			var center=(p-Vector2(0,22+step*4)).snapped(Vector2(2,2))
			draw_rect(Rect2(center-Vector2(2,6),Vector2(4,12)),Color('#869864'))
			draw_rect(Rect2(center-Vector2(6,2),Vector2(12,4)),Color('#869864'))
		elif e.kind=='scythe':
			var step=floori(e.age/.055)
			for j in 5:
				var angle: float=e.heading.angle()-PI/4+(j+step)*PI/20
				var point=project(e.pos+Vector2.from_angle(angle)*50).snapped(Vector2(2,2))-Vector2(0,20)
				draw_rect(Rect2(point,Vector2(4,3)),Color('#dce0d5') if step<3 else Color('#879da6'))
		elif e.kind in ['hoof_dust','wood_chips']:
			var axis: Vector2=e.axis
			var step:=floori(e.age/.055)
			for j in 3:
				var pos: Vector2=(p-axis*(step*4+j*2)+axis.orthogonal()*(j-1)*(step+3)).snapped(Vector2(2,2))
				draw_rect(Rect2(pos,Vector2(4,2)),Color('#bda779') if e.kind=='hoof_dust' else Color('#d2b68a'))
		elif e.kind=='arrow':
			var q: Vector2=project(e.from).lerp(p,minf(1,e.age/.35))
			q.y-=sin(minf(1,e.age/.35)*PI)*60
			draw_line(q-Vector2(12,4),q,Color('#f0dab0'),3)
			if pass_battle:
				for lane in [-2,-1,1,2]:
					var shift=Vector2(lane*10,lane*5)
					draw_line(q+shift-Vector2(12,4),q+shift,Color('#dfc58d'),3)
		elif e.kind=='flanking_charge' and e.age<.72:
			var dir=project(e.from).direction_to(p)
			var tip=p.round() if e.has('contact') else (p-dir*(36-floorf(e.age*10)*3)).round()
			var flash=Color('#ffd08a') if e.sector=='side' else Color('#ff976e')
			for offset in [0,12]:
				var center=tip-dir*offset
				var chevron=PackedVector2Array([center-dir*12+dir.orthogonal()*11,center,center-dir*12-dir.orthogonal()*11])
				draw_polyline(chevron,Color('#432b24'),9)
				draw_polyline(chevron,flash,5)
			var label=trial.words('侧击','Flank') if e.sector=='side' else trial.words('背击','Rear')
			terrain_sign(p+Vector2(14,-156),label)
		elif e.kind=='heal':
			var lift:=Vector2(0,42+e.age*32)
			draw_line(p-lift-Vector2(7,0),p-lift+Vector2(7,0),Color('#cae8ae'),4)
			draw_line(p-lift-Vector2(0,7),p-lift+Vector2(0,7),Color('#cae8ae'),4)
		elif e.kind=='arrow_impact' and e.age<.15:
			var chip=Color('#c3a15a') if e.get('blocked',false) else Color('#edcb81')
			for i in 3:draw_rect(Rect2(p+Vector2((i-1)*5,-floor(e.age/.05)*3),Vector2(3,3)),chip)
		elif e.kind=='stone_impact':
			draw_arc(p,8+e.age*58,0,TAU,12,Color(.75,.61,.42,1-e.age*2),3)
		elif e.has('character'):
			draw_cast_fx(e)
		elif e.kind in ['hit','charge'] and e.age<.18:
			var radius=12 if e.kind=='hit' else 40
			draw_line(p-Vector2(radius,12),p+Vector2(radius,-12),Color('#e9d49d'),4)
	if debug_first_contact:
		for u in rules.units:
			if u.has('last_contact'):
				var mark=project(u.last_contact.pos).round()
				draw_circle(mark,8,Color.BLACK,false,4)
				draw_circle(mark,8,Color.CYAN,false,2)
				draw_line(mark-Vector2(10,0),mark+Vector2(10,0),Color.CYAN,2)
	if rules.phase in ['deploy','battle']:
		draw_set_transform_matrix(ground_transform())
		var p: Vector2=trial.pointer.snapped(Vector2(2,2))
		if trial.selected=='blink' and rules.phase=='battle' and not clean_capture:
			var people=rules.Blink.ready(rules,trial.selected_people())
			if not people.is_empty():
				var origin: Vector2=rules.Blink.center(rules,people)
				var color=Color('#879da6') if origin.distance_to(p)<=rules.Blink.RANGE*1.2 else Color('#bd5746')
				draw_arc(origin,rules.Blink.RANGE,0,TAU,64,color,2)
				for row in people:
					var start: Vector2=rules.Soldiers.ground_position(rules,row.unit,row.slot)
					draw_rect(Rect2(start+(p-start).limit_length(rules.Blink.DISTANCE)-Vector2(3,3),Vector2(6,6)),color)
		if trial.selected=='volley' and rules.phase=='battle' and not clean_capture:
			var people=rules.Volley.ready(rules,trial.selected_people())
			if not people.is_empty():
				var origin: Vector2=rules.Volley.center(rules,people)
				var color=Color('#dfbd79') if origin.distance_to(p)<=rules.Volley.RANGE*1.2 and rules.bounds.has_point(p) else Color('#bd5746')
				draw_arc(origin,rules.Volley.RANGE,0,TAU,64,Color('#c5ba85'),2)
				draw_dashed_line(origin,p,color,2,12)
				draw_arc(p,rules.Volley.radius(people.size()),0,TAU,24,color,3)
		if trial.selected=='charge' and rules.phase=='battle' and not clean_capture:
			var people=rules.Soldiers.members(rules,trial.selected_people()).filter(func(row):return rules.Charges.ready(rules,row.unit,row.actor))
			var center=Vector2.ZERO
			for row in people:center+=rules.Soldiers.ground_position(rules,row.unit,row.slot)
			if not people.is_empty():
				center/=people.size()
				var delta=(p-center).limit_length(rules.config.individual_charge.max_range)
				var tip=center+delta;var direction=delta.normalized()
				draw_line(center,tip,Color('#eea875'),2)
				draw_polyline(PackedVector2Array([tip-direction*16+direction.orthogonal()*9,tip,tip-direction*16-direction.orthogonal()*9]),Color('#eea875'),3)
		if trial.selected=='personal_route' and rules.phase=='battle':
			var people=rules.Soldiers.members(rules,trial.soldier_ids)
			if not people.is_empty():
				var origin=Vector2.ZERO
				for row in people:origin+=rules.Soldiers.ground_position(rules,row.unit,row.slot)
				origin/=people.size()
				for point in trial.draft_waypoints:
					draw_dashed_line(origin,point,Color('#f4da94'),2,10);draw_circle(point,5,Color('#ffe39d'));origin=point
				draw_dashed_line(origin,p,Color('#f4da94'),2,10);draw_arc(p,12,0,TAU,20,Color('#ffe39d'),2)
			draw_set_transform(Vector2.ZERO);return
		if trial.selected=='route' and rules.phase=='battle':
			draw_set_transform(Vector2.ZERO)
			for squad in rules.alive('ally'):
				if not clean_capture and squad.id in trial.squad_ids:
					draw_route_arrow(squad)
					break
			return
		if trial.selected=='lightning' and (rules.phase!='battle' or not rules.power_available() or not rules.bounds.has_point(p)):
			draw_set_transform(Vector2.ZERO)
			return
		if trial.selected=='lightning' and rules.deity=='poseidon':
			var q=rules.config.sea_wave
			var origin=rules.wave_start(p)
			draw_rect(Rect2(origin-Vector2(0,q.width/2),Vector2(q.length,q.width)),Color('#83c4c2'),false,3)
			draw_line(origin,origin+Vector2(q.length,0),Color('#ddc88e'),3)
			draw_polyline(PackedVector2Array([origin+Vector2(q.length-24,-16),origin+Vector2(q.length,0),origin+Vector2(q.length-24,16)]),Color('#ddc88e'),4,false)
		elif trial.selected=='lightning' and rules.powers.config.has(rules.deity):
			draw_power_area(rules.powers.area(rules.deity,p),Color('#a7d4bc') if rules.deity=='athena' else Color('#f2da91'))
		elif trial.selected=='lightning':
			var points=PackedVector2Array()
			for i in 33: points.append(p+Vector2(cos(i*TAU/32),sin(i*TAU/32))*float(rules.config.lightning.radius))
			draw_polyline(points,Color('#f2da91'),3,false)
		elif rules.reserve.has(trial.selected) and rules.deployment_valid(p,trial.selected):
			draw_rect(Rect2(p-Vector2(45,30),Vector2(90,60)),Color('#e4d09c'),false,3)

	draw_set_transform(Vector2.ZERO)

# Slots are in projected field pixels. One full infantry block spans about 288 of 1920.
func regiment_bounds(u: Dictionary) -> Rect2:
	var scale=Terrain.layout(u.kind,trial.rules.square_battle).z*u.get('visual_scale',1.)
	var bounds=Rect2()
	var initialized=false
	var slots=trial.rules.Contact.feet(trial.rules,u)
	for i in slots.size():
		if not trial.rules.Contact.present(u,i,trial.rules.Contact.count(u,trial.rules.config.types[u.kind])):continue
		var point=slots[i]+trial.rules.Contact.body_shift(u,i,trial.rules.elapsed)
		var body=Rect2(point-Vector2(18,46)*scale,Vector2(36,52)*scale)
		bounds=body if not initialized else bounds.merge(body)
		initialized=true
	return bounds

func regiment_contains(u: Dictionary,point: Vector2) -> bool:
	var scale=Terrain.layout(u.kind,trial.rules.square_battle).z*u.get('visual_scale',1.)
	var slots=trial.rules.Contact.feet(trial.rules,u)
	var count=trial.rules.Contact.count(u,trial.rules.config.types[u.kind])
	for i in slots.size():
		if not trial.rules.Contact.present(u,i,count):continue
		var foot=slots[i]+trial.rules.Contact.body_shift(u,i,trial.rules.elapsed)
		var pose=reaction_pose(u.get('slot_states',{}).get(i,{}),trial.rules.elapsed,i)
		var local=(point-foot-Vector2(0,pose.get('drop',0.)*scale)).rotated(-pose.get('angle',0.))
		if Rect2(-Vector2(20,48)*scale,Vector2(40,56)*scale).has_point(local):return true
	return point.length()<24

# Close armies share screen space. Put labels above the whole contact, never
# over an opposing soldier's head or the next regiment's strength bar.
func regiment_labels(rules) -> Dictionary:
	var result={}
	var taken: Array[Rect2]=[]
	var living=rules.units.filter(func(u):return u.hp>0 and not u.get('escaped',false))
	var bodies={}
	for u in living:
		var body=regiment_bounds(u)
		body.position+=project(u.pos)
		bodies[u.id]=body
	living.sort_custom(func(a,b):return bodies[a.id].position.y<bodies[b.id].position.y)
	for u in living:
		var p=(project(u.pos)+Vector2(-44,regiment_bounds(u).position.y-18)).round()
		for attempt in 12:
			var box=Rect2(p-Vector2(2,30),Vector2(124,46))
			var blocked=false
			for id in bodies:
				if id!=u.id and box.intersects(bodies[id]):blocked=true;break
			if not blocked:
				for old in taken:
					if box.intersects(old):blocked=true;break
			if not blocked:break
			p.y-=18
		result[u.id]=p
		taken.append(Rect2(p-Vector2(2,30),Vector2(124,46)))
	return result

func mounted_bearing(u: Dictionary,angle: float) -> int:
	return trial.rules.Contact.bearing(u,angle,trial.rules.config.regiment_impact.bearing_hysteresis_degrees)

# Ground shadows and discrete rigid poses retain the source pixel proportions.
func draw_foot_shadow(foot: Vector2,scale: float,mounted: bool=false,alpha: float=1.):
	var width=19 if mounted else 9
	draw_rect(Rect2((foot-Vector2(width,1)*scale).round(),Vector2(width*2,4)*scale),Color(0.10,0.16,0.10,.43*alpha))
	draw_rect(Rect2((foot-Vector2(width-3,3)*scale).round(),Vector2(width*2-6,8)*scale),Color(0.10,0.16,0.10,.22*alpha))

func reaction_pose(state: Dictionary,now: float,slot: int) -> Dictionary:
	if state.is_empty() or not state.has('reaction'):return {}
	var age: float=now-state.get('reaction_start',state.start)
	if age<0 or age>=.8:return {}
	var direction: Vector2=state.get('dir',Vector2.RIGHT)
	var hand=signf(direction.x) if absf(direction.x)>.15 else (-1. if slot%2 else 1.)
	var strength=.30 if state.reaction=='brace' else .35 if state.reaction=='light' else 1.
	# The first simulation step stays in the exact collision pose. Following poses
	# catch the weight, stagger, plant a foot, then stand in the displaced position.
	var angle=0.
	var drop=0.
	var frame=0
	if age>1./60:
		if age<.08:angle=.14;frame=9
		elif age<.18:angle=.36;drop=2;frame=10
		elif age<.35:angle=.48;drop=4;frame=1
		elif age<.52:angle=.25;drop=2;frame=4
		elif age<.68:angle=.12;frame=1
	return {'angle':angle*strength*hand,'drop':roundf(drop*strength),'frame':frame,'flash':age<.055}

func draw_casualties(rules):
	for fallen in rules.casualties:
		var motion=fallen.motion
		var fade:float=motion.opacity()
		if fade<=0:continue
		var foot:Vector2=fallen.foot
		var scale:float=fallen.scale
		var art:String=fallen.get('art',fallen.kind)
		# Corpses never become collision obstacles or continue to deal damage.
		if not clean_capture:
			if motion.pool_radius>0:
				draw_rect(Rect2((foot-Vector2(motion.pool_radius,2)).round(),Vector2(motion.pool_radius*2,4)),Color(.25,.13,.11,fade*.65))
			for drop in motion.blood:
				var p:Vector2=foot+ground_transform().basis_xform(drop.point)
				draw_rect(Rect2(p.round(),Vector2.ONE*maxf(1.,roundf(drop.radius*2))),Color(.30,.12,.10,fade*.8))
		for burst in motion.burst:
			var progress:float=motion.age/1.2
			if progress>=1:continue
			var size:float=maxf(1,roundf(burst.size*(1-progress*.4)))
			draw_rect(Rect2((foot+ground_transform().basis_xform(burst.point)).round(),Vector2.ONE*size),Color(.12,.10,.16,(1-progress)*.55))
		if not corpse_parts.has(art):continue
		var sheet:Texture2D=tex('rts-corpses/'+art+'_'+fallen.side)
		for part in corpse_parts[art][int(fallen.bearing)]:
			var pivot=Vector2(part.pivot[0],part.pivot[1])*scale
			var displacement=Vector2.ZERO
			var rotation=0.
			var a:int=part.bone[0];var b:int=part.bone[1]
			if motion.equipment.has(part.name):
				var e:Dictionary=motion.equipment[part.name]
				displacement=ground_transform().basis_xform(e.point-e.origin)
				rotation=e.angle-e.initial_angle
			elif a<motion.x.size() and b<motion.x.size():
				# Retarget rigid pieces without stretching the approved human proportions.
				displacement=ground_transform().basis_xform((motion.point(a)+motion.point(b)-motion.rest[a]-motion.rest[b])*.5)
				var axis:Vector2=ground_transform().basis_xform(motion.rest[b]-motion.rest[a])
				if axis.length_squared()>.001:rotation=axis.angle_to(ground_transform().basis_xform(motion.point(b)-motion.point(a)))
			else:continue
			draw_set_transform((foot+pivot+displacement).round(),rotation)
			draw_texture_rect_region(sheet,Rect2(-Vector2(64,64)*scale-pivot,Vector2(128,128)*scale),Rect2(int(part.cell)*128,int(fallen.bearing)*128,128,128),Color(.82,.78,.70,fade))
			draw_set_transform(Vector2.ZERO)

func draw_regiments(rules, pass_battle: bool):
	var figures: Array=[]
	for u in rules.units:
		if u.get('escaped',false):continue
		var stats: Dictionary=rules.config.types[u.kind]
		var scale: float=rules.contact_profiles[u.kind].scale*u.get('visual_scale',1.)
		var heading:=ground_transform().basis_xform(u.heading)
		var angle=atan2(heading.x,heading.y)
		var bearing:=mounted_bearing(u,angle) if u.kind=='cavalry' else posmod(roundi(angle/(PI/4)),8)
		var center:=project(u.pos)
		var slots=rules.Contact.feet(rules,u)
		for slot in slots.size():
			if not rules.Contact.drawable(u,slot):continue
			var foot: Vector2=center+slots[slot]+rules.Contact.body_shift(u,slot,rules.elapsed)
			if pass_battle and u.get('routing',false):foot+=Vector2(sin(slot*7.3),cos(slot*4.7))*12
			var distance: float=u.get('slot_distances',{}).get(slot,u.march_distance)
			var speed: float=u.get('slot_speeds',{}).get(slot,1. if u.moving else 0.)
			var walk=speed>.2
			var actor: Dictionary=u.soldiers[slot] if u.has('soldiers') else {}
			var attack_age: float=u.attack_age if u.kind=='medic' else actor.get('attack_age',u.attack_age)
			var attack_duration: float=rules.Soldiers.ATTACK_DURATION if rules.config.types[u.kind].has('individual') else .55
			var mounted_shot: bool=rules.Soldiers.mounted_ranged(u)
			var action: bool=attack_age<attack_duration and (mounted_shot or u.kind!='cavalry' or not walk or u.gait=='impact')
			if actor.is_empty() and u.get('wall_next',0.)>rules.elapsed and not u.get('wall_files',{}).has(slot):action=false
			var frame:=clampi(int(attack_age/attack_duration*8),0,7) if action else floori(8*distance/float(stats.stride))
			var actor_bearing:=bearing
			if (action or actor.has('personal_order')) and actor.has('heading'):
				var direction: Vector2=ground_transform().basis_xform(actor.heading)
				actor_bearing=posmod(roundi(atan2(direction.x,direction.y)/(PI/4)),8)
			var cell=rules.Contact.cell_index(action,walk,frame,slot%4)
			var upper_cell=11 if u.kind=='cavalry' and u.gait=='sprint' else -1
			if mounted_shot and action:
				upper_cell=cell
				cell=rules.Contact.cell_index(false,walk,floori(8*distance/float(stats.stride)),slot%4)
			if actor.has('charge_run'):upper_cell=11
			if rules.shield_active(u,slot) and not action:upper_cell=9
			var tint=Color.WHITE
			var pose: Dictionary={}
			var state: Dictionary=u.get('slot_states',{}).get(slot,{})
			if actor.has('impact_pose') and rules.elapsed-actor.impact_pose.start<.8:state=actor.impact_pose
			if u.kind!='cavalry':
				pose=reaction_pose(state,rules.elapsed,slot)
				if pose.is_empty():
					var motion: Dictionary=u.get('contact_motion',{})
					if motion.get('offsets',{}).has(slot):
						pose=reaction_pose({'reaction':'light','start':motion.start,'dir':Vector2(motion.offsets[slot].x,motion.offsets[slot].y)},rules.elapsed,slot)
			else:
				var contact: Dictionary=u.get('rider_contacts',{}).get(slot,{})
				if not contact.is_empty():
					var age: float=rules.elapsed-contact.start
					if age>=1./60 and age<.16:
						# A short planted stride reads as resistance while nearby riders keep running.
						cell=9 if contact.get('braced',false) else 1
						pose={'angle':-.08*signf(contact.dir.x),'drop':0.,'frame':cell,'flash':false}
			if not pose.is_empty():
				cell=pose.frame
				if pose.flash:tint=Color(1.8,1.7,1.45)
			var texture: Texture2D=regiments[u.get('art',u.kind)].stone if u.petrified>0 else regiments[u.get('art',u.kind)][u.side]
			if u.petrified>0:cell=0;upper_cell=-1;pose={}
			var first: Dictionary=u.get('last_contact',{}) if u.kind=='cavalry' else u.get('contact_motion',{}).get('contact',{})
			if not first.is_empty() and rules.elapsed-first.time<1./60+.00001:
				if u.kind=='cavalry' and slot==first.rider_slot:
					cell=first.rider_cell;upper_cell=first.get('rider_upper_cell',-1);actor_bearing=first.rider_bearing;pose={}
				elif u.kind in ['legion','guard','spear'] and slot==first.defender_slot:
					cell=first.defender_cell;actor_bearing=first.defender_bearing;pose={};tint=Color(1.8,1.7,1.45)
			figures.append({'foot':foot,'scale':scale,'kind':u.kind,'texture':texture,'cell':cell,'upper_cell':upper_cell,'bearing':actor_bearing,'tint':tint,'pose':pose,'dragon_fire':dragon_flame_strength(attack_age) if u.get('archetype','')=='dragon' and u.petrified<=0 else 0.,'heading':actor.get('heading',u.heading)})
	figures.sort_custom(func(a,b):return a.foot.y<b.foot.y)
	for figure in figures:
		var foot: Vector2=figure.foot
		var scale: float=figure.scale
		draw_foot_shadow(foot,scale,figure.kind=='cavalry')
		var pose: Dictionary=figure.pose
		var offset=Vector2(0,pose.get('drop',0.)*scale)
		draw_set_transform((foot+offset).round(),pose.get('angle',0.))
		var dest=Rect2(-Vector2(32,54)*scale,Vector2(64,64)*scale)
		if figure.upper_cell>=0:
			# Only the rider/weapon change pose; horse legs retain distance-based gait.
			draw_texture_rect_region(figure.texture,Rect2(dest.position,Vector2(64,32)*scale),Rect2(figure.upper_cell*64,figure.bearing*64,64,32),figure.tint)
			draw_texture_rect_region(figure.texture,Rect2(dest.position+Vector2(0,32)*scale,Vector2(64,32)*scale),Rect2(figure.cell*64,figure.bearing*64+32,64,32),figure.tint)
		else:
			draw_texture_rect_region(figure.texture,dest,Rect2(figure.cell*64,figure.bearing*64,64,64),figure.tint)
		draw_set_transform(Vector2.ZERO)
		if figure.dragon_fire>0:draw_dragon_flame(foot,figure.heading,scale,figure.dragon_fire,rules.elapsed)

static func dragon_flame_strength(age: float) -> float:
	# Public renderer breath is visual only, active at .12–.76 of the .8s attack.
	return clampf(minf((age-.12)/.20,(.76-age)/.12),0.,1.)

func draw_dragon_flame(foot: Vector2,heading: Vector2,scale: float,power: float,time: float):
	var axis=ground_transform().basis_xform(heading).normalized()
	var mouth=foot+Vector2(axis.x*12,-22+axis.y*6)*scale
	var across=axis.orthogonal();var tick=floori(time/.07)
	# Hard-edged authored pixel bands, not the original procedural glow shader.
	for i in range(9,0,-1):
		var center=mouth+axis*i*3.*scale*power+across*(posmod(tick+i*3,5)-2)*scale
		var width=(1.+i*.55)*scale*power
		var color=Color('#b34f36') if i>6 else Color('#d77c32') if i>3 else Color('#edcb81')
		var size=Vector2.ONE*maxf(3.,roundf(width/3.)*3.)
		draw_rect(Rect2((center-size/2).snapped(Vector2(3,3)),size),color)
		if i<5:draw_rect(Rect2(center.snapped(Vector2(3,3)),Vector2(3,3)),Color('#fff1c4'))

func terrain_sign(pos: Vector2, value: String):
	var font=trial.hint.get_theme_font('font')
	var w=font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
	draw_rect(Rect2(pos-Vector2(5,18),Vector2(w+10,23)),Color('#352f24df'))
	draw_string(font,pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color('#f1dda6'))

func flag_color(rules) -> Color:
	match rules.flag_state:
		'capturing':return Color('#ff8768')
		'contested':return Color('#ffd373')
	return Color('#eac68a')

func draw_standard(rules):
	var top=project(rules.flag_center).round()-Vector2(0,147)
	if rules.flag_state!='secure':
		var bar=top-Vector2(46,23)
		draw_rect(Rect2(bar,Vector2(92,10)),Color('#322925'))
		draw_rect(Rect2(bar+Vector2(2,2),Vector2(roundf(88*rules.capture_time/rules.capture_seconds),6)),flag_color(rules))

func draw_pass_ground():
	terrain_sign(trial.rules.terrain.main_pass.get_center()+Vector2(-37,-10),trial.words('正面通道','Main pass'))
	terrain_sign(trial.rules.terrain.SIDE_GATE.get_center()+Vector2(-37,18),trial.words('侧道','Side pass'))

# Compact bearing pip beside each strength bar, using the sprite's ground projection.
func draw_front_marker(center: Vector2, u: Dictionary):
	var dir=ground_transform().basis_xform(u.heading).normalized()
	var points=PackedVector2Array([(center+dir*13).round(),(center-dir*8+dir.orthogonal()*8).round(),
		(center-dir*8-dir.orthogonal()*8).round()])
	draw_colored_polygon(points,Color('#ffe6ab') if u.side=='ally' else Color('#f6ac89'))
	points.append(points[0])
	draw_polyline(points,Color('#473626'),3)

func draw_route_arrow(squad: Dictionary):
	var origin=project(squad.pos)
	var plan: Dictionary=trial.rules.plan_route(squad,trial.draft_waypoints,trial.pointer)
	var tint=Color('#ffe39d')
	if plan.ok and plan.has('paths'):
		for i in plan.paths.size():
			var row=plan.people[i]
			var foot: Vector2=trial.rules.Soldiers.point(trial.rules,row.unit,row.slot)
			var last=foot
			for stop in plan.paths[i].path:
				var next=project(stop)
				draw_line(last,next,Color('#ffe39d88'),1);last=next
			draw_circle(last,3,tint)
		return
	var start=origin
	for point in plan.points:
		var end=project(point)
		draw_line(start,end,Color('#382f25'),9)
		draw_line(start,end,tint,4)
		if point in trial.draft_waypoints:
			draw_rect(Rect2(end-Vector2(6,6),Vector2(12,12)),tint)
		start=end
	if not plan.ok:
		var stop=project(plan.blocked)
		var red=Color('#ff8467')
		draw_dashed_line(start,stop,red,3,9)
		draw_line(stop-Vector2(10,10),stop+Vector2(10,10),red,5)
		draw_line(stop+Vector2(-10,10),stop+Vector2(10,-10),red,5)
		terrain_sign(stop+Vector2(15,-7),trial.words('此处不可达','Unreachable'))
		return
	var tip=project(trial.pointer)
	var tail=project(plan.points[-2]) if plan.points.size()>1 else origin
	if trial.draft_waypoints.is_empty() and trial.squad_at((tip-trial.camera_offset)*trial.zoom,'ally',true).get('id',-1)==squad.id:
		tail=origin
		tip=origin+ground_transform().basis_xform(squad.heading).normalized()*96
		draw_line(tail,tip,tint,4)
	var dir=tail.direction_to(tip)
	if dir==Vector2.ZERO:return
	var base=tip-dir*minf(24,tail.distance_to(tip)*.5)
	draw_colored_polygon(PackedVector2Array([tip,base+dir.orthogonal()*10,base-dir.orthogonal()*10]),tint)

func draw_oil(rules):
	if trial.oil_index>=0 and rules.phase=='deploy':
		draw_set_transform_matrix(ground_transform())
		draw_rect(Rect2(980,325,380,900),Color('#eda84d25'))
		draw_rect(Rect2(980,325,380,900),Color('#ebc37d'),false,3)
		draw_arc(trial.pointer,161,0,TAU,40,Color('#f5c576'),3)
		draw_set_transform(Vector2.ZERO)
	for b in rules.barrels:
		var p: Vector2=project(b.pos).snapped(Vector2(2,2))
		if b.state in ['burn','ash']:
			draw_set_transform_matrix(ground_transform())
			draw_circle(b.pos,153,Color('#543a2d66'))
			draw_set_transform(Vector2.ZERO)
			if b.state=='burn':
				for i in 7:
					var foot: Vector2=project(b.pos+Vector2(cos(i*2.4),sin(i*2.4))*sqrt(i/6.0)*119)
					draw_set_transform(foot.snapped(Vector2(2,2)),0,Vector2(.46,.46))
					pixelfx.draw(self,'flame-pillar',Vector2.ZERO,fmod(b.age+i*.13,pixelfx.duration('flame-pillar')))
					draw_set_transform(Vector2.ZERO)
			continue
		for offset in [Vector2(-11,1),Vector2(12,-7),Vector2(11,12)]:
			var base=p+offset
			draw_rect(Rect2(base+Vector2(-12,-23),Vector2(24,26)),Color('#472e21'))
			draw_rect(Rect2(base+Vector2(-9,-22),Vector2(18,23)),Color('#b58248'))
			for y in [-18,-6]:draw_rect(Rect2(base+Vector2(-11,y),Vector2(22,4)),Color('#53483d'))
			draw_rect(Rect2(base+Vector2(-6,-26),Vector2(12,4)),Color('#eec56c'))
		if b.state=='arrow':
			var q: Vector2=project(b.from).lerp(p,clampf(b.age/.4,0,1))
			q.y-=sin(b.age/.4*PI)*75
			draw_circle(q,7,Color('#ffa640'))
			draw_circle(q,3,Color('#fff0a2'))

func apparition_alpha(age: float) -> float:
	if age<0 or age>=1.0:return 0.0
	return minf(1,age/.08)*(1-smoothstep(.78,1.0,age))

func apparition_frame(age: float) -> int:
	return clampi(floori(age*6.0),0,5)

func draw_apparition(e: Dictionary):
	var alpha=apparition_alpha(e.age)
	if alpha<=0:return
	var foot: Vector2=project(e.pos)+Vector2(-90,-70)
	if e.character in ['achilles','minotaur']:
		var c=trial.rules.powers.config[e.character]
		var area=trial.rules.powers.area(e.character,e.pos)
		var progress=clampf((e.age-c.windup)/c.travel_seconds,0,1)
		foot=project(area.origin+Vector2(progress*c.length,0))+Vector2(-90,-70)
	var bounds: Rect2=apparition_bounds[e.character]
	var origin=foot-Vector2(384,660)
	origin=origin.clamp(trial.field_point(Vector2(40,180))-bounds.position,trial.field_point(Vector2(1850,880))-bounds.end).snapped(Vector2(2,2))
	# AtlasTexture margins preserve registration of the second sprite-sheet row.
	var frame: Texture2D=animations[e.character].get_frame_texture('action',apparition_frame(e.age))
	draw_texture_rect(frame,Rect2(origin,Vector2(768,768)),false,Color(1,1,1,alpha))

func draw_cast_fx(e: Dictionary):
	var p: Vector2=project(e.pos)
	var fade=1-smoothstep(e.duration-.35,e.duration,e.age)
	if e.character=='poseidon':
		var q=trial.rules.config.sea_wave
		var travel=minf(1,e.age/float(q.travel_seconds))
		# The broad crest's feet travel along the same oblique lane used for hits.
		var foot=project(e.pos+Vector2(travel*q.length,0))
		pixelfx.draw(self,'wave-crash',foot,e.age,fade)
		return
	if e.character=='medusa':
		draw_set_transform_matrix(ground_transform())
		draw_power_area(trial.rules.powers.area('medusa',e.pos),Color(.72,.76,.58,.5*fade))
		draw_set_transform(Vector2.ZERO)
	if e.character in ['athena','demeter']:return
	if e.character=='hephaestus' and e.age>=trial.rules.powers.config.hephaestus.windup:return
	for fx in characters[e.character].cast_fx:
		var age=(e.age-float(fx.delay))*float(fx.speed)+float(fx.start)
		if e.age<float(fx.delay):continue
		var positions=[p]
		for point in positions:
			pixelfx.draw(self,fx.id,point+Vector2(fx.x,fx.y),age,fade)

func draw_power_area(area: Dictionary, color: Color):
	if area.shape=='lane':
		draw_rect(Rect2(area.origin-Vector2(0,area.width/2),Vector2(area.length,area.width)),color,false,3)
		draw_line(area.origin,area.origin+Vector2(area.length,0),color,3)
		draw_polyline(PackedVector2Array([area.origin+Vector2(area.length-24,-16),area.origin+Vector2(area.length,0),area.origin+Vector2(area.length-24,16)]),color,4,false)
		return
	var points=PackedVector2Array()
	if area.shape=='cone':points.append(area.origin)
	for i in 33:
		var angle=lerpf(-area.angle,area.angle,i/32.0) if area.shape=='cone' else i*TAU/32
		points.append((area.origin+Vector2(cos(angle),sin(angle))*area.radius).snapped(Vector2(2,2)))
	if area.shape=='cone':points.append(area.origin)
	draw_polyline(points,color,3,false)

func draw_live_powers():
	var powers=trial.rules.powers
	for zone in powers.zones:
		draw_set_transform_matrix(ground_transform())
		draw_power_area(powers.area('hephaestus',zone.pos),Color(.8,.42,.22,minf(.7,zone.remaining)))
		draw_set_transform(Vector2.ZERO)
		# The native fire stays visible for exactly the live hazard's lifetime.
		var age=.6+fmod(zone.age,1.15)
		pixelfx.draw(self,'flame-pillar',project(zone.pos),age,minf(1,zone.remaining/.5))
	for charge in powers.charges:
		var c=powers.config[charge.character]
		var head=charge.area.origin+Vector2(minf(1,charge.age/c.travel_seconds)*c.length,0)
		var trail=head-Vector2(100,0)
		draw_line(project(trail).snapped(Vector2(2,2)),project(head).snapped(Vector2(2,2)),Color('#eed59c'),6,false)
	for d in powers.decoys:
		if d.hp<=0:continue
		var fade=minf(1,d.remaining/.5)
		for i in 3:
			var point=project(d.pos+Vector2(0,(i-1)*24)).snapped(Vector2(2,2))
			draw_texture_rect_region(regiments.legion.ally,Rect2(point-Vector2(48,81),Vector2(96,96)),Rect2(0,128,64,64),Color(.85,.72,.42,.5*fade))
		var p=project(d.pos)+Vector2(-30,-100)
		draw_rect(Rect2(p,Vector2(60*d.hp/d.max_hp,4)),Color('#d1bb7d'))
	for u in trial.rules.units:
		if u.hp<=0:continue
		var p=project(u.pos)
		if u.shield>0:pixelfx.draw(self,'divine-shield',p,fmod(clock,pixelfx.duration('divine-shield')),minf(1,u.shield/.3))
		if u.rooted>0:
			var age=minf(1.2,powers.config.demeter.duration-u.rooted) if u.rooted>.7 else 1.8+(1-u.rooted/.7)*.85
			pixelfx.draw(self,'root-snare',p,age,minf(1,u.rooted/.15))
		if u.marked>0:
			var ring=PackedVector2Array()
			for i in 17:ring.append((p+Vector2(0,-165)+Vector2(cos(i*TAU/16),sin(i*TAU/16))*20).snapped(Vector2(2,2)))
			draw_polyline(ring,Color('#dde9d0'),4,false)
		if u.poison>0:
			for i in 3:draw_rect(Rect2((p+Vector2(-14+i*14,-155-(int(clock*8+i)%3)*5)).snapped(Vector2(2,2)),Vector2(6,6)),Color('#a2b95c'))
		if u.regen>0:
			var plus=(p+Vector2(50,-160)).snapped(Vector2(2,2))
			draw_rect(Rect2(plus-Vector2(2,8),Vector2(4,16)),Color('#a8d4a2'))
			draw_rect(Rect2(plus-Vector2(8,2),Vector2(16,4)),Color('#a8d4a2'))

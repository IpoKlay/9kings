extends Node2D
const PassBattle=preload('res://scripts/tactical/pass_battle.gd')
const Scenery = preload('res://scripts/battle_environment.gd')
const PixelFX = preload('res://scripts/tactical/pixelfx_atlas.gd')
var pixelfx = PixelFX.new()
const LANDSCAPE=Rect2(-320,-140,3840,2160)
var environment = Scenery.new()
var trial
var textures = {}
var regiments: Dictionary={}
var clock = 0.0
var effects: Array = []
const Terrain=preload('res://scripts/tactical/pass_terrain.gd')
var characters: Dictionary={}
var animations: Dictionary={}
var apparition_bounds: Dictionary={}

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
	environment.landscape_texture=preload('res://assets/environments/iberia-rts.png')
	environment.landscape_size=LANDSCAPE.size
	environment.shore_origin=Vector2(0,1080)
	# Absolute planting positions on this level; canopy sizes use the classic field scale.
	environment.landscape_trees=[Vector3(284,203,155),Vector3(748,242,170),Vector3(1010,212,146),
		Vector3(490,545,164),Vector3(418,591,145),Vector3(532,618,130),
		Vector3(1740,345,158),Vector3(1854,365,139),Vector3(2218,390,166),
		Vector3(3122,680,178),Vector3(3500,850,149),Vector3(2685,1440,161),
		Vector3(3100,1520,177),Vector3(3030,1470,138),Vector3(326,1712,172),
		Vector3(505,2010,158),Vector3(1060,2022,171),Vector3(1930,1850,154)]
	environment.landscape_flags=[Vector2(710,435),Vector2(2650,1220)]
	environment.attach(self)
	for kind in trial.rules.config.types:
		var art := {}
		for side in ['ally','enemy','stone']:
			art[side]=load('res://assets/rts-armies/%s_%s.png' % [kind,side])
		regiments[kind]=art

func advance(dt: float):
	clock+=dt
	environment.tick(dt)
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
	effects.append(e)
	if effects.size()>80: effects.pop_front()
func _draw():
	if trial==null: return
	draw_set_transform(LANDSCAPE.position)
	environment.draw(self,1,LANDSCAPE.position)
	draw_set_transform(Vector2.ZERO)
	var rules=trial.rules
	if rules.terrain:draw_pass_ground()
	draw_set_transform_matrix(ground_transform())
	draw_rect(rules.bounds,Color('#bea36c99'),false,3)
	if rules is PassBattle:
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
	for squad in rules.alive('ally'):
		if squad.id not in trial.squad_ids:continue
		draw_arc(squad.pos,57,0,TAU,32,Color('#ffe39d'),5)
		if squad.order=='move' and trial.selected!='route':
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
	draw_set_transform(Vector2.ZERO)
	if trial.drag_select:
		var rect=Rect2(trial.field_point(trial.drag_origin),trial.field_point(trial.drag_end)-trial.field_point(trial.drag_origin)).abs()
		draw_rect(rect,Color('#efcf862b'))
		draw_rect(rect,Color('#ffe39d'),false,2)
	var pass_battle=rules is PassBattle
	if pass_battle:
		draw_oil(rules)
		for squad in rules.alive('ally'):
			if squad.id in trial.squad_ids:
				var half: Vector2=rules.terrain.extents[squad.kind]
				draw_rect(Rect2(project(squad.pos)-half,half*2),Color('#ffe39d99'),false,3)
	draw_regiments(rules,pass_battle)
	for u in rules.units:
		if u.hp<=0 or u.get('escaped',false):continue
		var p: Vector2=(project(u.pos)+Vector2(-44,regiment_bounds(u).position.y-14)).round()
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
		if u.side=='ally' and u.id in trial.squad_ids and u.obstruction!='':
			var note=trial.words('等待前队','Waiting') if u.obstruction=='queue' else trial.words('敌阵截击','Intercepted')
			terrain_sign(p+Vector2(0,-32),note)
		if u.stun>0:
			for j in 3: draw_rect(Rect2(p+Vector2(25+j*16,-10+(int(clock*8+j)%2)*4),Vector2(6,6)),Color('#fff0ad'))
	if pass_battle:draw_standard(rules)
	for shot in rules.stones:
		var t: float=clampf(shot.age/float(rules.config.types.siege.flight),0,1)
		var rock:=project(shot.from).lerp(project(shot.pos),t)-Vector2(0,18+sin(t*PI)*115)
		draw_rect(Rect2(rock.round()-Vector2(6,6),Vector2(12,10)),Color('#453d33'))
		draw_rect(Rect2(rock.round()-Vector2(4,5),Vector2(7,4)),Color('#b4a384'))
	draw_live_powers()
	# One brief foreground apparition keeps faces readable over dense squads; no input surface.
	for i in range(effects.size()-1,-1,-1):
		if effects[i].has('character') and effects[i].age<1.0:
			draw_apparition(effects[i])
			break
	for e in effects:
		var p: Vector2=project(e.pos)
		if e.kind=='arrow':
			var q: Vector2=project(e.from).lerp(p,minf(1,e.age/.35))
			q.y-=sin(minf(1,e.age/.35)*PI)*60
			draw_line(q-Vector2(12,4),q,Color('#f0dab0'),3)
			if pass_battle:
				for lane in [-2,-1,1,2]:
					var shift=Vector2(lane*10,lane*5)
					draw_line(q+shift-Vector2(12,4),q+shift,Color('#dfc58d'),3)
		elif e.kind=='flanking_charge':
			var dir=project(e.from).direction_to(p)
			var tip=(p-dir*(36-floorf(e.age*10)*3)).round()
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
		elif e.kind=='stone_impact':
			draw_arc(p,8+e.age*58,0,TAU,12,Color(.75,.61,.42,1-e.age*2),3)
		elif e.has('character'):
			draw_cast_fx(e)
		elif e.kind in ['hit','charge'] and e.age<.18:
			var radius=12 if e.kind=='hit' else 40
			draw_line(p-Vector2(radius,12),p+Vector2(radius,-12),Color('#e9d49d'),4)
	if rules.phase in ['deploy','battle']:
		draw_set_transform_matrix(ground_transform())
		var p: Vector2=trial.pointer.snapped(Vector2(2,2))
		if trial.selected=='route' and rules.phase=='battle':
			draw_set_transform(Vector2.ZERO)
			for squad in rules.alive('ally'):
				if squad.id in trial.squad_ids:
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
	var stats: Dictionary=trial.rules.config.types[u.kind]
	var layout:=Terrain.layout(u.kind)
	var rows:=ceili(float(stats.soldiers)/int(stats.files))
	var half:=Vector2(((int(stats.files)-1)*layout.x+(rows-1)*5)*.5,(rows-1)*layout.y*.5)
	return Rect2(-half-Vector2(14,43)*layout.z,half*2+Vector2(28,48)*layout.z)

func draw_regiments(rules, pass_battle: bool):
	var ranks: Array=[]
	for u in rules.units:
		if u.get('escaped',false) or (u.hp<=0 and u.dead_age>4):continue
		var stats: Dictionary=rules.config.types[u.kind]
		var total:=int(stats.soldiers)
		var files:=int(stats.files)
		var depth:=ceili(float(total)/files)
		var count:=maxi(1,ceili(total*u.hp/u.max_hp))
		var layout:=Terrain.layout(u.kind)
		var heading:=ground_transform().basis_xform(u.heading)
		var bearing:=posmod(roundi(atan2(heading.x,heading.y)/(PI/4)),8)
		var texture: Texture2D=regiments[u.kind][u.side]
		var tint:=Color.WHITE
		var action: bool=u.attack_age<.55 and u.hp>0
		var walk: bool=u.moving and u.hp>0
		if u.petrified>0 and u.hp>0:
			texture=regiments[u.kind].stone
			action=false
			walk=false
		if u.hit_age<.12:tint=Color('#fff1b8')
		if u.hp<=0:tint=Color(.55,.4,.3,maxf(0,1-u.dead_age/4))
		var center:=project(u.pos)
		var frame:=clampi(int(u.attack_age/.55*8),0,7) if action else floori(8*u.march_distance/float(stats.stride))
		for rank in ceili(float(count)/files):
			var row_offset:=rank-(depth-1)*.5
			var first:=center+Vector2(-(files-1)*layout.x*.5+row_offset*5,row_offset*layout.y)
			ranks.append({'first':first,'count':mini(files,count-rank*files),'layout':layout,
				'texture':texture,'tint':tint,'bearing':bearing,'frame':frame,
				'action':action,'walk':walk,'rank':rank,'unit':u})
	ranks.sort_custom(func(a,b):return a.first.y<b.first.y)
	for row in ranks:
		var u: Dictionary=row.unit
		var layout: Vector3=row.layout
		for col in int(row.count):
			var phase: int=(col+row.rank*3)%4
			var frame:=0
			if row.action:frame=9+maxi(0,int(row.frame)-(phase%2))
			elif row.walk:frame=1+posmod(int(row.frame)+[0,1,0,-1][phase],8)
			var feet: Vector2=row.first+Vector2(col*layout.x,0)
			if pass_battle and u.get('routing',false):
				feet+=Vector2(sin(col*7.3+row.rank),cos(row.rank*4.7+col))*12
			var dest:=Rect2((feet-Vector2(32,54)*layout.z).round(),Vector2(64,64)*layout.z)
			if u.hp<=0:
				draw_set_transform(feet.round(),PI/2)
				dest.position=-Vector2(32,54)*layout.z
			draw_texture_rect_region(row.texture,dest,Rect2(frame*64,int(row.bearing)*64,64,64),row.tint)
			if u.hp<=0:draw_set_transform(Vector2.ZERO)

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
	var foot=project(rules.flag_center).round()
	var top=foot-Vector2(0,147)
	draw_line(foot,top,Color('#493323'),8)
	draw_line(foot,top,Color('#c39a56'),4)
	draw_rect(Rect2(top+Vector2(-17,10),Vector2(36,44)),Color('#562d27'))
	draw_rect(Rect2(top+Vector2(-14,13),Vector2(30,37)),Color('#a44635'))
	draw_rect(Rect2(top+Vector2(-20,9),Vector2(41,4)),Color('#f3cb78'))
	draw_colored_polygon(PackedVector2Array([top+Vector2(-9,20),top+Vector2(0,24),top+Vector2(9,20),
		top+Vector2(6,28),top+Vector2(2,30),top+Vector2(0,35),top+Vector2(-3,30),top+Vector2(-7,27)]),Color('#f1ce7e'))
	draw_rect(Rect2(top+Vector2(-11,41),Vector2(24,3)),Color('#ddb261'))
	# The eagle finial has stepped wings and a raised head.
	var wing=PackedVector2Array([top+Vector2(-16,-5),top+Vector2(-8,-3),top+Vector2(-3,1),
		top+Vector2(-2,-7),top+Vector2(5,-7),top+Vector2(8,-4),top+Vector2(3,-3),
		top+Vector2(4,0),top+Vector2(16,-6),top+Vector2(12,2),top+Vector2(3,6),
		top+Vector2(3,9),top+Vector2(-2,9),top+Vector2(-3,6),top+Vector2(-12,2)])
	draw_colored_polygon(wing,Color('#f1ce7e'))
	if rules.flag_state!='secure':
		var bar=top-Vector2(46,23)
		draw_rect(Rect2(bar,Vector2(92,10)),Color('#322925'))
		draw_rect(Rect2(bar+Vector2(2,2),Vector2(roundf(88*rules.capture_time/rules.capture_seconds),6)),flag_color(rules))

func draw_pass_ground():
	# Outline sampled from the original Iberian rock bank. Rotate its long axis into the pass.
	var bank=PackedVector2Array([Vector2(8,50),Vector2(29,26),Vector2(61,17),Vector2(88,25),
		Vector2(107,52),Vector2(147,55),Vector2(179,36),Vector2(205,18),Vector2(232,14),
		Vector2(271,31),Vector2(294,37),Vector2(280,59),Vector2(248,70),Vector2(225,90),
		Vector2(185,99),Vector2(156,103),Vector2(128,101),Vector2(94,89),Vector2(60,85),
		Vector2(29,72),Vector2(15,69)])
	var rock_art=environment.landscape_texture
	var uv=PackedVector2Array()
	for vertex in bank:uv.append((Vector2(1950,245)+vertex)/rock_art.get_size())
	for wall: Rect2 in Terrain.ROCKS:
		for flank in 2:
			var poly=PackedVector2Array()
			for vertex in bank:
				var along=(vertex.x-8)/286.0
				var across=(vertex.y-14)/89.0
				if flank==1:along=1.0-along
				poly.append((wall.position+Vector2((flank*.30+across*.70)*wall.size.x,along*wall.size.y)).round())
			draw_polygon(poly,PackedColorArray([Color.WHITE]),uv,rock_art)
	terrain_sign(Vector2(986,600),trial.words('正面通道','Main pass'))
	terrain_sign(Vector2(986,908),trial.words('侧道','Side pass'))

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

extends Node2D
const Catalog=preload('res://scripts/data/catalog.gd')
const Formation=preload('res://scripts/formation.gd')
var field: Dictionary=Catalog.presentation('field')
var camp: Dictionary=Catalog.data('balance/camp')
var feedback: Dictionary=Catalog.presentation('feedback')
## The same isometric projection as the web edition; UI hit tests use its inverse.
const BattleEnvironment = preload('res://scripts/battle_environment.gd')
var environment = BattleEnvironment.new()
var environment_act = 1
var menu_mode = false
var game
var preview: Array = []
var textures = {}
var hover_cell = -1
var selected_cell = -1
var camp_action = ''
var moving_cell = -1
var clock = 0.0
var attack_times = {}
var death_times = {}
var hit_reactions = {}
var impact_marks: Array = []
var feedback_clock = 0.0
var hit_serial = 0
var shake_started = -10.0
var shake_peak = 0.0
var shake_axis = Vector2.RIGHT
var particles: Array = []
var stains: Array = []
var captions: Array = []
var shake = 0.0
var impact = true
var language = 'zh'
var translated = {}
var world_font: Font = preload('res://assets/fonts/game_pixel_font.tres')

func _ready():
	environment.attach(self)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
func tex(id: String):
	if not textures.has(id): textures[id] = load('res://assets/'+id+'.png')
	return textures[id]
func text(s: String) -> String:
	return translated.get(s,s) if language=='zh' else s
func project(x: float,y: float,z: float = 0) -> Vector2:
	return Vector2(field.screen_origin.x+field.projection_x[0]*(x-field.world_origin.x)+field.projection_x[1]*(y-field.world_origin.y),field.screen_origin.y+field.projection_y[0]*(x-field.world_origin.x)+field.projection_y[1]*(y-field.world_origin.y)-z)
func unproject(p: Vector2) -> Vector2:
	var v = p-field.screen_origin
	var det = field.projection_x[0]*field.projection_y[1]-field.projection_x[1]*field.projection_y[0]
	return Vector2(field.world_origin.x+(field.projection_y[1]*v.x-field.projection_x[1]*v.y)/det,field.world_origin.y+(-field.projection_y[0]*v.x+field.projection_x[0]*v.y)/det)
func center(cell: int) -> Vector2:
	return Formation.cell_center(cell)
func cell_at(p: Vector2) -> int:
	var w = unproject(p)
	var col = int(floor((w.x-field.camp_hit_origin.x)/field.camp_spacing.x))
	var row = int(floor((w.y-field.camp_hit_origin.y)/field.camp_spacing.y))
	return row*int(camp.columns)+col if col>=0 and col<camp.columns and row>=0 and row<camp.rows else -1
func cell_shape(cell: int) -> PackedVector2Array:
	var p = center(cell)
	return PackedVector2Array([project(p.x-field.camp_half_size.x,p.y-field.camp_half_size.y),project(p.x+field.camp_half_size.x,p.y-field.camp_half_size.y),project(p.x+field.camp_half_size.x,p.y+field.camp_half_size.y),project(p.x-field.camp_half_size.x,p.y+field.camp_half_size.y)])
func refresh():
	if is_instance_valid(environment.surface): environment.update_surface(self,clampi(environment_act-1,0,2),Vector2.ZERO)
	preview = game.muster()
	queue_redraw()
func clear_battle():
	attack_times.clear()
	death_times.clear()
	hit_reactions.clear()
	impact_marks.clear()
	hit_serial = 0
	particles.clear()
	stains.clear()
	captions.clear()
	shake = 0
	shake_peak = 0
	shake_started = -10.0
func tick_environment(delta):
	environment.tick(delta)
	queue_redraw()

func tick(delta, visual_delta: float = -1.0):
	clock += delta
	var fx_delta: float = delta if visual_delta<0 else visual_delta
	feedback_clock += fx_delta
	shake = maxf(0,shake-fx_delta*feedback.shake_decay)
	for id in hit_reactions.keys():
		if feedback_clock-hit_reactions[id].time>=feedback.recoil_seconds: hit_reactions.erase(id)
	for mark in impact_marks: mark.age += fx_delta
	impact_marks = impact_marks.filter(func(mark):return mark.age<mark.duration)
	for p in particles:
		p.life -= fx_delta
		p.pos += p.velocity*fx_delta
		p.velocity.y += fx_delta*feedback.particle_gravity
	particles = particles.filter(func(p):return p.life>0)
	for c in captions:
		c.life -= delta
		c.pos.y -= delta*feedback.caption_rise_speed
	captions = captions.filter(func(c):return c.life>0)
	queue_redraw()
func pixel_position(p: Vector2) -> Vector2:
	return p.snapped(Vector2.ONE*float(feedback.pixel_step))
func kick(amount: float, direction: float):
	if not impact: return
	if feedback_clock-shake_started<feedback.shake_repeat_gap_seconds and amount<=shake_peak: return
	shake = minf(feedback.shake_limit_pixels,amount)
	shake_peak = shake
	shake_axis = Vector2(direction,.35).normalized()
	shake_started = feedback_clock
func camera_offset() -> Vector2:
	if not impact or menu_mode or shake<=0: return Vector2.ZERO
	var pose=clampi(int((feedback_clock-shake_started)*feedback.shake_pose_fps),0,feedback.shake_poses.size()-1)
	return pixel_position(shake_axis*shake*float(feedback.shake_poses[pose]))
func recoil_offset(id: int) -> Vector2:
	if not impact or not hit_reactions.has(id): return Vector2.ZERO
	var r: Dictionary=hit_reactions[id]
	var age: float=feedback_clock-r.time
	var t=clampf((age-feedback.recoil_hold_seconds)/(feedback.recoil_seconds-feedback.recoil_hold_seconds),0,1)
	return pixel_position(r.offset*(1-t)*(1-t))
func hit_tint(id: int) -> Color:
	if not hit_reactions.has(id): return Color.WHITE
	var r: Dictionary=hit_reactions[id]
	if feedback_clock-r.time>=feedback.hit_flash_seconds: return Color.WHITE
	return feedback.guard_flash_color if r.guard else feedback.hit_flash_color
func add_impact(p: Vector2, kind: String, direction: float):
	if impact_marks.size()>=int(feedback.impact_mark_limit): impact_marks.pop_front()
	impact_marks.append({'pos':pixel_position(p),'kind':kind,'direction':direction,'age':0.0,
		'duration':feedback.blast_mark_seconds if kind=='blast' else feedback.impact_mark_seconds})
func draw_impacts():
	for mark in impact_marks:
		var pose=int(mark.age*feedback.impact_pose_fps)
		var p: Vector2=mark.pos
		if mark.kind=='blast':
			var radius: float=12.0+pose*6.0
			var dust=Color('#c6af76') if pose<3 else Color('#887858')
			for direction in [-1,1]:
				draw_line(p+Vector2(direction*radius,-4),p+Vector2(direction*(radius+8),0),dust,2)
				draw_line(p+Vector2(direction*(radius+8),0),p+Vector2(direction*radius,4),dust,2)
			if pose<2:draw_rect(Rect2(p-Vector2(4,4),Vector2(8,8)),Color('#e1cf94'))
		elif mark.kind in ['guard','break']:
			var r: float=6.0+mini(pose,2)*2.0
			var ink=Color('#e1cf94') if mark.kind=='break' else Color('#b8cbd1')
			var x: float=mark.direction*r
			draw_line(p+Vector2(x,-r),p+Vector2(x+mark.direction*4,-r+4),ink,2)
			draw_line(p+Vector2(x,r),p+Vector2(x+mark.direction*4,r-4),ink,2)
			if pose<2:draw_line(p+Vector2(x+mark.direction*4,-r+4),p+Vector2(x+mark.direction*4,r-4),ink,2)
			if mark.kind=='break':
				for direction in [-1,1]:draw_rect(Rect2(p+Vector2(direction*(8+pose*4),-8-pose*2),Vector2(4,2)),ink)
		else:
			var r: float=8.0 if pose<2 else 12.0
			var ink=Color('#eee1b5') if pose<2 else Color('#b7754a')
			var d: float=mark.direction
			# Four hard-edged fragments leave the body visible between the rays.
			for sign_x in [-1,1]:
				for sign_y in [-1,1]:
					var a=p+Vector2(sign_x*(r-4),sign_y*(r-4)*.5)
					var b=p+Vector2(sign_x*r,sign_y*r*.5)
					draw_line(pixel_position(a),pixel_position(b),ink,2)
			if pose==0:draw_line(p-Vector2(4*d,6),p+Vector2(4*d,4),ink,2)
func troop_offset(u: Dictionary, index: int) -> Vector2:
	var count=int(u.get('soldierCount',5 if u.type=='cavalry' else 3 if u.type=='medic' else 9))
	var p=Formation.offset(u.type,index,count,u.get('testudo',false))*float(field.troop_scale)
	p.x *= 1.0 if u.side=='ally' else -1.0
	return p
func troop_extent_y(type: String, count: int, testudo: bool=false) -> float:
	var corner=Formation.offset(type,0,count,testudo)*float(field.troop_scale)
	return absf(corner.x*field.projection_y[0])+absf(corner.y*field.projection_y[1])
func receive_hit(e: Dictionary):
	# A shield break must stay readable even directly after a routine hit.
	if not e.get('broken',false) and hit_reactions.has(e.id) and feedback_clock-hit_reactions[e.id].time<feedback.hit_repeat_gap_seconds: return
	var u: Dictionary={}
	if game.g.battle!=null and int(e.id)>=0 and int(e.id)<game.g.battle.units.size(): u=game.g.battle.units[int(e.id)]
	var guard: bool=e.absorbed>0
	var heavy: bool=e.get('broken',false) or e.damage>=float(u.get('maxHp',200))*feedback.heavy_hit_hp_fraction
	var direction: float=1.0 if e.side=='enemy' else -1.0
	var recoil: float=feedback.heavy_recoil_pixels if heavy else feedback.hit_recoil_pixels
	hit_reactions[e.id]={'time':feedback_clock,'guard':guard,'offset':Vector2(direction,.35).normalized()*recoil}
	# Put the contact on a front-rank soldier, not below the centre of the whole formation.
	var formation_offset=Vector2.ZERO
	if not u.is_empty() and u.type!='siege':
		var count=int(u.get('soldierCount',5 if u.type=='cavalry' else 3 if u.type=='medic' else 9))
		var columns=2 if u.type=='cavalry' else 3
		var row=hit_serial%int(ceil(count/float(columns)))
		formation_offset=troop_offset(u,row*columns)
	var contact_height=26.0*(1.0 if u.get('type','')=='siege' else float(field.troop_scale))
	var p=project(595+e.x*.91+formation_offset.x,475+e.y*.9+formation_offset.y,contact_height)
	add_impact(p,'break' if e.get('broken',false) else 'guard' if guard else 'hit',direction)
	burst(p,Color('#e1cf94') if guard else Color('#9f3e35'),int(feedback.guard_particles if guard else feedback.hit_particles))
	hit_serial += 1
func burst(p: Vector2,color: Color,count: int):
	for i in count:
		if particles.size()>=feedback.particle_limit: particles.pop_front()
		particles.append({'pos':p,'velocity':Vector2(randf_range(feedback.particle_velocity_x[0],feedback.particle_velocity_x[1]),randf_range(feedback.particle_velocity_y[0],feedback.particle_velocity_y[1])),'life':randf_range(feedback.particle_lifetime[0],feedback.particle_lifetime[1]),'color':color,'size':randf_range(feedback.particle_size[0],feedback.particle_size[1])})
func events(items: Array):
	for e in items:
		if e.kind=='wave_start':
			attack_times.clear()
			death_times.clear()
			hit_reactions.clear()
			impact_marks.clear()
			shake = 0
			shake_peak = 0
			shake_started = -10.0
			continue
		var p = project(595+e.x*.91,475+e.y*.9,14)
		match e.kind:
			'attack': attack_times[e.id] = clock
			'hit':
				receive_hit(e)
				if e.get('broken',false):
					captions.append({'pos':p-Vector2(20,30),'life':.75,'text':'SHIELD BROKEN','color':Color('#e6d9a6')})
				if e.damage>0 and stains.size()<feedback.stain_limit:
					stains.append({'pos':p+Vector2(randf_range(-14,14),15),'size':Vector2(randf_range(3,10),randf_range(2,4))})
			'blast':
				burst(p,Color('#c6af76'),16)
				add_impact(p,'blast',1.0 if e.side=='ally' else -1.0)
				kick(feedback.blast_shake,1.0 if e.side=='ally' else -1.0)
			'death':
				death_times[e.id] = clock
				burst(p,Color('#a04234'),8)
				captions.append({'pos':p-Vector2(20,35),'life':.85,'text':'ROUTED' if e.side=='enemy' else 'SQUAD LOST','color':Color('#ecd08b') if e.side=='enemy' else Color('#d28979')})
				kick(feedback.death_shake,1.0 if e.side=='enemy' else -1.0)
			'breach':
				kick(feedback.breach_shake,-1.0)

func _draw():
	if game == null: return
	var offset = camera_offset()
	draw_set_transform(offset)
	environment.draw(self,environment_act,offset)
	if menu_mode:
		draw_set_transform(Vector2.ZERO)
		return
	for s in stains: draw_rect(Rect2(s.pos,s.size),Color('#602b29'))
	var queue: Array = []
	var expansion_tiles=game.expansion_candidates() if camp_action=='expand' else []
	for i in int(game.camp.max_lives):
		queue.append({'kind':'life','pos':project(-25,380+i*66),'live':i<game.g.defense})
	for i in int(game.camp.max_buildings):
		var b = game.building_at(i)
		var wc = center(i)
		var p = project(wc.x,wc.y)
		if game.g.battle == null:
			var unlocked=game.is_unlocked(i)
			var expanding=i in expansion_tiles
			if not unlocked and not expanding: continue
			var valid = unlocked and (camp_action=='move' or (game.g.phase=='place' and (b==null or (b.type==game.g.pending and b.level<game.camp.max_building_level))))
			var active = i==hover_cell or i==selected_cell
			if unlocked or expanding:
				var polygon = cell_shape(i)
				draw_colored_polygon(polygon,Color(0.88,.83,.59,.24 if active else .12 if expanding else .06))
				polygon.append(polygon[0])
				draw_polyline(polygon,Color('#f0dca0') if active or expanding else Color(.59,.67,.47,.75 if valid else .5),2)
				if b==null and (valid or expanding):
					draw_line(p-Vector2(5,0),p+Vector2(5,0),Color('#c6d1a5'),2)
					draw_line(p-Vector2(0,5),p+Vector2(0,5),Color('#c6d1a5'),2)
		if b!=null:
			if not game.is_troop(b.type): queue.append({'kind':'building','pos':p,'building':b,'cell':i})
			if game.g.battle==null:
				var label_y=24.0+troop_extent_y(b.type,Formation.count(b.type,int(b.level))) if game.is_troop(b.type) else 18.0
				queue.append({'kind':'level','pos':p+Vector2(0,label_y),'building':b})
	if game.g.battle==null:
		var source=game.building_at(hover_cell)
		if game.g.phase=='place' and game.is_unlocked(hover_cell): source={'type':game.g.pending,'cell':hover_cell}
		elif camp_action=='move' and game.is_unlocked(hover_cell):
			var moving=game.building_at(moving_cell)
			if moving!=null: source={'type':moving.type,'cell':hover_cell}
		if source!=null:
			for b in game.g.buildings:
				if camp_action=='move' and b.cell==moving_cell: continue
				var cell=moving_cell if camp_action=='move' and b.cell==source.cell else int(b.cell)
				if not game.adjacent(int(source.cell),cell): continue
				var attack_link=(source.type=='training' and game.types[b.type].get('attack',0)>0) or (b.type=='training' and game.types[source.type].get('attack',0)>0)
				var health_link=(source.type=='medic' and game.is_troop(b.type)) or (b.type=='medic' and game.is_troop(source.type))
				if not attack_link and not health_link: continue
				var a=center(source.cell);var z=center(cell)
				draw_line(project(a.x,a.y),project(z.x,z.y),Color('#e6c980'),3)
		var front=center(int(game.camp.columns)*2+int(game.camp.columns)-1)
		draw_string(world_font,project(front.x+70,front.y),text('FRONT →'),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color('#e6c980'))
	var units = preview if game.g.battle==null else game.g.battle.units
	for u in units:
		if game.g.battle==null and u.side=='ally' and not game.is_troop(u.type): continue
		var dead = u.hp<=0
		var age = clock-death_times.get(u.id,clock) if dead else 0
		var p = project(595+u.x*.91,475+u.y*.9)
		if u.type=='siege':
			queue.append({'kind':'siege','pos':p,'unit':u,'dead':dead})
			continue
		var count=int(u.get('soldierCount',5 if u.type=='cavalry' else 3 if u.type=='medic' else 9))
		for i in count:
			var formation_offset=troop_offset(u,i)
			var x = 595+u.x*.91+formation_offset.x
			var y = 475+u.y*.9+formation_offset.y
			queue.append({'kind':'soldier','pos':project(x,y),'unit':u,'index':i,'dead':dead,'age':age})
	queue.sort_custom(func(a,b):return a.pos.y<b.pos.y)
	for item in queue:
		var p = item.pos
		if item.kind in ['soldier','siege'] and not item.dead: p += recoil_offset(int(item.unit.id))
		match item.kind:
			'level':
				var b=item.building
				var value=['','I','II','III'][int(b.level)]
				if game.is_troop(b.type): value+='  ×'+str(Formation.count(b.type,int(b.level)))
				var width=world_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
				draw_rect(Rect2(p-Vector2(width*.5+4,15),Vector2(width+8,19)),Color(.08,.12,.09,.86))
				draw_string(world_font,(p-Vector2(width*.5,0)).round(),value,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color('#e0d4aa'))
			'life': draw_texture(tex('life_'+str(int(item.live))),p-Vector2(48,70))
			'building':
				var b = item.building
				var lift = 4 if item.cell==selected_cell and game.g.battle==null else 0
				if b.type in ['siege','medic']:
					draw_texture_rect(tex('facilities/'+b.type+'_'+str(int(b.level))),Rect2((p-Vector2(48,82+lift)).round(),Vector2(96,96)),false)
				else:
					draw_texture_rect(tex('building_'+b.type+'_'+str(int(b.level))),Rect2(p-Vector2(37.1,63.7+lift),Vector2(74.2,74.2)),false)
			'siege':
				var frame = clampi(int((clock-attack_times.get(item.unit.id,-10.0))/.75*16),0,15)
				var color = Color(.45,.38,.34,.7) if item.dead else (Color(.7,.85,1) if item.unit.side=='enemy' else Color.WHITE)
				draw_texture_rect_region(tex('catapult'),Rect2(p-Vector2(40,65),Vector2(73,73)),Rect2(frame*80,0,80,80),color)
			'soldier':
				var u = item.unit
				var attack_age = clock-attack_times.get(u.id,-10.0)-(item.index%3)*.032-int(item.index/3.0)*.018
				var mode = 'idle'
				var frame = 0
				if not item.dead:
					if attack_age>=0 and attack_age<.48:
						mode = 'attack'
						frame = clampi(int(attack_age/.48*16),0,15)
					elif u.moving and game.g.phase=='battle':
						mode = 'walk'
						frame = int((clock*13+item.index*.83+u.id*.52)/TAU*16)%16
				if u.get('testudo',false) and item.index%3>0: mode = 'testudo' if mode=='idle' else 'testudo_'+mode
				var dir = 1.0 if u.side=='ally' else -1.0
				var angle = -dir*minf(1,item.age/.3)*1.5 if item.dead else 0.0
				draw_set_transform(pixel_position(p+offset),angle,Vector2(dir,1)*float(field.troop_scale))
				var color = Color(.55,.4,.38,.8) if item.dead else Color.WHITE
				if not item.dead: color = hit_tint(int(u.id))
				draw_texture_rect_region(tex('unit_'+u.type+'_'+u.side+'_'+mode),Rect2(-32,-52,64,64),Rect2(frame*64,0,64,64),color)
				if not item.dead and u.hp<u.maxHp*.65: draw_rect(Rect2(-1,-13,2,4),Color('#8d292d'))
				draw_set_transform(offset)
	if game.g.battle!=null:
		for u in units:
			if u.hp<=0: continue
			var p = project(595+u.x*.91,475+u.y*.9)
			var label_lift=37.0
			if u.type!='siege':
				# Clear the back row and tall spears without changing the squad's actual position.
				var head_height=43.0 if u.type=='spear' else 35.0 if u.type=='cavalry' else 25.0
				label_lift=(head_height+8.0)*float(field.troop_scale)
				label_lift+=troop_extent_y(u.type,int(u.get('soldierCount',5 if u.type=='cavalry' else 3 if u.type=='medic' else 9)),u.get('testudo',false))
			var bar=pixel_position(p-Vector2(0,label_lift))
			draw_rect(Rect2(bar-Vector2(22,0),Vector2(44,5)),Color('#183626'))
			draw_rect(Rect2(bar-Vector2(21,-1),Vector2(42*u.hp/u.maxHp,3)),Color('#e6c980') if u.side=='ally' else Color('#acc5c9'))
			if u.shield>0: draw_rect(Rect2(bar-Vector2(21,4),Vector2(42*u.shield/u.maxShield,2)),Color('#c9eddb'))
			if u.get('healUntil',0)>game.g.battle.time:
				draw_line(bar-Vector2(4,13),bar+Vector2(4,-13),Color('#a2ddba'),3)
				draw_line(bar-Vector2(0,17),bar-Vector2(0,9),Color('#a2ddba'),3)
			if u.get('burnUntil',0)>game.g.battle.time:
				draw_rect(Rect2(bar+Vector2(26,8),Vector2(4,10)),Color('#d4813c'))
		for shot in game.g.battle.projectiles:
			var t = 1-shot.life/shot.duration
			var launch_height=24.0*(1.0 if shot.siege else float(field.troop_scale))
			var p = project(595+(shot.from+(shot.to-shot.from)*t)*.91,475+(shot.fromY+(shot.toY-shot.fromY)*t)*.9,launch_height+sin(t*PI)*(110 if shot.siege else 28))
			if shot.siege:
				draw_rect(Rect2(p-Vector2(5,4),Vector2(10,8)),Color('#a6b1a2'))
				draw_rect(Rect2(p+Vector2(2,0),Vector2(4,5)),Color('#53655b'))
			else:
				var dir = 1 if shot.side=='ally' else -1
				draw_line(p,p+Vector2(15,5)*dir,Color('#df984a') if shot.fire else Color('#eee1b5'),2)
	draw_impacts()
	for p in particles:
		var side=maxf(feedback.pixel_step,snappedf(p.size,feedback.pixel_step))
		draw_rect(Rect2(pixel_position(p.pos),Vector2(side,side)),p.color)
	for c in captions: draw_string(world_font,c.pos,text(c.text),HORIZONTAL_ALIGNMENT_LEFT,-1,18,c.color)
	draw_set_transform(Vector2.ZERO)

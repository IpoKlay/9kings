extends RefCounted
## Coordinates here are projected field pixels before camera zoom (the same grid as soldier feet).
const Terrain=preload('res://scripts/tactical/pass_terrain.gd')
const Soldiers=preload('res://scripts/tactical/regiment_soldiers.gd')

static func bearing(u: Dictionary,angle: float,margin_degrees: float) -> int:
	var nearest=posmod(roundi(angle/(PI/4)),8)
	if u.kind!='cavalry':return nearest
	var old: int=u.get('sprite_bearing',-1)
	if old<0 or absf(angle_difference(old*PI/4,angle))>PI/8+deg_to_rad(margin_degrees):u.sprite_bearing=nearest
	return u.sprite_bearing

static func cell_index(action: bool,walk: bool,frame: int,phase: int) -> int:
	if action:return 9+maxi(0,frame-phase%2)
	if walk:return 1+posmod(frame+[0,1,0,-1][phase],8)
	return 0

static func slot_offset(kind: String, stats: Dictionary, slot: int, high_view: bool=false) -> Vector2:
	var layout=Terrain.layout(kind,high_view)
	var files=int(stats.files)
	return Vector2((slot-(files-1)*.5)*layout.x,0)

# One shared oriented row for drawing, hits, projectiles and local reactions.
static func feet(r,u: Dictionary,heading: Vector2=Vector2.ZERO) -> PackedVector2Array:
	if not heading.is_zero_approx():return formation_feet(r,u,heading)
	# shortcut: untouched members still follow their row; migrate autonomous AI movement next.
	if not u.get('personalized',false):return formation_feet(r,u)
	var result=formation_feet(r,u).duplicate()
	if u.get('personalized',false):
		for slot in u.soldiers.size():
			if u.soldiers[slot].has('position'):result[slot]=r.ground_basis.basis_xform(u.soldiers[slot].position-u.pos)
	return result

static func formation_feet(r,u: Dictionary,heading: Vector2=Vector2.ZERO) -> PackedVector2Array:
	if heading.is_zero_approx():heading=u.get('formation_heading',u.heading)
	if u.get('row_heading',Vector2.ZERO)==heading and u.get('row_basis',Transform2D())==r.ground_basis:
		return u.row_feet
	var lateral=heading.normalized().orthogonal()
	var width=Vector2(r.ground_basis.x.x,r.ground_basis.y.x).length()
	var axis: Vector2=r.ground_basis.basis_xform(lateral)/width
	var result=PackedVector2Array()
	for point in r.contact_profiles[u.kind].feet:result.append(axis*point.x)
	u.row_heading=heading
	u.row_basis=r.ground_basis
	u.row_feet=result
	return result

static func turn(r,u: Dictionary,dt: float):
	var old: Vector2=u.get('formation_heading',u.heading)
	if u.hp<=0 or u.petrified>0 or u.stun>0:return
	var angle=old.angle_to(u.heading)
	u.formation_heading=old.rotated(clampf(angle,-Terrain.VIEW.formation_turn_rate*dt,Terrain.VIEW.formation_turn_rate*dt))

static func count(u: Dictionary, stats: Dictionary) -> int:
	if u.has('soldiers'):
		Soldiers.sync(u)
		return u.soldiers.filter(func(actor):return actor.hp>0).size()
	return maxi(1,ceili(stats.files*u.hp/u.max_hp))

static func present(u: Dictionary, slot: int, visible_count: int) -> bool:
	if u.has('soldiers'):return u.soldiers[slot].hp>0
	return int(u.slot_priority[slot] if u.has('slot_priority') else slot)<visible_count

# A zero-HP person remains visible until the actual death-system visit.
static func drawable(u: Dictionary,slot: int) -> bool:
	return u.soldiers[slot].get('death_state',0)==0

# Stable body ellipses follow the proportions of the eight-direction 64px atlas.
# The lookup contains feet for all files in a fresh regiment; losses leave holes.
static func profile(kind: String,stats: Dictionary,high_view: bool=false) -> Dictionary:
	var radius=Vector2(18,23)
	match kind:
		'cavalry':radius=Vector2(33,38.5)
		'spear':radius=Vector2(25,30)
		'siege':radius=Vector2(40,26)
	var slots=PackedVector2Array()
	for i in int(stats.files):slots.append(slot_offset(kind,stats,i,high_view))
	return {'radius':radius*(Terrain.VIEW.figure_scale if high_view else 1.),'feet':slots,'files':int(stats.files),'spacing':Terrain.layout(kind,high_view).x,'scale':Terrain.layout(kind,high_view).z}

static func touching(r,a: Dictionary,b: Dictionary,advance: Vector2=Vector2.ZERO) -> bool:
	var sa: Dictionary=r.contact_profiles[a.kind]
	var sb: Dictionary=r.contact_profiles[b.kind]
	var delta: Vector2=r.ground_basis.basis_xform(b.pos-a.pos-advance)+Vector2(0,sa.radius.y-sb.radius.y)
	var reach: Vector2=sa.radius+sb.radius
	var extent: Vector2=r.terrain.extents[a.kind]+r.terrain.extents[b.kind]+reach
	if a.has('slot_states') or b.has('slot_states'):extent+=Vector2(90,90)
	if not a.get('personalized',false) and not b.get('personalized',false) and (absf(delta.x)>extent.x or absf(delta.y)>extent.y):return false
	var an=count(a,r.config.types[a.kind])
	var bn=count(b,r.config.types[b.kind])
	var inv=Vector2.ONE/reach
	var occupied:=PackedVector2Array()
	var other=feet(r,b)
	for j in other.size():
		if present(b,j,bn):occupied.append((delta+other[j]+body_shift(b,j,r.elapsed))*inv)
	var own=feet(r,a)
	for i in own.size():
		if not present(a,i,an):continue
		var boot: Vector2=(own[i]+body_shift(a,i,r.elapsed))*inv
		for point in occupied:
			if boot.distance_squared_to(point)<=1:return true
	return false

static func body_shift(u: Dictionary,slot: int,now: float) -> Vector2:
	var local:=slot_shift(u,slot,now)
	var motion: Dictionary=u.get('contact_motion',{})
	if motion.is_empty():return local
	var offsets: Dictionary=motion.offsets
	if not offsets.has(slot):return local
	var impulse: Vector3=offsets[slot]
	var age: float=now-motion.start-impulse.z
	if age<=0:return local
	var rise: float=motion.rise
	var settle: float=motion.hold
	var weight=smoothstep(0,rise,age)*(1-smoothstep(settle,settle+motion.recover,age))
	return local+Vector2(impulse.x,impulse.y)*weight

# Locate the opposing figures at the edge, once per landed blow.
static func locate(r,a: Dictionary,b: Dictionary,old_count: int) -> Dictionary:
	var ac: Vector2=r.projection*a.pos
	var bc: Vector2=r.projection*b.pos
	var dir: Vector2=ac.direction_to(bc)
	if dir==Vector2.ZERO:dir=r.ground_basis.basis_xform(a.heading).normalized()
	var sa: Dictionary=r.config.types[a.kind]
	var sb: Dictionary=r.config.types[b.kind]
	var an=count(a,sa)
	var bn=old_count
	var best=INF
	var near_a=Vector2.ZERO
	var near_b=Vector2.ZERO
	var near_slot=0
	var target_slots={}
	var own_feet=feet(r,a)
	var enemy_feet=feet(r,b)
	for j in int(sb.files):
		if present(b,j,bn):
			target_slots[j]=enemy_feet[j]+body_shift(b,j,r.elapsed)
	for i in int(sa.files):
		if not present(a,i,an):continue
		var foot: Vector2=own_feet[i]+body_shift(a,i,r.elapsed)
		var tip=ac+foot+Vector2(0,-r.contact_profiles[a.kind].radius.y)+dir*16
		for j in target_slots:
			var point: Vector2=bc+target_slots[j]+Vector2(0,-r.contact_profiles[b.kind].radius.y)
			var cost=tip.distance_squared_to(point)-foot.dot(dir)*.15
			if cost<best:
				best=cost
				near_a=foot
				near_b=target_slots[j]
				near_slot=j
	return {'dir':dir,'rider':near_a,'entry':near_b,'defender_slot':near_slot,'pos':r.projection.affine_inverse()*(bc+near_b)}

# A soldier can part inside the pass, but a personal excursion ends at the rock face.
static func clip_shift(r,u: Dictionary,slot: int,shift: Vector2) -> Vector2:
	var start: Vector2=r.projection*u.pos+feet(r,u)[slot]
	if shift.is_zero_approx():return Vector2.ZERO
	var inverse: Transform2D=r.projection.affine_inverse()
	var world_start:=inverse*start
	var world_end:=world_start+inverse.basis_xform(shift)
	var bounded:=world_end.clamp(r.bounds.position,r.bounds.end-Vector2(.001,.001))
	# A legal regiment centre can leave its outermost boot beyond the map edge.
	# Only forbid excursions farther out from that boot.
	var finish: Vector2=start+r.ground_basis.basis_xform(bounded-world_start.clamp(r.bounds.position,r.bounds.end-Vector2(.001,.001)))
	for wall: Rect2 in r.terrain.ROCKS:
		if r.terrain.crosses(wall,start,finish):
			for edge in 4:
				var corners=[wall.position,Vector2(wall.end.x,wall.position.y),wall.end,Vector2(wall.position.x,wall.end.y)]
				var touch=Geometry2D.segment_intersects_segment(start,finish,corners[edge],corners[(edge+1)%4])
				if touch!=null:finish=start.move_toward(touch,maxf(0,start.distance_to(touch)-2))
	return finish-start

static func apply(r,a: Dictionary,b: Dictionary,hit: Dictionary,old_count: int):
	var cfg: Dictionary=r.config.regiment_impact
	var side: bool=hit.sector!='front'
	var braced: bool=not side and braced_pikes(b,r.elapsed)
	var contact: Dictionary=hit.contact if hit.has('contact') else locate(r,a,b,old_count)
	var dir: Vector2=contact.dir
	var sb: Dictionary=r.config.types[b.kind]
	var casualties=[]
	for j in int(sb.files):
		if present(b,j,old_count):
			casualties.append([j,feet(r,b)[j].distance_squared_to(contact.entry)])
	begin_passage(r,a,b,contact,side,braced)
	b.contact_motion={'start':r.elapsed,'offsets':{},'rise':.06,'hold':cfg.gap_hold,'recover':.65}
	# Preserve the exact contact record for single-step feedback and replay auditing.
	var first_slot: int=contact.defender_slot
	b.contact_motion.offsets[first_slot]=Vector3.ZERO
	if hit.has('contact'):
		hit.ground_pos=b.pos+r.ground_basis.affine_inverse().basis_xform(contact.entry)
		b.contact_motion.contact=hit.contact
		b.contact_motion.old_count=old_count
	# Remove figures at the broken edge first. Healing restores those slots in reverse order.
	var lost=old_count-count(b,sb)
	if lost>0:
		casualties.sort_custom(func(x,y):return x[1]<y[1])
		var order: Array=range(int(sb.files))
		var priority: Dictionary=b.get('slot_priority',{})
		order.sort_custom(func(x,y):return priority.get(x,x)<priority.get(y,y))
		for index in mini(lost,casualties.size()):
			var victim=casualties[index][0]
			order.erase(victim)
			order.insert(old_count-1,victim)
		for i in order.size():priority[order[i]]=i
		b.slot_priority=priority
	hit.mounted_contact=true
	hit.braced=braced
	hit.pos=contact.pos
	hit.from=hit.pos-r.ground_basis.affine_inverse().basis_xform(dir*80)

# Sparse slots interpolate from their current pose, hold, then walk home.
static func slot_shift(u: Dictionary,slot: int,now: float) -> Vector2:
	var state: Dictionary=u.get('slot_states',{}).get(slot,{})
	if state.is_empty():return Vector2.ZERO
	var age: float=now-state.start
	if age<state.rise:return state.origin.lerp(state.goal,smoothstep(0,state.rise,age))
	if state.get('persistent',false):
		if state.get('returning',false):return state.return_from.move_toward(Vector2.ZERO,maxf(0,now-state.return_start)*state.return_speed)
		return state.goal
	return state.goal*(1-smoothstep(state.hold,state.hold+state.recover,age))

static func set_slot(r,u: Dictionary,slot: int,goal: Vector2,rise: float,hold: float,recover: float):
	if not u.has('slot_states'):u.slot_states={}
	var current:=slot_shift(u,slot,r.elapsed)
	u.slot_states[slot]={'origin':current,'goal':clip_shift(r,u,slot,goal),'start':r.elapsed,
		'rise':rise,'hold':hold,'recover':recover}

static func prune(u: Dictionary,now: float):
	var states: Dictionary=u.get('slot_states',{})
	for slot in states.keys():
		var s: Dictionary=states[slot]
		if not s.get('persistent',false) and now>=s.start+s.hold+s.recover:states.erase(slot)
	if states.is_empty():u.erase('slot_states')

# Combat displacement owns a slot until both its pause and a genuinely clear
# return corridor permit walking home. No enemy can be crossed by a timer.
static func advance_recovery(r,u: Dictionary,_dt: float):
	var states: Dictionary=u.get('slot_states',{})
	if states.is_empty():return
	var row=feet(r,u)
	var origin: Vector2=r.projection*u.pos
	var active=count(u,r.config.types[u.kind])
	for slot in states.keys():
		var state: Dictionary=states[slot]
		if not state.get('persistent',false):continue
		if u.hp<=0 or not present(u,slot,active):
			# Casualty collection needs this step's displaced foot before clearing it.
			continue
		if r.elapsed<state.release_at:continue
		var shift=slot_shift(u,slot,r.elapsed)
		if shift.length()<.05:
			states.erase(slot)
			continue
		if r.elapsed<state.get('next_check',0.):continue
		state.next_check=r.elapsed+.08
		var home: Vector2=origin+row[slot]
		var start: Vector2=home+shift
		var blocked=false
		for wall: Rect2 in r.terrain.ROCKS:
			if r.terrain.crosses(wall,start,home):blocked=true;break
		if not blocked:
			for enemy in r.alive('enemy' if u.side=='ally' else 'ally'):
				if enemy.get('routing',false):continue
				var enemy_origin: Vector2=r.projection*enemy.pos
				if enemy_origin.distance_squared_to(home)>450*450:continue
				var enemy_feet=feet(r,enemy)
				var alive_count=count(enemy,r.config.types[enemy.kind])
				for j in enemy_feet.size():
					if not present(enemy,j,alive_count):continue
					var foot: Vector2=enemy_origin+enemy_feet[j]+body_shift(enemy,j,r.elapsed)
					var closest=Geometry2D.get_closest_point_to_segment(foot,start,home)
					if foot.distance_squared_to(closest)<(22*22 if enemy.kind=='cavalry' or u.kind=='cavalry' else 15*15):
						blocked=true
						break
				if blocked:break
		if blocked:
			if state.get('returning',false):
				state.goal=shift
				state.origin=shift
				state.start=r.elapsed
				state.rise=0.
				state.returning=false
		elif not state.get('returning',false):
			state.returning=true
			state.return_start=r.elapsed
			state.return_from=shift
			state.return_speed=46. if u.kind!='cavalry' else 64.
	if states.is_empty():u.erase('slot_states')

# Sample after all movement, turning and impact resolution. Pausing never calls
# this, so both stride accumulation and local feedback stay on simulation time.
static func track_slots(r,u: Dictionary,dt: float):
	var row=feet(r,u)
	if not u.has('slot_distances'):
		u.slot_distances={}
		u.slot_speeds={}
		u.slot_last_feet={}
	var inverse: Transform2D=r.projection.affine_inverse()
	for slot in row.size():
		var point: Vector2=r.projection*u.pos+row[slot]+body_shift(u,slot,r.elapsed)
		var old: Vector2=u.slot_last_feet.get(slot,point)
		var distance=inverse.basis_xform(point-old).length()
		u.slot_distances[slot]=u.slot_distances.get(slot,u.march_distance)+distance
		u.slot_speeds[slot]=distance/maxf(dt,.000001)
		u.slot_last_feet[slot]=point

static func light_hit(r,u: Dictionary,entry: Vector2,dir: Vector2,struck_slot: int=-1):
	var row=feet(r,u)
	var active=count(u,r.config.types[u.kind])
	for slot in row.size():
		if struck_slot>=0 and slot!=struck_slot:continue
		if not present(u,slot,active):continue
		var weight=1. if struck_slot>=0 else clampf(1-row[slot].distance_to(entry)/42,0,1)
		if weight<=0 or u.get('slot_states',{}).get(slot,{}).get('persistent',false):continue
		set_slot(r,u,slot,dir*7*weight,.075,.16,.28)
		u.slot_states[slot].merge({'reaction':'light','reaction_start':r.elapsed,'dir':dir})

static func begin_passage(r,a: Dictionary,b: Dictionary,contact: Dictionary,flank: bool,braced: bool):
	var cfg: Dictionary=r.config.regiment_impact
	var axis: Vector2=contact.dir
	var speed: float=r.ground_basis.basis_xform(a.heading*float(r.config.types.cavalry.speed)*a.pace).length()
	var first: Vector2=contact.rider
	var origin: Vector2=r.projection*a.pos
	var entry: Vector2=r.projection*b.pos+contact.entry
	a.penetration={'target':b.id,'axis':axis,'origin':origin,'entry':entry,'rider':first,
		'travel':0.,'riders':{},
		'limit':float(cfg.flank_depth if flank else cfg.braced_depth if braced else cfg.front_depth),
		'dislodged':{},'start':r.elapsed,'braced':braced,'flank':flank,'contacts':{}}
	var row:=feet(r,a)
	var first_slot=0
	var nearest=INF
	for i in row.size():
		var foot:=row[i]+body_shift(a,i,r.elapsed)
		var rel: Vector2=foot-first
		if rel.length_squared()<nearest:nearest=rel.length_squared();first_slot=i
		var lateral:=rel.dot(axis.orthogonal())
		var lane:=clampf(1-absf(lateral)/(cfg.lane_half_width*1.7),0,1)
		a.penetration.riders[i]={'origin':foot,'rel':rel,'lane':lane,'travel':0.,'blocked':0.,
			'speed':maxf(1,speed)*(.68 if flank else .22 if braced else .4)*(.3+.7*lane),
			'limit':a.penetration.limit*lane+minf(a.penetration.limit*.3,20)*(1-lane),
			'delay':maxf(0,-rel.dot(axis))/maxf(1,speed),'done':false,'point':origin+foot}
	a.rider_contacts={}
	a.penetration.contacts[first_slot]=r.elapsed
	a.rider_contacts[first_slot]={'start':r.elapsed,'dir':axis,'braced':braced}
	set_slot(r,a,first_slot,slot_shift(a,first_slot,r.elapsed),0.,.1,.55)
	a.slot_states[first_slot].merge({'persistent':true,'release_at':r.elapsed+.65,'returning':false,
		'reaction':'rider_brace' if braced else 'rider_impact','reaction_start':r.elapsed,'dir':axis})
	# Public intent marker also consumed by the mounted gait and route cancellation.
	a.follow_goal=a.pos+r.ground_basis.affine_inverse().basis_xform(axis*a.penetration.limit)
	if braced:a.brace_until=r.elapsed+.40
	var slot: int=contact.get('defender_slot',-1)
	if slot>=0:part_slot(r,b,a.penetration,slot,1.)

static func part_slot(r,b: Dictionary,p: Dictionary,slot: int,weight: float):
	var cfg: Dictionary=r.config.regiment_impact
	var axis: Vector2=p.axis
	var normal:=axis.orthogonal()
	var foot: Vector2=r.projection*b.pos+feet(r,b)[slot]
	var lateral: float=(foot-p.entry).dot(normal)
	var hand:=signf(lateral) if absf(lateral)>1 else (1. if slot%2 else -1.)
	var width: float=cfg.flank_spread if p.flank else cfg.braced_spread if p.braced else cfg.front_spread
	var goal: Vector2=(normal*hand*width+axis*width*.22)*weight
	set_slot(r,b,slot,goal,.12,cfg.gap_hold,.56)
	var hold: float=cfg.get('breach_hold',2.6) if p.flank else .8 if p.braced else 2.0
	b.slot_states[slot].merge({'reaction':'brace' if p.braced else 'charge',
		'reaction_start':r.elapsed,'dir':axis,'persistent':true,'release_at':r.elapsed+hold,'returning':false})
	p.dislodged[slot]=true

# Each horse spends its own momentum against its own track. The regiment centre
# follows the mean progress; it cannot stop a clear neighbour when one horse stalls.
static func advance_passage(r,a: Dictionary,b: Dictionary,dt: float) -> bool:
	var p: Dictionary=a.penetration
	var axis: Vector2=p.axis
	var normal:=axis.orthogonal()
	var cfg: Dictionary=r.config.regiment_impact
	var age: float=r.elapsed-p.start
	var defender_feet:=feet(r,b)
	var count_b=count(b,r.config.types[b.kind])
	var count_a=count(a,r.config.types[a.kind])
	var center: Vector2=r.projection*b.pos
	var active=false
	var total: float=0.
	var living=0
	for i in p.riders:
		var rider: Dictionary=p.riders[i]
		if not present(a,i,count_a):rider.done=true;continue
		living+=1
		var rel: Vector2=rider.rel
		var lateral:=rel.dot(normal)
		if not rider.done and age>=rider.delay:
			var previous: float=rider.travel
			var next: float=minf(rider.limit,previous+rider.speed*dt)
			var side_step: float=-lateral*rider.lane*clampf(next/75,0,.46)
			var nose: Vector2=rel+axis*next+normal*side_step
			var start_along:=rel.dot(axis)+previous
			var end_along:=nose.dot(axis)
			var touches=false
			var new_contacts=0
			for j in defender_feet.size():
				if not present(b,j,count_b):continue
				var home: Vector2=center+defender_feet[j]-p.entry
				var boot:=home+body_shift(b,j,r.elapsed)
				var across:=absf((boot-nose).dot(normal))
				var along:=boot.dot(axis)
				if along<start_along-9 or along>end_along+9:continue
				if across<cfg.lane_half_width and absf(home.dot(normal))<cfg.lane_half_width and rider.lane>.12:
					touches=true
					if not p.dislodged.has(j):
						part_slot(r,b,p,j,sqrt(clampf(1-across/cfg.lane_half_width,.03,1.)))
						new_contacts+=1
				if across<8 and along>=start_along-2:
					end_along=minf(end_along,maxf(start_along,along-4))
			next=maxf(previous,end_along-rel.dot(axis))
			var desired: Vector2=p.origin+rider.origin+axis*next+normal*side_step
			var actual:=clip_boot_motion(r,rider.point,desired)
			var terrain_blocked:=actual.distance_squared_to(desired)>.01
			if terrain_blocked:
				next=maxf(previous,(actual-p.origin-rider.origin).dot(axis))
			var inc:=maxf(0,next-previous)
			rider.blocked=rider.blocked+dt if inc<.03 else 0.
			rider.travel=next
			rider.point=actual
			rider.speed=maxf(0,rider.speed-(24 if p.flank else 70)*dt-new_contacts*(1.6 if p.flank else 4.))
			rider.done=terrain_blocked or next>=rider.limit-.02 or rider.speed<=2 or rider.blocked>=.17
			if touches and not p.contacts.has(i):
				p.contacts[i]=r.elapsed
				a.rider_contacts[i]={'start':r.elapsed,'dir':axis,'braced':p.braced}
				if p.contacts.size()>1:
					r.events.append({'kind':'rider_contact','pos':r.projection.affine_inverse()*(p.entry+normal*nose.dot(normal)),
						'attacker':a.id,'target':b.id,'slot':i,'charge_id':a.charge_id,'braced':p.braced})
		active=active or not rider.done
		total+=rider.travel
	# Moving the command anchor is optional; physical horses retain their own points.
	var previous: Vector2=a.pos
	var advance:=total/maxi(1,living)*.42
	var next_world: Vector2=r.projection.affine_inverse()*(p.origin+axis*advance)
	if r.bounds.has_point(next_world) and r.may_advance(a,next_world):a.pos=next_world
	r.record_march(a,previous)
	a.pace=previous.distance_to(a.pos)/maxf(.001,dt*r.config.types.cavalry.speed)
	p.travel=advance
	var row:=feet(r,a)
	if not a.has('slot_states'):a.slot_states={}
	for i in p.riders:
		if not present(a,i,count_a):continue
		var shift: Vector2=p.riders[i].point-r.projection*a.pos-row[i]
		# The swept foot already passed terrain checks. Do not clip from an unrelated
		# formation home or interpolate backwards through a newly occupied corridor.
		a.slot_states[i]={'origin':shift,'goal':shift,'start':r.elapsed,'rise':0.,'hold':.10,'recover':.55,
			'persistent':true,'release_at':r.elapsed+.65,'returning':false}
		if p.contacts.has(i):
			a.slot_states[i].merge({'reaction':'rider_brace' if p.braced else 'rider_impact',
				'reaction_start':p.contacts[i],'dir':axis})
	return active and age<1.45

# Sweep from the current foot, never from its old formation home.
static func clip_boot_motion(r,start: Vector2,finish: Vector2) -> Vector2:
	var inverse: Transform2D=r.projection.affine_inverse()
	var world_start:=inverse*start
	var world_end:=inverse*finish
	var bounded:=world_end.clamp(r.bounds.position,r.bounds.end-Vector2(.001,.001))
	finish=start+r.ground_basis.basis_xform(bounded-world_start.clamp(r.bounds.position,r.bounds.end-Vector2(.001,.001)))
	for wall: Rect2 in r.terrain.ROCKS:
		if not r.terrain.crosses(wall,start,finish):continue
		if wall.has_point(start):return start
		var corners=[wall.position,Vector2(wall.end.x,wall.position.y),wall.end,Vector2(wall.position.x,wall.end.y)]
		for edge in 4:
			var touch=Geometry2D.segment_intersects_segment(start,finish,corners[edge],corners[(edge+1)%4])
			if touch!=null:finish=start.move_toward(touch,maxf(0,start.distance_to(touch)-2))
	return finish

# Sample one front per file. Contacted files brace while a free wing continues
# a short distance around the end of the opposing line.
static func press_wall(r,a: Dictionary,b: Dictionary):
	if a.get('wall_next',0.)>r.elapsed:return
	a.wall_next=r.elapsed+.20
	var axis: Vector2=r.ground_basis.basis_xform(a.heading).normalized()
	var gap: Vector2=r.ground_basis.basis_xform(b.pos-a.pos)
	if axis.dot(gap.normalized())<.4:return
	var normal:=axis.orthogonal()
	var own: PackedVector2Array=feet(r,a)
	var other: PackedVector2Array=feet(r,b)
	var active=count(b,r.config.types[b.kind])
	var enemy_front=INF
	var lo=INF
	var hi=-INF
	for i in other.size():
		if not present(b,i,active):continue
		var point: Vector2=gap+other[i]+body_shift(b,i,r.elapsed)
		enemy_front=minf(enemy_front,point.dot(axis))
		lo=minf(lo,point.dot(normal))
		hi=maxf(hi,point.dot(normal))
	var local_front=-INF
	for point in own:local_front=maxf(local_front,point.dot(axis))
	var engaged={}
	for i in own.size():
		var behind: float=local_front-own[i].dot(axis)
		var flank:=own[i].dot(normal)
		var exposure:=flank-clampf(flank,lo,hi)
		var separation: float=enemy_front-own[i].dot(axis)
		if behind>58:continue
		var offset:=Vector2.ZERO
		if absf(exposure)>9 and a.order!='hold':
			var advance:=clampf(absf(exposure)*.9,0,42)*clampf(1-behind/82,.25,1)
			offset=axis*advance-normal*signf(exposure)*advance*.18
		elif separation<58:
			offset=-axis*(6 if a.order=='hold' else 3)*clampf(1-behind/58,0,1)
			engaged[i]=true
		if not offset.is_zero_approx() and not a.has('penetration'):
			# A charge or projectile reaction owns its slot until it settles.
			var existing: Dictionary=a.get('slot_states',{}).get(i,{})
			if existing.is_empty() or existing.get('wall',false):
				set_slot(r,a,i,offset,.22,.34,.4)
				a.slot_states[i].wall=true
	a.wall_files=engaged

static func ranged_response(r,u: Dictionary,world: Vector2,radius: float,power: float):
	var local: Vector2=r.ground_basis.basis_xform(world-u.pos)
	var slots: PackedVector2Array=feet(r,u)
	for i in slots.size():
		var delta:=slots[i]-local
		var weight:=1.-delta.length()/radius
		if weight>0 and not u.get('slot_states',{}).has(i):
			var direction:=delta.normalized() if delta.length_squared()>1 else Vector2.DOWN
			set_slot(r,u,i,direction*power*weight,.07,.17,.29)


static func braced_pikes(u: Dictionary,now: float) -> bool:
	return u.kind=='spear' and u.order=='hold' and u.stun<=0 and u.petrified<=0 and not u.get('routing',false) and now-u.get('last_stride',-1.)>=.25

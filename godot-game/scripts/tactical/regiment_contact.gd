extends RefCounted
## Coordinates here are projected field pixels before camera zoom (the same grid as soldier feet).
const Terrain=preload('res://scripts/tactical/pass_terrain.gd')

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

static func slot_offset(kind: String, stats: Dictionary, slot: int) -> Vector2:
	var layout=Terrain.layout(kind)
	var files=int(stats.files)
	return Vector2((slot-(files-1)*.5)*layout.x,0)

static func count(u: Dictionary, stats: Dictionary) -> int:
	return maxi(1,ceili(stats.files*u.hp/u.max_hp))

static func present(u: Dictionary, slot: int, visible_count: int) -> bool:
	return int(u.slot_priority[slot] if u.has('slot_priority') else slot)<visible_count

# Stable body ellipses follow the proportions of the eight-direction 64px atlas.
# The lookup contains feet for all files in a fresh regiment; losses leave holes.
static func profile(kind: String,stats: Dictionary) -> Dictionary:
	var radius=Vector2(18,23)
	match kind:
		'cavalry':radius=Vector2(33,38.5)
		'spear':radius=Vector2(25,30)
		'siege':radius=Vector2(40,26)
	var slots=PackedVector2Array()
	for i in int(stats.files):slots.append(slot_offset(kind,stats,i))
	return {'radius':radius,'feet':slots,'files':int(stats.files),'spacing':Terrain.layout(kind).x}

static func touching(r,a: Dictionary,b: Dictionary,advance: Vector2=Vector2.ZERO) -> bool:
	var sa: Dictionary=r.contact_profiles[a.kind]
	var sb: Dictionary=r.contact_profiles[b.kind]
	var delta: Vector2=r.ground_basis.basis_xform(b.pos-a.pos-advance)+Vector2(0,sa.radius.y-sb.radius.y)
	var reach: Vector2=sa.radius+sb.radius
	var extent: Vector2=r.terrain.extents[a.kind]+r.terrain.extents[b.kind]+reach
	if a.has('slot_states') or b.has('slot_states'):extent+=Vector2(90,90)
	if absf(delta.x)>extent.x or absf(delta.y)>extent.y:return false
	var an=count(a,r.config.types[a.kind])
	var bn=count(b,r.config.types[b.kind])
	var inv=Vector2.ONE/reach
	# Displaced rows can no longer use the intact-grid shortcut. Query actual
	# living boots at both ends, including gaps left by a second charging squad.
	if a.has('slot_states') or b.has('slot_states'):
		var occupied:=PackedVector2Array()
		for j in sb.feet.size():
			if present(b,j,bn):occupied.append((delta+sb.feet[j]+body_shift(b,j,r.elapsed))*inv)
		for i in sa.feet.size():
			if not present(a,i,an):continue
			var boot: Vector2=(sa.feet[i]+body_shift(a,i,r.elapsed))*inv
			for point in occupied:
				if boot.distance_squared_to(point)<=1:return true
		return false
	var bslots: PackedVector2Array=sb.feet
	for i in sa.feet.size():
		if not present(a,i,an):continue
		var origin: Vector2=sa.feet[i]-delta
		for row in range(0,bslots.size(),sb.files):
			var dy=(origin.y-bslots[row].y)*inv.y
			if absf(dy)>1:continue
			var length=sqrt(1-dy*dy)*reach.x
			var first: Vector2=bslots[row]
			var spacing: float=sb.spacing
			var start=maxi(0,ceili((origin.x-length-first.x)/spacing))
			var end=mini(sb.files-1,floori((origin.x+length-first.x)/spacing))
			for col in range(start,end+1):
				if present(b,row+col,bn):return true
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
	for j in int(sb.files):
		if present(b,j,bn):
			target_slots[j]=r.contact_profiles[b.kind].feet[j]+body_shift(b,j,r.elapsed)
	for i in int(sa.files):
		if not present(a,i,an):continue
		var foot: Vector2=r.contact_profiles[a.kind].feet[i]+body_shift(a,i,r.elapsed)
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
	var start: Vector2=r.projection*u.pos+r.contact_profiles[u.kind].feet[slot]
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
			casualties.append([j,slot_offset(b.kind,sb,j).distance_squared_to(contact.entry)])
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
		if now>=s.start+s.hold+s.recover:states.erase(slot)
	if states.is_empty():u.erase('slot_states')

static func begin_passage(r,a: Dictionary,b: Dictionary,contact: Dictionary,flank: bool,braced: bool):
	var cfg: Dictionary=r.config.regiment_impact
	var axis: Vector2=contact.dir
	var speed: float=r.ground_basis.basis_xform(a.heading*float(r.config.types.cavalry.speed)*a.pace).length()
	var first: Vector2=contact.rider
	var origin: Vector2=r.projection*a.pos
	var entry: Vector2=r.projection*b.pos+contact.entry
	a.penetration={'target':b.id,'axis':axis,'origin':origin,'entry':entry,'rider':first,
		'speed':maxf(1,speed)*(.68 if flank else .22 if braced else .4),'travel':0.,
		'limit':float(cfg.flank_depth if flank else cfg.braced_depth if braced else cfg.front_depth),
		'dislodged':{},'blocked':0.,'start':r.elapsed,'braced':braced,'flank':flank}
	# Public intent marker also consumed by the mounted gait and route cancellation.
	a.follow_goal=a.pos+r.ground_basis.affine_inverse().basis_xform(axis*a.penetration.limit)
	if braced:a.brace_until=r.elapsed+.40
	var slot: int=contact.get('defender_slot',-1)
	if slot>=0:part_slot(r,b,a.penetration,slot,1.)

static func part_slot(r,b: Dictionary,p: Dictionary,slot: int,weight: float):
	var cfg: Dictionary=r.config.regiment_impact
	var axis: Vector2=p.axis
	var normal:=axis.orthogonal()
	var foot: Vector2=r.projection*b.pos+r.contact_profiles[b.kind].feet[slot]
	var lateral: float=(foot-p.entry).dot(normal)
	var hand:=signf(lateral) if absf(lateral)>1 else (1. if slot%2 else -1.)
	var width: float=cfg.flank_spread if p.flank else cfg.braced_spread if p.braced else cfg.front_spread
	var goal: Vector2=(normal*hand*width+axis*width*.22)*weight
	set_slot(r,b,slot,goal,.065,cfg.gap_hold,.56)
	p.dislodged[slot]=true

# Sweep a narrow leading file in projected ground space. The front can advance
# only into space actually vacated by living boots; later files use the same lane.
static func advance_passage(r,a: Dictionary,b: Dictionary,dt: float) -> bool:
	var p: Dictionary=a.penetration
	var axis: Vector2=p.axis
	var normal:=axis.orthogonal()
	var cfg: Dictionary=r.config.regiment_impact
	var next: float=minf(p.limit,p.travel+p.speed*dt)
	var width: float=cfg.lane_half_width
	var age: float=r.elapsed-p.start
	if not p.has('tail') and age>=.16:
		p.tail=true
		r.events.append({'kind':'charge_tail','pos':a.pos})
	var defender_feet: PackedVector2Array=r.contact_profiles[b.kind].feet
	var count_b=count(b,r.config.types[b.kind])
	var center: Vector2=r.projection*b.pos
	var opening:=next
	var touched:=0
	var occupied_feet:=PackedVector2Array()
	for j in defender_feet.size():
		if not present(b,j,count_b):continue
		var delta: Vector2=center+defender_feet[j]-p.entry
		var along:=delta.dot(axis)
		var shift:=body_shift(b,j,r.elapsed)
		occupied_feet.append(delta+shift)
		if along< p.travel-15 or along>next+9:continue
		var across:=delta.dot(normal)
		var occupied:=delta+shift
		if absf(across)<width and not p.dislodged.has(j):
			var weight:=sqrt(clampf(1-absf(across)/width,.03,1.))
			part_slot(r,b,p,j,weight)
			touched+=1
		if absf(occupied.dot(normal))<8 and occupied.dot(axis)>=p.travel-2:
			opening=minf(opening,maxf(p.travel,occupied.dot(axis)-2))
	var inc:=maxf(0,opening-p.travel)
	var next_world: Vector2=r.projection.affine_inverse()*(p.origin+axis*opening*.42)
	if not r.bounds.has_point(next_world) or not r.may_advance(a,next_world):return false
	p.blocked=p.blocked+dt if inc<.03 else 0.
	p.travel=opening
	p.speed=maxf(0,p.speed-(24 if p.flank else 70)*dt-touched*(1.6 if p.flank else 4.))
	var previous: Vector2=a.pos
	a.pos=next_world
	r.record_march(a,previous)
	a.pace=previous.distance_to(a.pos)/maxf(.001,dt*r.config.types.cavalry.speed)
	var feet: PackedVector2Array=r.contact_profiles.cavalry.feet
	for i in feet.size():
		var rel: Vector2=feet[i]-p.rider
		var lateral:=rel.dot(normal)
		var behind:=maxf(0,-rel.dot(axis))
		var lane:=clampf(1-absf(lateral)/(width*1.7),0,1)
		# Hold the uncommitted ranks back. Followers enter the lead file in sequence.
		var distance:=maxf(0,opening-behind*.30)*lane
		var shift: Vector2=axis*(distance-opening*.42)-normal*lateral*lane*clampf(distance/75,0,.46)
		if p.braced:shift-=axis*(1+lane)*sin(minf(1,(r.elapsed-p.start)/.22)*PI)*5
		# Clip each follower to the free interval on its own track. An intact
		# neighbour or a defender pinned against rock can stop just this horse.
		var nose: Vector2=rel+axis*opening*.42+shift
		var end_along:=nose.dot(axis)
		var start_along: float=rel.dot(axis)+p.get('progress',{}).get(i,0.)
		for boot in occupied_feet:
			if absf((boot-nose).dot(normal))>=8:continue
			var stop:=boot.dot(axis)-4
			if stop>=start_along-2 and stop<end_along:
				end_along=maxf(start_along,stop)
		shift+=axis*(end_along-nose.dot(axis))
		if not p.has('progress'):p.progress={}
		p.progress[i]=end_along-rel.dot(axis)
		set_slot(r,a,i,shift,dt,.10,.55)
	return opening<p.limit-.02 and p.speed>2 and p.blocked<.17 and r.elapsed-p.start<1.45

# Sample one front per file. Contacted files brace while a free wing continues
# a short distance around the end of the opposing line.
static func press_wall(r,a: Dictionary,b: Dictionary):
	if a.get('wall_next',0.)>r.elapsed:return
	a.wall_next=r.elapsed+.20
	var axis: Vector2=r.ground_basis.basis_xform(a.heading).normalized()
	var gap: Vector2=r.ground_basis.basis_xform(b.pos-a.pos)
	if axis.dot(gap.normalized())<.4:return
	var normal:=axis.orthogonal()
	var own: PackedVector2Array=r.contact_profiles[a.kind].feet
	var other: PackedVector2Array=r.contact_profiles[b.kind].feet
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
	var feet: PackedVector2Array=r.contact_profiles[u.kind].feet
	for i in feet.size():
		var delta:=feet[i]-local
		var weight:=1.-delta.length()/radius
		if weight>0 and not u.get('slot_states',{}).has(i):
			var direction:=delta.normalized() if delta.length_squared()>1 else Vector2.DOWN
			set_slot(r,u,i,direction*power*weight,.07,.17,.29)


static func braced_pikes(u: Dictionary,now: float) -> bool:
	return u.kind=='spear' and u.order=='hold' and u.stun<=0 and u.petrified<=0 and not u.get('routing',false) and now-u.get('last_stride',-1.)>=.25

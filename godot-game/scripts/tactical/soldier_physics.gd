extends RefCounted
## Independently implemented public physics pair response; terrain uses the authored pass geometry.

static func shield(actor: Dictionary) -> bool:
	return actor.get('shield_wall',false)

static func formation(actor: Dictionary) -> bool:
	return shield(actor) or actor.has('wall_slot') and actor.get('personal_order','')=='move'

static func random_axis(r) -> float:
	r.repulsion_seed=(r.repulsion_seed*1103515245+12345)&0xffffffff
	return float((r.repulsion_seed>>16)&32767)/16383.5-1.

static func pair_shift(r,a: Dictionary,b: Dictionary,dt: float) -> Vector2:
	var delta: Vector2=a.point-b.point
	var squared=delta.length_squared()
	var maximum: float=(a.radius+b.radius)*1.6
	if squared>=maximum*maximum:return Vector2.ZERO
	var left: Dictionary=a.unit.soldiers[a.slot];var right: Dictionary=b.unit.soldiers[b.slot]
	var friendly: bool=a.unit.side==b.unit.side
	if friendly and formation(left) and formation(right):return Vector2.ZERO
	var spread=1.2 if friendly else 1.1
	var strength=120. if friendly else 60.
	var cap=16.
	if not friendly and (shield(left) and delta.dot(left.get('wall_heading',left.heading))<0. or shield(right) and delta.dot(right.get('wall_heading',right.heading))>0.):
		spread=1.6;strength=200.;cap=32.
	return response(r,delta,(a.radius+b.radius)*spread,strength,cap,dt)

static func response(r,delta: Vector2,radius: float,strength: float,cap: float,dt: float) -> Vector2:
	var squared=delta.length_squared()
	if squared>=radius*radius:return Vector2.ZERO
	if squared<=.01:
		return Vector2(random_axis(r),random_axis(r))*minf(16.,dt*strength*.5)
	var shift=delta*(dt*strength/radius)*(1.-squared/(radius*radius))
	if squared<radius*radius*.16:shift*=1.+5.*(1.-squared/(radius*radius*.16))
	return shift.limit_length(cap)

static func terrain_slide(r,kind: String,from: Vector2,to: Vector2,u: Dictionary={}) -> Vector2:
	if from==to:return from
	var nav=r.Soldiers.navigator(r,kind,u)
	if r.terrain.clear_segment(nav,from,to):return to
	var x=Vector2(to.x,from.y);var y=Vector2(from.x,to.y)
	if r.terrain.clear_segment(nav,from,x):return x
	if r.terrain.clear_segment(nav,from,y):return y
	return from

static func integrate(r,rows: Array,dt: float):
	for row in rows:
		var u: Dictionary=row.unit;var actor: Dictionary=u.soldiers[row.slot]
		if actor.get('death_state',0)!=0 or not actor.has('position') or u.stun>0 or u.petrified>0:continue
		var speed: float=(u.combat_stats if u.has('combat_stats') else r.config.types[u.kind]).speed
		var cap=110. if shield(actor) else maxf(speed,r.config.individual_charge.speed)+60. if actor.has('charge_run') else speed+60.
		actor.velocity=actor.get('velocity',Vector2.ZERO).limit_length(cap)
		var impulse: Vector2=actor.get('impulse',Vector2.ZERO)
		var from: Vector2=actor.position
		var delta: Vector2=(actor.velocity+impulse)*dt
		# Keep authored thin rocks swept; normal motion and knockback share one proposed displacement.
		var pieces=maxi(1,ceili(delta.length()/4.))
		for i in pieces:actor.position=terrain_slide(r,u.kind,actor.position,actor.position+delta/pieces,u)
		row.point=actor.position
		if actor.has('charge_run'):
			actor.charge_run.velocity=actor.velocity
			# shortcut: authored rock stopping predates the native grid; replace with its axis rollback when ported.
			if actor.position.is_equal_approx(from) and not delta.is_zero_approx():
				actor.velocity=Vector2.ZERO;actor.charge_run.velocity=Vector2.ZERO
				if actor.charge_run.age>.15:r.Charges.finish(r,u,actor,'blocked')
		impulse*=pow(.85,dt*60.)
		if absf(impulse.x)<.5:impulse.x=0.
		if absf(impulse.y)<.5:impulse.y=0.
		if impulse==Vector2.ZERO:actor.erase('impulse')
		else:actor.impulse=impulse

static func repel(r,rows: Array,dt: float):
	r.repulsion_time+=dt
	if r.repulsion_time<1./30.-.000001:return
	var elapsed: float=r.repulsion_time;r.repulsion_time=0.
	# Use the pre-pass cell membership, then sequentially update the actual pair positions.
	r.Soldiers.prepare_neighbours(r,rows,elapsed)
	var points=PackedVector2Array();var radii=PackedFloat64Array();var headings=PackedVector2Array()
	var flags=PackedByteArray();var sides=PackedInt32Array();var teams={}
	for i in rows.size():
		var row: Dictionary=rows[i];var u: Dictionary=row.unit;var actor: Dictionary=u.soldiers[row.slot]
		row.physics_index=i;row.physics_from=row.point;points.append(row.point);radii.append(row.radius)
		headings.append(actor.get('wall_heading',actor.heading))
		flags.append(int(u.stun<=0 and u.petrified<=0 and actor.get('death_state',0)==0) | (int(shield(actor))<<1) | (int(formation(actor))<<2))
		if not teams.has(u.side):teams[u.side]=teams.size()
		sides.append(teams[u.side])
	for i in rows.size():
		if (flags[i]&1)==0:continue
		for other in rows[i].neighbours:
			var j: int=other.physics_index
			if j<=i or (flags[j]&1)==0:continue
			var delta=points[i]-points[j];var size: float=radii[i]+radii[j]
			if delta.length_squared()>=(size*1.6)*(size*1.6):continue
			var friendly: bool=sides[i]==sides[j]
			if friendly and flags[i]&4 and flags[j]&4:continue
			var spread=1.2 if friendly else 1.1
			var strength=120. if friendly else 60.;var cap=16.
			if not friendly and (flags[i]&2 and delta.dot(headings[i])<0. or flags[j]&2 and delta.dot(headings[j])>0.):
				spread=1.6;strength=200.;cap=32.
			var shift=response(r,delta,size*spread,strength,cap,elapsed)
			if shift==Vector2.ZERO:continue
			if (flags[i]&2)==0:points[i]+=shift
			if (flags[j]&2)==0:points[j]-=shift
	for row in rows:
		var actor: Dictionary=row.unit.soldiers[row.slot]
		var from: Vector2=row.physics_from
		var next=terrain_slide(r,row.unit.kind,from,points[row.physics_index],row.unit)
		if next!=from and not actor.has('position'):r.Charges.detach(r,row.unit,row.slot)
		if actor.has('position'):actor.position=next
		row.point=next;row.erase('physics_index');row.erase('physics_from')
		row.erase('neighbours')

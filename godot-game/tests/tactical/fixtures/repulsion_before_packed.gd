extends RefCounted
## Frozen pre-optimization kernel, 2026-11-06. Regression oracle; not a second gameplay implementation.

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
	var radius: float=(a.radius+b.radius)*spread
	if squared>=radius*radius:return Vector2.ZERO
	if squared<=.01:
		return Vector2(random_axis(r),random_axis(r))*minf(16.,dt*strength*.5)
	var shift=delta*(dt*strength/radius)*(1.-squared/(radius*radius))
	if squared<radius*radius*.16:shift*=1.+5.*(1.-squared/(radius*radius*.16))
	return shift.limit_length(cap)

static func terrain_slide(r,kind: String,from: Vector2,to: Vector2,u: Dictionary={}) -> Vector2:
	var nav=r.Soldiers.navigator(r,kind,u)
	if r.terrain.clear_segment(nav,from,to):return to
	var x=Vector2(to.x,from.y);var y=Vector2(from.x,to.y)
	if r.terrain.clear_segment(nav,from,x):return x
	if r.terrain.clear_segment(nav,from,y):return y
	return from

static func repel(r,rows: Array,dt: float):
	r.repulsion_time+=dt
	if r.repulsion_time<1./30.-.000001:return
	var elapsed: float=r.repulsion_time;r.repulsion_time=0.
	# Use the pre-pass cell membership, then sequentially update the actual pair positions.
	r.Soldiers.prepare_neighbours(r,rows,elapsed)
	var before=[]
	for i in rows.size():rows[i].physics_index=i;before.append(rows[i].point)
	for a in rows:
		if a.unit.stun>0 or a.unit.petrified>0 or a.unit.soldiers[a.slot].get('death_state',0)!=0:continue
		for b in a.neighbours:
			if b.physics_index<=a.physics_index or b.unit.stun>0 or b.unit.petrified>0 or b.unit.soldiers[b.slot].get('death_state',0)!=0:continue
			var shift=pair_shift(r,a,b,elapsed)
			if not shield(a.unit.soldiers[a.slot]):a.point+=shift
			if not shield(b.unit.soldiers[b.slot]):b.point-=shift
	for row in rows:
		var actor: Dictionary=row.unit.soldiers[row.slot]
		var from: Vector2=before[row.physics_index]
		var next=terrain_slide(r,row.unit.kind,from,row.point,row.unit)
		if next!=from and not actor.has('position'):r.Charges.detach(r,row.unit,row.slot)
		if actor.has('position'):actor.position=next
		row.point=next;row.erase('physics_index')
		row.erase('neighbours')
